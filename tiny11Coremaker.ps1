#---------[ Parameters ]---------#
param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [switch]$NonInteractive = $false,
    
    # Version selector (Auto, Pro, Home, ProWorkstations)
    [ValidateSet('Auto','Pro','Home','ProWorkstations')][string]$VersionSelector = 'Auto',
    
    # Optional debloat options (honored from workflow)
    [ValidateSet('yes','no')][string]$RemoveDefender = 'yes',
    [ValidateSet('yes','no')][string]$RemoveAI = 'yes',
    [ValidateSet('yes','no')][string]$RemoveEdge = 'yes',
    [ValidateSet('yes','no')][string]$RemoveStore = 'yes'
)

# Set error handling to continue on non-critical errors
# Script will only exit on critical failures (ISO creation, mounting, etc.)
$ErrorActionPreference = 'Continue'

if ((Get-ExecutionPolicy) -eq 'Restricted') {
    if ($NonInteractive) {
        Write-Host "Execution policy is Restricted. Attempting to set to RemoteSigned..."
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false -Force
    } else {
        Write-Host "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
        $response = Read-Host
        if ($response -eq 'yes') {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
        } else {
            Write-Host "The script cannot be run without changing the execution policy. Exiting..."
            exit
        }
    }
}

# Debloat settings - tự động enable theo chính sách của core maker
# RemoveDefender, RemoveAI, RemoveEdge, RemoveStore được set từ parameters (honored from workflow)
$EnableDebloat = 'yes'
$RemoveAppx = 'yes'
$RemoveCapabilities = 'yes'
$RemoveWindowsPackages = 'yes'
$RemoveOneDrive = 'yes'
$DisableTelemetry = 'yes'
$DisableSponsoredApps = 'yes'
$DisableAds = 'yes'
Write-Host "Debloat (core): Defender=$RemoveDefender, AI=$RemoveAI, Edge=$RemoveEdge, Store=$RemoveStore"

# Import debloater module
if ($EnableDebloat -eq 'yes') {
    $modulePath = Join-Path $PSScriptRoot "tiny11-debloater.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        Write-Host "Debloater module loaded"
    } else {
        Write-Warning "Debloater module not found at $modulePath. Debloat features will be disabled."
        $EnableDebloat = 'no'
    }
}

# Check and run the script as admin if required
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Host "Restarting Tiny11 image creator as admin in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}
Start-Transcript -Path "$PSScriptRoot\tiny11.log" 
# Ask the user for input
Write-Host "Welcome to tiny11 core builder! BETA 09-05-25"
Write-Host "This script generates a significantly reduced Windows 11 image. However, it's not suitable for regular use due to its lack of serviceability - you can't add languages, updates, or features post-creation. tiny11 Core is not a full Windows 11 substitute but a rapid testing or development tool, potentially useful for VM environments."

if ($NonInteractive) {
    Write-Host "Non-interactive mode enabled. Continuing automatically..."
    $input = 'y'
} else {
    Write-Host "Do you want to continue? (y/n)"
    $input = Read-Host
}

if ($input -eq 'y') {
    Write-Host "Off we go..."
    if (-not $NonInteractive) {
        Start-Sleep -Seconds 3
        Clear-Host
    }

$mainOSDrive = $env:SystemDrive
$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$mainOSDrive\tiny11\sources" >null

# Use ISO parameter if provided, otherwise prompt
if ($ISO) {
    $DriveLetter = $ISO + ":"
    Write-Host "Using ISO drive from parameter: $DriveLetter"
} else {
    if ($NonInteractive) {
        Write-Error "ISO parameter is required in non-interactive mode. Please provide -ISO parameter."
        exit 1
    }
    $DriveLetter = Read-Host "Please enter the drive letter for the Windows 11 image"
    $DriveLetter = $DriveLetter + ":"
}

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Host "Found install.esd, converting to install.wim..."
        $esdInfoOutput = & 'dism' '/English' "/Get-WimInfo" "/wimfile:$DriveLetter\sources\install.esd"
        $esdInfoOutput | Write-Host
        
        if ($NonInteractive) {
            # Auto-detect edition based on VersionSelector
            Write-Host "Auto-detecting edition based on VersionSelector: $VersionSelector"
            $wimInfo = $esdInfoOutput
            
            # Parse WIM info to find target editions
            $index = $null
            $targetEditions = @()
            $currentIndex = $null
            $currentName = $null
            
            foreach ($line in $wimInfo) {
                if ($line -match 'Index : (\d+)') {
                    $currentIndex = [int]$Matches[1]
                } elseif ($line -match 'Name : (.+)') {
                    $currentName = $Matches[1].Trim()
                    if ($currentIndex -and $currentName) {
                        $match = $false
                        $priority = 999
                        
                        switch ($VersionSelector) {
                            'Auto' {
                                # Auto mode: prefer Pro editions
                                if ($currentName -like '*Pro*' -and $currentName -notlike '*Home*') {
                                    $match = $true
                                    if ($currentName -eq 'Windows 11 Pro') {
                                        $priority = 1
                                    } elseif ($currentName -like '*Pro for Workstations*' -and $currentName -notlike '*N*') {
                                        $priority = 2
                                    } elseif ($currentName -like '*Pro Education*' -and $currentName -notlike '*N*') {
                                        $priority = 3
                                    } elseif ($currentName -like '*Pro*' -and $currentName -notlike '*N*') {
                                        $priority = 4
                                    } else {
                                        $priority = 5
                                    }
                                }
                            }
                            'Pro' {
                                # Pro mode: find exact Windows 11 Pro
                                if ($currentName -eq 'Windows 11 Pro') {
                                    $match = $true
                                    $priority = 1
                                }
                            }
                            'Home' {
                                # Home mode: find Windows 11 Home (non-N)
                                if ($currentName -like '*Home*' -and $currentName -notlike '*N*' -and $currentName -notlike '*Pro*') {
                                    $match = $true
                                    if ($currentName -eq 'Windows 11 Home') {
                                        $priority = 1
                                    } else {
                                        $priority = 2
                                    }
                                }
                            }
                            'ProWorkstations' {
                                # ProWorkstations mode: find Pro for Workstations
                                if ($currentName -like '*Pro for Workstations*' -and $currentName -notlike '*N*') {
                                    $match = $true
                                    $priority = 1
                                }
                            }
                        }
                        
                        if ($match) {
                            $targetEditions += @{
                                Index = $currentIndex
                                Name = $currentName
                                Priority = $priority
                            }
                        }
                        $currentIndex = $null
                        $currentName = $null
                    }
                }
            }
            
            if ($targetEditions.Count -gt 0) {
                # Sort by priority and select the best one
                $bestEdition = $targetEditions | Sort-Object Priority | Select-Object -First 1
                $index = $bestEdition.Index
                Write-Host "Found edition: $($bestEdition.Name) (Index: $index)" -ForegroundColor Green
            } else {
                # Fallback to index 1 if not found
                $index = 1
                Write-Host "Requested edition not found, using default index: $index" -ForegroundColor Yellow
            }
        } else {
            $index = Read-Host "Please enter the image index"
        }
        
        Write-Host ' '
        Write-Host 'Converting install.esd to install.wim. This may take a while...'
        & 'DISM' /Export-Image /SourceImageFile:"$DriveLetter\sources\install.esd" /SourceIndex:$index /DestinationImageFile:"$mainOSDrive\tiny11\sources\install.wim" /Compress:max /CheckIntegrity
    } else {
        Write-Host "Can't find Windows OS Installation files in the specified Drive Letter.."
        Write-Host "Please enter the correct DVD Drive Letter.."
        exit
    }
}

Write-Host "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$mainOSDrive\tiny11" -Recurse -Force > null

# Remove install.esd if it exists (we only need install.wim)
if (Test-Path "$mainOSDrive\tiny11\sources\install.esd") {
    Set-ItemProperty -Path "$mainOSDrive\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
    Remove-Item "$mainOSDrive\tiny11\sources\install.esd" -Force > $null 2>&1
    Write-Host "Removed install.esd (using install.wim instead)"
}

Write-Host "Copy complete!"
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    Clear-Host
}
Write-Host "Getting image information:"
$wimInfoOutput = & 'dism' '/English' "/Get-WimInfo" "/wimfile:$mainOSDrive\tiny11\sources\install.wim"
$wimInfoOutput | Write-Host

if ($NonInteractive) {
    # Auto-detect edition based on VersionSelector
    Write-Host "Auto-detecting edition based on VersionSelector: $VersionSelector"
    $wimInfo = $wimInfoOutput
    
    # Parse WIM info to find target editions
    $index = $null
    $targetEditions = @()
    $currentIndex = $null
    $currentName = $null
    
    foreach ($line in $wimInfo) {
        if ($line -match 'Index : (\d+)') {
            $currentIndex = [int]$Matches[1]
        } elseif ($line -match 'Name : (.+)') {
            $currentName = $Matches[1].Trim()
            if ($currentIndex -and $currentName) {
                $match = $false
                $priority = 999
                
                switch ($VersionSelector) {
                    'Auto' {
                        # Auto mode: prefer Pro editions
                        if ($currentName -like '*Pro*' -and $currentName -notlike '*Home*') {
                            $match = $true
                            if ($currentName -eq 'Windows 11 Pro') {
                                $priority = 1
                            } elseif ($currentName -like '*Pro for Workstations*' -and $currentName -notlike '*N*') {
                                $priority = 2
                            } elseif ($currentName -like '*Pro Education*' -and $currentName -notlike '*N*') {
                                $priority = 3
                            } elseif ($currentName -like '*Pro*' -and $currentName -notlike '*N*') {
                                $priority = 4
                            } else {
                                $priority = 5
                            }
                        }
                    }
                    'Pro' {
                        # Pro mode: find exact Windows 11 Pro
                        if ($currentName -eq 'Windows 11 Pro') {
                            $match = $true
                            $priority = 1
                        }
                    }
                    'Home' {
                        # Home mode: find Windows 11 Home (non-N)
                        if ($currentName -like '*Home*' -and $currentName -notlike '*N*' -and $currentName -notlike '*Pro*') {
                            $match = $true
                            if ($currentName -eq 'Windows 11 Home') {
                                $priority = 1
                            } else {
                                $priority = 2
                            }
                        }
                    }
                    'ProWorkstations' {
                        # ProWorkstations mode: find Pro for Workstations
                        if ($currentName -like '*Pro for Workstations*' -and $currentName -notlike '*N*') {
                            $match = $true
                            $priority = 1
                        }
                    }
                }
                
                if ($match) {
                    $targetEditions += @{
                        Index = $currentIndex
                        Name = $currentName
                        Priority = $priority
                    }
                }
                $currentIndex = $null
                $currentName = $null
            }
        }
    }
    
    if ($targetEditions.Count -gt 0) {
        # Sort by priority and select the best one
        $bestEdition = $targetEditions | Sort-Object Priority | Select-Object -First 1
        $index = $bestEdition.Index
        Write-Host "Found edition: $($bestEdition.Name) (Index: $index)" -ForegroundColor Green
    } else {
        # Fallback to index 1 if not found
        $index = 1
        Write-Host "Requested edition not found, using default index: $index" -ForegroundColor Yellow
    }
} else {
    $index = Read-Host "Please enter the image index"
}
Write-Host "Mounting Windows image. This may take a while."
$wimFilePath = "$mainOSDrive\tiny11\sources\install.wim" 
& takeown "/F" $wimFilePath 
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # This block will catch the error and suppress it.
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
New-Item -ItemType Directory -Force -Path "$mainOSDrive\scratchdir" > $null
& dism /English "/mount-image" "/imagefile:$mainOSDrive\tiny11\sources\install.wim" "/index:$index" "/mountdir:$mainOSDrive\scratchdir"

$imageIntl = & dism /English /Get-Intl "/Image:$mainOSDrive\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($languageLine) {
    $languageCode = $Matches[1]
    Write-Host "Default system UI language code: $languageCode"
} else {
    Write-Host "Default system UI language code not found."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($env:SystemDrive)\tiny11\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        # If the architecture is x64, replace it with amd64
        if ($architecture -eq 'x64') {
            $architecture = 'amd64'
        }
        Write-Host "Architecture: $architecture"
        break
    }
}

if (-not $architecture) {
    Write-Host "Architecture information not found."
}

Write-Host "Mounting complete! Performing removal of applications..."

# Sử dụng debloater module nếu được enable
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Host "Using integrated debloater from Windows-ISO-Debloater..."
    Remove-DebloatPackages -MountPath "$mainOSDrive\scratchdir" `
        -RemoveAppx:($RemoveAppx -eq 'yes') `
        -RemoveCapabilities:($RemoveCapabilities -eq 'yes') `
        -RemoveWindowsPackages:($RemoveWindowsPackages -eq 'yes') `
        -LanguageCode $languageCode `
        -RemoveStore:($RemoveStore -eq 'yes') `
        -RemoveAI:($RemoveAI -eq 'yes') `
        -RemoveDefender:($RemoveDefender -eq 'yes')
    
    Remove-DebloatFiles -MountPath "$mainOSDrive\scratchdir" `
        -RemoveEdge:($RemoveEdge -eq 'yes') `
        -RemoveOneDrive:($RemoveOneDrive -eq 'yes') `
        -Architecture $architecture
} else {
    # Fallback to original method
    Write-Host "Using original package removal method..."
    $packages = & 'dism' '/English' "/image:$mainOSDrive\scratchdir" '/Get-ProvisionedAppxPackages' |
        ForEach-Object {
            if ($_ -match 'PackageName : (.*)') {
                $matches[1]
            }
        }
    $packagePrefixes = 'Clipchamp.Clipchamp_', 'Microsoft.BingNews_', 'Microsoft.BingWeather_', 'Microsoft.BingSports_', 'Microsoft.BingFinance_', 'Microsoft.GamingApp_', 'Microsoft.GetHelp_', 'Microsoft.Getstarted_', 'Microsoft.MicrosoftOfficeHub_', 'Microsoft.MicrosoftSolitaireCollection_', 'Microsoft.Microsoft3DViewer_', 'Microsoft.MicrosoftStickyNotes_', 'Microsoft.People_', 'Microsoft.PowerAutomateDesktop_', 'Microsoft.Todos_', 'Microsoft.WindowsAlarms_', 'microsoft.windowscommunicationsapps_', 'Microsoft.WindowsFeedbackHub_', 'Microsoft.WindowsMaps_', 'Microsoft.WindowsSoundRecorder_', 'Microsoft.WindowsCamera_', 'Microsoft.WindowsCalculator_', 'Microsoft.WindowsNotepad_', 'Microsoft.WindowsPaint_', 'Microsoft.WindowsTerminal_', 'Microsoft.WindowsTips_', 'Microsoft.OneDrive_', 'Microsoft.OneDriveSync_', 'Microsoft.ScreenSketch_', 'Microsoft.Windows.Search.Cortana_', 'Microsoft.SkypeApp_', 'Microsoft.Office.OneNote_', 'Microsoft.Xbox.TCUI_', 'Microsoft.XboxGamingOverlay_', 'Microsoft.XboxGameOverlay_', 'Microsoft.XboxSpeechToTextOverlay_', 'Microsoft.XboxApp_', 'Microsoft.XboxIdentityProvider_', 'Microsoft.YourPhone_', 'Microsoft.ZuneMusic_', 'Microsoft.ZuneVideo_', 'MicrosoftCorporationII.MicrosoftFamily_', 'MicrosoftCorporationII.QuickAssist_', 'MicrosoftTeams_', 'MSTeams_', 'Microsoft.OutlookForWindows_', 'Microsoft.Windows.Teams_'
    
    # Honor RemoveAI and RemoveStore parameters - filter out AI/Copilot and Store packages if they should be kept
    if ($RemoveAI -eq 'no') {
        # Remove AI/Copilot packages from removal list
        $packagePrefixes = $packagePrefixes | Where-Object { $_ -notlike '*549981C3F5F10*' -and $_ -notlike '*Copilot*' }
    } else {
        # Add AI/Copilot packages if RemoveAI = yes
        $packagePrefixes += 'Microsoft.549981C3F5F10_', 'Microsoft.Windows.Copilot', 'Microsoft.Copilot_'
    }
    
    if ($RemoveStore -eq 'no') {
        # Filter out Store packages (they will be kept)
        # Note: Store packages are not in packagePrefixes list, they're handled separately
        Write-Host "Keeping Microsoft Store (RemoveStore=no)" -ForegroundColor Green
    }

    $packagesToRemove = $packages | Where-Object {
        $packageName = $_
        $shouldRemove = $false
        
        # Check if package matches any prefix
        foreach ($prefix in $packagePrefixes) {
            if ($packageName -like "$prefix*") {
                $shouldRemove = $true
                break
            }
        }
        
        # Honor RemoveAI parameter - keep AI/Copilot packages if RemoveAI = no
        if ($RemoveAI -eq 'no') {
            if ($packageName -like '*Copilot*' -or $packageName -like '*549981C3F5F10*') {
                $shouldRemove = $false
                Write-Host "  Keeping AI package: $packageName" -ForegroundColor Gray
            }
        }
        
        # Honor RemoveStore parameter - keep Store packages if RemoveStore = no
        if ($RemoveStore -eq 'no') {
            if ($packageName -like '*WindowsStore*' -or $packageName -like '*StorePurchaseApp*' -or $packageName -like '*Store.Engagement*') {
                $shouldRemove = $false
                Write-Host "  Keeping Store package: $packageName" -ForegroundColor Gray
            }
        }
        
        $shouldRemove
    }
    foreach ($package in $packagesToRemove) {
        write-host "Removing $package :"
        $result = & 'dism' '/English' "/image:$mainOSDrive\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package" 2>&1
        if ($LASTEXITCODE -ne 0 -or ($result | Select-String -Pattern "Error|failed|not found" -Quiet)) {
            Write-Host "  Warning: Failed to remove $package (continuing...)" -ForegroundColor Yellow
        }
    }

    Write-Host "Removing of system apps complete! Now proceeding to removal of system packages..."
    
    $scratchDir = "$mainOSDrive\scratchdir"
    $packagePatterns = @(
        "Microsoft-Windows-InternetExplorer-Optional-Package~31bf3856ad364e35",
        "Microsoft-Windows-Kernel-LA57-FoD-Package~31bf3856ad364e35~amd64",
        "Microsoft-Windows-LanguageFeatures-Handwriting-$languageCode-Package~31bf3856ad364e35",
        "Microsoft-Windows-LanguageFeatures-OCR-$languageCode-Package~31bf3856ad364e35",
        "Microsoft-Windows-LanguageFeatures-Speech-$languageCode-Package~31bf3856ad364e35",
        "Microsoft-Windows-LanguageFeatures-TextToSpeech-$languageCode-Package~31bf3856ad364e35",
        "Microsoft-Windows-MediaPlayer-Package~31bf3856ad364e35",
        "Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~31bf3856ad364e35",
        "Microsoft-Windows-WordPad-FoD-Package~",
        "Microsoft-Windows-TabletPCMath-Package~",
        "Microsoft-Windows-StepsRecorder-Package~"
    )
    # Honor RemoveDefender parameter from workflow
    if ($RemoveDefender -eq 'yes') {
        $packagePatterns += "Windows-Defender-Client-Package~31bf3856ad364e35~"
    } else {
        Write-Host "Keeping Windows Defender (RemoveDefender=no)"
    }

    # Get all packages
    $allPackages = & dism /image:$scratchDir /Get-Packages /Format:Table
    $allPackages = $allPackages -split "`n" | Select-Object -Skip 1

    foreach ($packagePattern in $packagePatterns) {
        # Filter the packages to remove
        $packagesToRemove = $allPackages | Where-Object { $_ -like "$packagePattern*" }

    foreach ($package in $packagesToRemove) {
        # Extract the package identity
        $packageIdentity = ($package -split "\s+")[0]

        Write-Host "Removing $packageIdentity..."
        try {
            $result = & dism /image:$scratchDir /Remove-Package /PackageName:$packageIdentity 2>&1
            $outputString = $result -join "`n"
            
            if ($LASTEXITCODE -ne 0 -or ($outputString | Select-String -Pattern "Removal failed|Error|failed|cannot|not found" -Quiet)) {
                Write-Host "  Warning: Failed to remove $packageIdentity (continuing...)" -ForegroundColor Yellow
            } else {
                Write-Host "  ✓ Removed successfully" -ForegroundColor Green
            }
        } catch {
            Write-Host "  Warning: Exception removing $packageIdentity - $($_.Exception.Message) (continuing...)" -ForegroundColor Yellow
        }
    }
    }
}

Start-Sleep -Seconds 1
if (-not $NonInteractive) {
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}

# Enable .NET Framework 3.5 automatically for core build
Write-Host "Enabling .NET Framework 3.5..."
try {
    & 'dism' "/image:$mainOSDrive\scratchdir" '/enable-feature' '/featurename:NetFX3' '/All' "/source:$($env:SystemDrive)\tiny11\sources\sxs" 
    if ($LASTEXITCODE -eq 0) {
        Write-Host ".NET 3.5 has been enabled successfully." -ForegroundColor Green
    } else {
        Write-Warning "Failed to enable .NET 3.5 (exit code: $LASTEXITCODE). Continuing..."
    }
} catch {
    Write-Warning "Error enabling .NET 3.5: $($_.Exception.Message). Continuing..."
}
# Chỉ chạy method cũ nếu debloater không được enable
if ($EnableDebloat -ne 'yes' -or -not (Get-Module -Name tiny11-debloater)) {
    # Honor RemoveEdge parameter from workflow
    if ($RemoveEdge -eq 'yes') {
        Write-Host "Removing Edge:"
        Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force >null
        Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force >null
        Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force >null
        
        if ($architecture -eq 'amd64') {
            $folderPath = Get-ChildItem -Path "$mainOSDrive\scratchdir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName

            if ($folderPath) {
                & 'takeown' '/f' $folderPath '/r' >null
                & icacls $folderPath  "/grant" "$($adminGroup.Value):(F)" '/T' '/C' >null
                Remove-Item -Path $folderPath -Recurse -Force >null
            } else {
                Write-Host "Folder not found."
            }
        } elseif ($architecture -eq 'arm64') {
            $folderPath = Get-ChildItem -Path "$mainOSDrive\scratchdir\Windows\WinSxS" -Filter "arm64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName >null

            if ($folderPath) {
                & 'takeown' '/f' $folderPath '/r'>null
                & icacls $folderPath  "/grant" "$($adminGroup.Value):(F)" '/T' '/C' >null
                Remove-Item -Path $folderPath -Recurse -Force >null
            } else {
                Write-Host "Folder not found."
            }
        } else {
            Write-Host "Unknown architecture: $architecture"
        }
        & 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r'
        & 'icacls' "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C'
        Remove-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force
    } else {
        Write-Host "Keeping Edge (RemoveEdge=no)"
    }
    
    Write-Host "Removing WinRE"
    & 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\System32\Recovery" '/r'
    & 'icacls' "$mainOSDrive\scratchdir\Windows\System32\Recovery" '/grant' 'Administrators:F' '/T' '/C'
    Remove-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Recovery\winre.wim" -Recurse -Force
    New-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Recovery\winre.wim" -ItemType File -Force
    
    Write-Host "Removing OneDrive:"
    & 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\System32\OneDriveSetup.exe" >null
    & 'icacls' "$mainOSDrive\scratchdir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' >null
    Remove-Item -Path "$mainOSDrive\scratchdir\Windows\System32\OneDriveSetup.exe" -Force >null
    
    Write-Host "Removing OneDrive Start Menu shortcuts:"
    $startMenuPaths = @(
        "$mainOSDrive\scratchdir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$mainOSDrive\scratchdir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive",
        "$mainOSDrive\scratchdir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$mainOSDrive\scratchdir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive"
    )
    
    foreach ($shortcutPath in $startMenuPaths) {
        if (Test-Path $shortcutPath) {
            & 'takeown' '/f' $shortcutPath '/r' >null
            & 'icacls' $shortcutPath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' >null
            Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue >null
        }
    }
}

Write-Host "Removal complete!"
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Host "Taking ownership of the WinSxS folder. This might take a while..."
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\WinSxS" '/r'
& 'icacls' "$mainOSDrive\scratchdir\Windows\WinSxS" '/grant' "$($adminGroup.Value):(F)" '/T' '/C'
Write-host "Complete!"
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Host "Preparing..."
$folderPath = Join-Path -Path $mainOSDrive -ChildPath "\scratchdir\Windows\WinSxS_edit"
$sourceDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS"
$destinationDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS_edit"
New-Item -Path $folderPath -ItemType Directory
if ($architecture -eq "amd64") {
   $dirsToCopy = @(
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",    
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "x86_microsoft-windows-s..ngstack-onecorebase_31bf3856ad364e35_*",
        "x86_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack-inetsrv_*",
        "x86_microsoft-windows-servicingstack-onecore_*",
        "amd64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "amd64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "amd64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "amd64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "amd64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "amd64_microsoft-windows-s..stack-inetsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-msg.resources_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs",
        "FileMaps",
        "Fusion",
        "InstallTemp",
        "Manifests",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*"
    )
 # Copy each directory
   foreach ($dir in $dirsToCopy) {
        $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory
        foreach ($sourceDir in $sourceDirs) {
            $destDir = Join-Path -Path $destinationDirectory -ChildPath $sourceDir.Name
            Write-Host "Copying $sourceDir.FullName to $destDir"
            Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force
        }
    }
}
 elseif ($architecture -eq "arm64") {
    # Specify the list of files to copy
     $dirsToCopy = @(
        "arm64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs",
        "FileMaps",
        "Fusion",
        "InstallTemp",
        "Manifests",
        "SettingsManifests",
        "Temp",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft-windows-servicing-adm_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingcommon_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicing-onecore-uapi_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*"
    )
}
foreach ($dir in $dirsToCopy) {
        $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory
        foreach ($sourceDir in $sourceDirs) {
            $destDir = Join-Path -Path $destinationDirectory -ChildPath $sourceDir.Name
            Write-Host "Copying $sourceDir.FullName to $destDir"
            Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force
        }
    }  


Write-Host "Deleting WinSxS. This may take a while..."
        Remove-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS -Recurse -Force

Rename-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS_edit -NewName $mainOSDrive\scratchdir\Windows\WinSxS
Write-Host "Complete!"

Write-Host "Loading registry..."
reg load HKLM\zCOMPONENTS $mainOSDrive\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM | Out-Null
Write-Host "Bypassing system requirements(on the system image):"
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Disabling Sponsored Apps:"
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'OemPreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SilentInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableWindowsConsumerFeatures' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'ContentDeliveryAllowed' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' '/v' 'ConfigureStartPins' '/t' 'REG_SZ' '/d' '{"pinnedList": [{}]}' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'FeatureManagementEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'OemPreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEverEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SilentInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SoftLandingEnabled' '/t' 'REG_DWORD' '/d' '0' '/f'| Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContentEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-310093Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338388Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338389Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338393Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353694Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353696Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SystemPaneSuggestionsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' '/v' 'DisablePushToInstall' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' '/v' 'DontOfferThroughWUAU' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableConsumerAccountStateContent' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableCloudOptimizedContent' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null

# Apply debloater registry tweaks nếu được enable
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Host "Applying debloater registry tweaks..."
    Apply-DebloatRegistryTweaks -RegistryPrefix "HKLM\z" `
        -DisableTelemetry:($DisableTelemetry -eq 'yes') `
        -DisableSponsoredApps:($DisableSponsoredApps -eq 'yes') `
        -DisableAds:($DisableAds -eq 'yes') `
        -DisableBitlocker:$true `
        -DisableOneDrive:($RemoveOneDrive -eq 'yes') `
        -DisableGameDVR:$true `
        -TweakOOBE:$true `
        -DisableUselessJunks:$true
}

Write-Host "Enabling Local Accounts on OOBE:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'BypassNRO' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
# Ensure Sysprep directory exists before copying autounattend.xml
$sysprepDir = "$mainOSDrive\scratchdir\Windows\System32\Sysprep"
if (-not (Test-Path $sysprepDir)) {
    New-Item -ItemType Directory -Path $sysprepDir -Force | Out-Null
}
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$sysprepDir\autounattend.xml" -Force | Out-Null
Write-Host "Disabling Reserved Storage:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' '/v' 'ShippedWithReserves' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
Write-Host "Disabling BitLocker Device Encryption"
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' '/v' 'PreventDeviceEncryption' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Disabling Chat icon:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' '/v' 'ChatIcon' '/t' 'REG_DWORD' '/d' '3' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' '/v' 'TaskbarMn' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
# Honor RemoveEdge parameter from workflow
if ($RemoveEdge -eq 'yes') {
    Write-Host "Removing Edge related registries"
    reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f | Out-Null
    reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f | Out-Null
}

# Honor RemoveAI parameter from workflow - disable Copilot/AI
if ($RemoveAI -eq 'yes') {
    Write-Host "Disabling Copilot/AI..."
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' '/v' 'TurnOffWindowsCopilot' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' '/v' 'HubsSidebarEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' '/v' 'DisableSearchBoxSuggestions' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
} else {
    Write-Host "Keeping Copilot/AI enabled (RemoveAI=no)"
}

# Honor RemoveStore parameter from workflow - disable Store
if ($RemoveStore -eq 'yes') {
    Write-Host "Disabling Microsoft Store..."
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\WindowsStore' '/v' 'RemoveWindowsStore' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
    & 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned' '/v' 'Microsoft.WindowsStore_8wekyb3d8bbwe' '/t' 'REG_SZ' '/d' '' '/f' | Out-Null
} else {
    Write-Host "Keeping Microsoft Store enabled (RemoveStore=no)"
}

Write-Host "Disabling OneDrive folder backup"
& 'reg' 'add' "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" '/v' 'DisableFileSyncNGSC' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Disabling Telemetry:"
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' '/v' 'TailoredExperiencesWithDiagnosticDataEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' '/v' 'HasAccepted' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitInkCollection' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitTextCollection' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' '/v' 'HarvestContacts' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' '/v' 'AcceptedPrivacyPolicy' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' '/v' 'AllowTelemetry' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f' | Out-Null
Write-Host "Prevents installation or DevHome and Outlook:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' '/v' 'workCompleted' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' '/v' 'workCompleted' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' '/f' | Out-Null
# Note: Copilot/AI disable is handled above based on RemoveAI parameter
Write-Host "Prevents installation of Teams:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' '/v' 'DisableInstallation' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Prevent installation of New Outlook":
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' '/v' 'PreventRun' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
$tasksPath = "$mainOSDrive\scratchdir\Windows\System32\Tasks"

Write-Host "Deleting scheduled task definition files..."

# Application Compatibility Appraiser
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue

# Customer Experience Improvement Program (removes the entire folder and all tasks within it)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue

# Program Data Updater
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue

# Chkdsk Proxy
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue

# Windows Error Reporting (QueueReporting)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue

Write-Host "Task files have been deleted."
Write-Host "Disabling Windows Update..."
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE1' '/t' 'REG_SZ' '/d' 'net stop wuauserv' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE2' '/t' 'REG_SZ' '/d' 'sc stop wuauserv' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE3' '/t' 'REG_SZ' '/d' 'sc config wuauserv start= disabled' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisableWUPostOOBE1' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\wuauserv /v Start /t REG_DWORD /d 4 /f' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisableWUPostOOBE2' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\ControlSet001\Services\wuauserv /v Start /t REG_DWORD /d 4 /f' '/f'
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'DoNotConnectToWindowsUpdateInternetLocations' '/t' 'REG_DWORD' '/d' '1' '/f'
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'DisableWindowsUpdateAccess' '/t' 'REG_DWORD' '/d' '1' '/f' 
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'WUServer' '/t' 'REG_SZ' '/d' 'localhost' '/f' 
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'WUStatusServer' '/t' 'REG_SZ' '/d' 'localhost' '/f' 
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'UpdateServiceUrlAlternate' '/t' 'REG_SZ' '/d' 'localhost' '/f' 
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' '/v' 'UseWUServer' '/t' 'REG_DWORD' '/d' '1' '/f' 
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'DisableOnline' '/t' 'REG_DWORD' '/d' '1' '/f' 
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv' '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f' 
& 'reg' 'delete' 'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSVC' '/f'
& 'reg' 'delete' 'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc' '/f'
& 'reg' 'add' 'HKEY_LOCAL_MACHINE\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' '/v' 'NoAutoUpdate' '/t' 'REG_DWORD' '/d' '1' '/f'
# Honor RemoveDefender parameter from workflow
if ($RemoveDefender -eq 'yes') {
    Write-Host "Disabling Windows Defender"
    # Set registry values for Windows Defender services
    $servicePaths = @(
        "WinDefend",
        "WdNisSvc",
        "WdNisDrv",
        "WdFilter",
        "Sense"
    )

    foreach ($path in $servicePaths) {
        Set-ItemProperty -Path "HKLM:\zSYSTEM\ControlSet001\Services\$path" -Name "Start" -Value 4
    }
    & 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' '/v' 'SettingsPageVisibility' '/t' 'REG_SZ' '/d' 'hide:virus;windowsupdate' '/f'
} else {
    Write-Host "Keeping Windows Defender enabled (RemoveDefender=no)"
} 
Write-Host "Tweaking complete!"
Write-Host "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null
Write-Host "Cleaning up image..."
& 'dism' '/English' "/image:$mainOSDrive\scratchdir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' >null
Write-Host "Cleanup complete."
Write-Host ' '
Write-Host "Unmounting image..."
& 'dism' '/English' '/unmount-image' "/mountdir:$mainOSDrive\scratchdir" '/commit'
Write-Host "Exporting image..."
& 'dism' '/English' '/Export-Image' "/SourceImageFile:$mainOSDrive\tiny11\sources\install.wim" "/SourceIndex:$index" "/DestinationImageFile:$mainOSDrive\tiny11\sources\install2.wim" '/compress:max'
Remove-Item -Path "$mainOSDrive\tiny11\sources\install.wim" -Force >null
Rename-Item -Path "$mainOSDrive\tiny11\sources\install2.wim" -NewName "install.wim" >null
Write-Host "Windows image completed. Continuing with boot.wim."
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Host "Mounting boot image (keeping both WinPE classic menu and Windows Setup)..."
$wimFilePath = "$($env:SystemDrive)\tiny11\sources\boot.wim" 
& takeown "/F" $wimFilePath >null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
Write-Host "Mounting Windows Setup image (index 2) to modify registry (index 1 - WinPE classic menu will be preserved)..."
& 'dism' '/English' '/mount-image' "/imagefile:$mainOSDrive\tiny11\sources\boot.wim" '/index:2' "/mountdir:$mainOSDrive\scratchdir"
Write-Host "Loading registry..."
reg load HKLM\zCOMPONENTS $mainOSDrive\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM
Write-Host "Bypassing system requirements(on the setup image):"
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' >null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' >null
# Removed CmdLine registry key to preserve WinPE classic boot menu (index 1)
# & 'reg' 'add' 'HKEY_LOCAL_MACHINE\zSYSTEM\Setup' '/v' 'CmdLine' '/t' 'REG_SZ' '/d' 'X:\sources\setup.exe' '/f' >null
Write-Host "Tweaking complete!"
Write-Host "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null
Write-Host "Unmounting image (keeping both indexes intact)..."
& 'dism' '/English' '/unmount-image' "/mountdir:$mainOSDrive\scratchdir" '/commit'
if (-not $NonInteractive) {
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Host "Exporting ESD. This may take a while..."
& dism /Export-Image /SourceImageFile:"$mainOSDrive\tiny11\sources\install.wim" /SourceIndex:1 /DestinationImageFile:"$mainOSDrive\tiny11\sources\install.esd" /Compress:recovery
Remove-Item "$mainOSDrive\tiny11\sources\install.wim" > $null 2>&1
Write-Host "The tiny11 image is now completed. Proceeding with the making of the ISO..."
Write-Host "Creating ISO image..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostarchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Host "Will be using oscdimg.exe from system ADK."
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Host "ADK folder not found. Will be using bundled oscdimg.exe."
    
    
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Host "Downloading oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

        if (Test-Path $localOSCDIMGPath) {
            Write-Host "oscdimg.exe downloaded successfully."
        } else {
            Write-Error "Failed to download oscdimg.exe."
            exit 1
        }
    } else {
        Write-Host "oscdimg.exe already exists locally."
    }

    $OSCDIMG = $localOSCDIMGPath
}

Write-Host "Running oscdimg to create ISO..."
$isoPath = "$PSScriptRoot\tiny11-core.iso"
try {
    & "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$mainOSDrive\tiny11\boot\etfsboot.com#pEF,e,b$mainOSDrive\tiny11\efi\microsoft\boot\efisys.bin" "$mainOSDrive\tiny11" $isoPath 2>&1 | Out-Null
    
    # Verify ISO was created
    Start-Sleep -Seconds 2
    if (-not (Test-Path $isoPath)) {
        Write-Error "ISO was not created at expected path: $isoPath"
        exit 1
    }
    
    $isoSize = (Get-Item $isoPath).Length / 1GB
    Write-Host "✓ ISO created successfully: $isoPath" -ForegroundColor Green
    Write-Host "  ISO size: $([math]::Round($isoSize, 2)) GB"
} catch {
    Write-Error "Failed to create ISO: $($_.Exception.Message)"
    exit 1
}

# Finishing up
Write-Host "Creation completed! Press any key to exit the script..."
if ($NonInteractive) {
    Write-Host "Build complete! Cleaning up..."
} else {
    Read-Host "Press Enter to continue"
}
Write-Host "Performing Cleanup..."
Remove-Item -Path "$mainOSDrive\tiny11" -Recurse -Force >null
Remove-Item -Path "$mainOSDrive\scratchdir" -Recurse -Force >null

# Stop the transcript
Stop-Transcript

exit
}
elseif ($input -eq 'n') {
    Write-Host "You chose not to continue. The script will now exit."
    exit
}
else {
    Write-Host "Invalid input. Please enter 'y' to continue or 'n' to exit."
}
