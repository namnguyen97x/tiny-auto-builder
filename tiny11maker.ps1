<#
.SYNOPSIS
    Scripts to build a trimmed-down Windows 11 image.

.DESCRIPTION
    This is a script created to automate the build of a streamlined Windows 11 image, similar to tiny10.
    My main goal is to use only Microsoft utilities like DISM, and no utilities from external sources.
    The only executable included is oscdimg.exe, which is provided in the Windows ADK and it is used to create bootable ISO images.

.PARAMETER ISO
    Drive letter given to the mounted iso (eg: E)

.PARAMETER SCRATCH
    Drive letter of the desired scratch disk (eg: D)

.EXAMPLE
    .\tiny11maker.ps1 E D
    .\tiny11maker.ps1 -ISO E -SCRATCH D
    .\tiny11maker.ps1 -SCRATCH D -ISO E
    .\tiny11maker.ps1

    *If you ordinal parameters the first one must be the mounted iso. The second is the scratch drive.
    prefer the use of full named parameter (eg: "-ISO") as you can put in the order you want.

.NOTES
    Auteur: ntdevlabs
    Date: 09-07-25
#>

#---------[ Parameters ]---------#
param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH,
    
    # Optional debloat options (chỉ áp dụng cho maker)
    [ValidateSet('yes','no')][string]$RemoveDefender = 'no',
    [ValidateSet('yes','no')][string]$RemoveAI = 'yes',
    [ValidateSet('yes','no')][string]$RemoveEdge = 'yes',
    [ValidateSet('yes','no')][string]$RemoveStore = 'yes',
    
    # Non-interactive mode for CI/CD
    [switch]$NonInteractive = $false,
    
    # Version selector (Auto, Pro, Home, ProWorkstations)
    [ValidateSet('Auto','Pro','Home','ProWorkstations')][string]$VersionSelector = 'Auto',
    
    # Custom ISO filename (optional, defaults to maker.iso or tiny11.iso)
    [string]$IsoName = '',
    
    # IRST driver path (optional, path to folder containing IRST driver .inf files)
    # If not provided, will use IRST_Driver folder in project root
    [string]$IrstDriverPath = ''
)

# Set error handling to continue on non-critical errors
# Script will only exit on critical failures (ISO creation, mounting, etc.)
$ErrorActionPreference = 'Continue'

if (-not $SCRATCH) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $SCRATCH + ":"
}

# Debloat settings - tự động enable theo chính sách của maker
$EnableDebloat = 'yes'
$RemoveAppx = 'yes'
$RemoveCapabilities = 'yes'
$RemoveWindowsPackages = 'yes'
$RemoveOneDrive = 'yes'
$DisableTelemetry = 'yes'
$DisableSponsoredApps = 'yes'
$DisableAds = 'yes'

# Optional debloat options (có thể tùy chỉnh)
# $RemoveDefender, $RemoveAI, $RemoveEdge, $RemoveStore được set từ parameters

# Import debloater module
if ($EnableDebloat -eq 'yes') {
    $modulePath = Join-Path $PSScriptRoot "tiny11-debloater.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        Write-Output "Debloater module loaded"
    } else {
        Write-Warning "Debloater module not found at $modulePath. Debloat features will be disabled."
        $EnableDebloat = 'no'
    }
}

#---------[ Functions ]---------#
function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
        Write-Output "Set registry value: $path\$name"
    } catch {
        Write-Output "Error setting registry value: $_"
    }
}

function Remove-RegistryValue {
    param (
		[string]$path
	)
	try {
		& 'reg' 'delete' $path '/f' | Out-Null
		Write-Output "Removed registry value: $path"
	} catch {
		Write-Output "Error removing registry value: $_"
	}
}

function Add-DriverToImage {
    param (
        [string]$MountPath,
        [string]$DriverPath,
        [string]$ImageName
    )
    
    # If no driver path provided, try to use IRST_Driver folder in project root
    if (-not $DriverPath -or -not (Test-Path $DriverPath)) {
        $projectIrstFolder = Join-Path $PSScriptRoot "IRST_Driver"
        if (Test-Path $projectIrstFolder) {
            Write-Host "Using IRST driver from project folder: $projectIrstFolder" -ForegroundColor Cyan
            $DriverPath = $projectIrstFolder
        } else {
            Write-Host "IRST driver path not provided and IRST_Driver folder not found, skipping driver injection." -ForegroundColor Yellow
            return
        }
    }
    
    Write-Host "Injecting IRST driver into $ImageName..." -ForegroundColor Cyan
    Write-Host "Driver path: $DriverPath" -ForegroundColor Gray
    
    # Check if DriverPath contains multiple driver folders (like IRST_Driver folder structure)
    $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    if (-not $infFiles) {
        Write-Warning "No .inf files found in driver path: $DriverPath"
        return
    }
    
    # If DriverPath contains subfolders with .inf files, inject each subfolder separately
    $driverFolders = Get-ChildItem -Path $DriverPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        $infInFolder = Get-ChildItem -Path $_.FullName -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
        $infInFolder.Count -gt 0
    }
    
    if ($driverFolders.Count -gt 0) {
        # Multiple driver folders found (like IRST_Driver structure)
        Write-Host "Found $($driverFolders.Count) driver folder(s) to inject..." -ForegroundColor Cyan
        $successCount = 0
        $failCount = 0
        
        foreach ($driverFolder in $driverFolders) {
            Write-Host "  Injecting: $($driverFolder.Name)..." -ForegroundColor Gray
            try {
                $result = & dism /English /image:"$MountPath" /add-driver /driver:"$($driverFolder.FullName)" /recurse 2>&1
                $outputString = $result -join "`n"
                
                if ($LASTEXITCODE -eq 0 -and -not ($outputString | Select-String -Pattern "Error|Failed|failed" -Quiet)) {
                    Write-Host "    ✓ Success" -ForegroundColor Green
                    $successCount++
                } else {
                    Write-Warning "    ✗ Failed (exit code: $LASTEXITCODE)"
                    $failCount++
                }
            } catch {
                Write-Warning "    ✗ Error: $($_.Exception.Message)"
                $failCount++
            }
        }
        
        Write-Host "Driver injection completed: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    } else {
        # Single driver folder or flat structure
        try {
            $result = & dism /English /image:"$MountPath" /add-driver /driver:"$DriverPath" /recurse 2>&1
            $outputString = $result -join "`n"
            
            if ($LASTEXITCODE -eq 0 -and -not ($outputString | Select-String -Pattern "Error|Failed|failed" -Quiet)) {
                Write-Host "IRST driver injected successfully into $ImageName" -ForegroundColor Green
            } else {
                Write-Warning "Failed to inject IRST driver into $ImageName (exit code: $LASTEXITCODE)"
                Write-Warning "Output: $outputString"
            }
        } catch {
            Write-Warning "Error injecting IRST driver into ${ImageName}: $($_.Exception.Message)"
        }
    }
}

#---------[ Execution ]---------#
# Check if PowerShell execution is restricted
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    if ($NonInteractive) {
        Write-Output "Execution policy is Restricted. Attempting to set to RemoteSigned..."
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false -Force
    } else {
        Write-Output "Your current PowerShell Execution Policy is set to Restricted, which prevents scripts from running. Do you want to change it to RemoteSigned? (yes/no)"
        $response = Read-Host
        if ($response -eq 'yes') {
            Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
        } else {
            Write-Output "The script cannot be run without changing the execution policy. Exiting..."
            exit
        }
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
    Write-Output "Restarting Tiny11 image creator as admin in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

if (-not (Test-Path -Path "$PSScriptRoot/autounattend.xml")) {
    Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile "$PSScriptRoot/autounattend.xml"
}

# Start the transcript and prepare the window
Start-Transcript -Path "$PSScriptRoot\tiny11_$(get-date -f yyyyMMdd_HHmms).log"

# Set window title only in interactive mode
if (-not $NonInteractive) {
    try {
        $Host.UI.RawUI.WindowTitle = "Tiny11 image creator"
        Clear-Host
    } catch {
        # Ignore errors in non-interactive environments
    }
}
Write-Output "Welcome to the tiny11 image creator! Release: 09-07-25"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
do {
    if (-not $ISO) {
        if ($NonInteractive) {
            Write-Error "ISO parameter is required in non-interactive mode. Please provide -ISO parameter."
            exit 1
        }
        $DriveLetter = Read-Host "Please enter the drive letter for the Windows 11 image"
    } else {
        $DriveLetter = $ISO
    }
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "Drive letter set to $DriveLetter"
        break
    } else {
        if ($NonInteractive) {
            Write-Error "Invalid drive letter format: $DriveLetter"
            exit 1
        }
        Write-Output "Invalid drive letter. Please enter a letter between C and Z."
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$' -and -not $NonInteractive)

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Output "Found install.esd, converting to install.wim..."
        $esdInfo = Get-WindowsImage -ImagePath "$DriveLetter\sources\install.esd"
        $esdInfo | Format-Table -AutoSize | Out-String | Write-Host
        
        if ($NonInteractive) {
            # Auto-detect image index (use first available index, usually 1)
            $index = 1
            if ($esdInfo) {
                $index = $esdInfo[0].ImageIndex
            }
            Write-Output "Auto-detected image index: $index"
        } else {
            $index = Read-Host "Please enter the image index"
        }
        
        Write-Output ' '
        Write-Output 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath $ScratchDisk\tiny11\sources\install.wim -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "Can't find Windows OS Installation files in the specified Drive Letter.."
        Write-Output "Please enter the correct DVD Drive Letter.."
        exit
    }
}

Write-Output "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null

# Remove install.esd if it exists (we only need install.wim)
if (Test-Path "$ScratchDisk\tiny11\sources\install.esd") {
    Set-ItemProperty -Path "$ScratchDisk\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
    Remove-Item "$ScratchDisk\tiny11\sources\install.esd" -Force > $null 2>&1
    Write-Output "Removed install.esd (using install.wim instead)"
}

Write-Output "Copy complete!"
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    Clear-Host
}
Write-Output "Getting image information:"
$wimInfoAll = Get-WindowsImage -ImagePath "$ScratchDisk\tiny11\sources\install.wim"
$wimInfoAll | Format-Table -AutoSize | Out-String | Write-Host
$ImagesIndex = $wimInfoAll.ImageIndex

if ($NonInteractive) {
    # Auto-detect edition based on VersionSelector
    Write-Output "Auto-detecting edition based on VersionSelector: $VersionSelector"
    $wimInfo = $wimInfoAll
    
    if (-not $index -or $ImagesIndex -notcontains $index) {
        $targetEditions = @()
        
        foreach ($image in $wimInfo) {
            $imageName = $image.ImageName
            $match = $false
            $priority = 999
            
            switch ($VersionSelector) {
                'Auto' {
                    # Auto mode: prefer Pro editions
                    if ($imageName -like '*Pro*' -and $imageName -notlike '*Home*') {
                        $match = $true
                        if ($imageName -eq 'Windows 11 Pro') {
                            $priority = 1
                        } elseif ($imageName -like '*Pro for Workstations*' -and $imageName -notlike '*N*') {
                            $priority = 2
                        } elseif ($imageName -like '*Pro Education*' -and $imageName -notlike '*N*') {
                            $priority = 3
                        } elseif ($imageName -like '*Pro*' -and $imageName -notlike '*N*') {
                            $priority = 4
                        } else {
                            $priority = 5
                        }
                    }
                }
                'Pro' {
                    # Pro mode: find exact Windows 11 Pro
                    if ($imageName -eq 'Windows 11 Pro') {
                        $match = $true
                        $priority = 1
                    }
                }
                'Home' {
                    # Home mode: find Windows 11 Home (non-N)
                    if ($imageName -like '*Home*' -and $imageName -notlike '*N*' -and $imageName -notlike '*Pro*') {
                        $match = $true
                        if ($imageName -eq 'Windows 11 Home') {
                            $priority = 1
                        } else {
                            $priority = 2
                        }
                    }
                }
                'ProWorkstations' {
                    # ProWorkstations mode: find Pro for Workstations
                    if ($imageName -like '*Pro for Workstations*' -and $imageName -notlike '*N*') {
                        $match = $true
                        $priority = 1
                    }
                }
            }
            
            if ($match) {
                $targetEditions += @{
                    Index = $image.ImageIndex
                    Name = $imageName
                    Priority = $priority
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
    }
} else {
    # In interactive mode, validate index
    while ($ImagesIndex -notcontains $index) {
        $wimInfoAll | Format-Table -AutoSize | Out-String | Write-Host
        $index = Read-Host "Please enter the image index"
    }
}
Write-Output "Mounting Windows image. This may take a while."
$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # This block will catch the error and suppress it.
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim -Index $index -Path $ScratchDisk\scratchdir

$imageIntl = & dism /English /Get-Intl "/Image:$($ScratchDisk)\scratchdir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }

if ($languageLine) {
    $languageCode = $Matches[1]
    Write-Output "Default system UI language code: $languageCode"
} else {
    Write-Output "Default system UI language code not found."
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($ScratchDisk)\tiny11\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'

foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $architecture = $line -replace 'Architecture : ',''
        # If the architecture is x64, replace it with amd64
        if ($architecture -eq 'x64') {
            $architecture = 'amd64'
        }
        Write-Output "Architecture: $architecture"
        break
    }
}

if (-not $architecture) {
    Write-Output "Architecture information not found."
}

Write-Output "Mounting complete! Performing removal of applications..."

# Sử dụng debloater module nếu được enable
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Output "Using integrated debloater from Windows-ISO-Debloater..."
    
    # Get packages để filter Store và AI
    $allPackages = Get-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" -ErrorAction SilentlyContinue
    
    # Filter Store packages if RemoveStore = no
    if ($RemoveStore -eq 'no') {
        $storePackages = $allPackages | Where-Object { $_.PackageName -like '*WindowsStore*' -or $_.PackageName -like '*StorePurchaseApp*' -or $_.PackageName -like '*Store.Engagement*' }
        foreach ($storePkg in $storePackages) {
            Write-Output "  Keeping Store package: $($storePkg.PackageName)"
        }
    }
    
    # Filter AI packages if RemoveAI = no
    if ($RemoveAI -eq 'no') {
        $aiPackages = $allPackages | Where-Object { $_.PackageName -like '*Copilot*' -or $_.PackageName -like '*549981C3F5F10*' }
        foreach ($aiPkg in $aiPackages) {
            Write-Output "  Keeping AI package: $($aiPkg.PackageName)"
        }
    }
    
    Remove-DebloatPackages -MountPath "$ScratchDisk\scratchdir" `
        -RemoveAppx:($RemoveAppx -eq 'yes') `
        -RemoveCapabilities:($RemoveCapabilities -eq 'yes') `
        -RemoveWindowsPackages:($RemoveWindowsPackages -eq 'yes') `
        -LanguageCode $languageCode `
        -RemoveStore:($RemoveStore -eq 'yes') `
        -RemoveAI:($RemoveAI -eq 'yes') `
        -RemoveDefender:($RemoveDefender -eq 'yes')
    
    Remove-DebloatFiles -MountPath "$ScratchDisk\scratchdir" `
        -RemoveEdge:($RemoveEdge -eq 'yes') `
        -RemoveOneDrive:($RemoveOneDrive -eq 'yes') `
        -Architecture $architecture
    
    # Remove Store packages manually if RemoveStore = yes
    # Note: If RemoveAppx = yes, these may already be removed by Remove-DebloatPackages
    if ($RemoveStore -eq 'yes') {
        Write-Output "Removing Microsoft Store packages..."
        # Get fresh package list after Remove-DebloatPackages may have removed some
        $currentPackages = Get-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" -ErrorAction SilentlyContinue
        $storePackages = $currentPackages | Where-Object { $_.PackageName -like '*WindowsStore*' -or $_.PackageName -like '*StorePurchaseApp*' -or $_.PackageName -like '*Store.Engagement*' }
        
        if ($storePackages.Count -eq 0) {
            Write-Host "  No Store packages found (may have been removed already by debloater)" -ForegroundColor Gray
        } else {
            foreach ($storePkg in $storePackages) {
                Write-Output "  Removing: $($storePkg.PackageName)"
                try {
                    Remove-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" -PackageName $storePkg.PackageName -ErrorAction Stop | Out-Null
                    Write-Host "    ✓ Removed successfully" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠ Warning: Failed to remove $($storePkg.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # Remove AI packages manually if RemoveAI = yes
    # Note: If RemoveAppx = yes, these may already be removed by Remove-DebloatPackages
    if ($RemoveAI -eq 'yes') {
        Write-Output "Removing AI/Copilot packages..."
        # Get fresh package list after Remove-DebloatPackages may have removed some
        $currentPackages = Get-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" -ErrorAction SilentlyContinue
        $aiPackages = $currentPackages | Where-Object { $_.PackageName -like '*Copilot*' -or $_.PackageName -like '*549981C3F5F10*' }
        
        if ($aiPackages.Count -eq 0) {
            Write-Host "  No AI packages found (may have been removed already by debloater)" -ForegroundColor Gray
        } else {
            foreach ($aiPkg in $aiPackages) {
                Write-Output "  Removing: $($aiPkg.PackageName)"
                try {
                    Remove-ProvisionedAppxPackage -Path "$ScratchDisk\scratchdir" -PackageName $aiPkg.PackageName -ErrorAction Stop | Out-Null
                    Write-Host "    ✓ Removed successfully" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠ Warning: Failed to remove $($aiPkg.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
} else {
    # Fallback to original method
    Write-Output "Using original package removal method..."
}

$packages = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'PackageName : (.*)') {
            $matches[1]
        }
    }

$packagePrefixes = 'AppUp.IntelManagementandSecurityStatus',
'Clipchamp.Clipchamp', 
'DolbyLaboratories.DolbyAccess',
'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
'Microsoft.BingNews',
'Microsoft.BingSearch',
'Microsoft.BingWeather',
'Microsoft.BingSports',
'Microsoft.BingFinance',
'Microsoft.Copilot',
'Microsoft.Windows.CrossDevice',
'Microsoft.GamingApp',
'Microsoft.GetHelp',
'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer',
'Microsoft.MicrosoftOfficeHub',
'Microsoft.MicrosoftSolitaireCollection',
'Microsoft.MicrosoftStickyNotes',
'Microsoft.MixedReality.Portal',
'Microsoft.MSPaint',
'Microsoft.Office.OneNote',
'Microsoft.OfficePushNotificationUtility',
'Microsoft.OutlookForWindows',
'Microsoft.Paint',
'Microsoft.People',
'Microsoft.PowerAutomateDesktop',
'Microsoft.SkypeApp',
'Microsoft.StartExperiencesApp',
'Microsoft.Todos',
'Microsoft.Wallet',
'Microsoft.Windows.DevHome',
'Microsoft.Windows.Copilot',
'Microsoft.Windows.Teams',
'Microsoft.WindowsAlarms',
'Microsoft.WindowsCamera',
'Microsoft.WindowsCalculator',
'Microsoft.WindowsNotepad',
'Microsoft.WindowsPaint',
'Microsoft.WindowsTerminal',
'Microsoft.WindowsTips',
'Microsoft.OneDrive',
'Microsoft.OneDriveSync',
'microsoft.windowscommunicationsapps',
'Microsoft.WindowsFeedbackHub',
'Microsoft.WindowsMaps',
'Microsoft.WindowsSoundRecorder',
'Microsoft.ScreenSketch',
'Microsoft.Windows.Search.Cortana',
'Microsoft.Windows.ContentDeliveryManager',
'Microsoft.Xbox.TCUI',
'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay',
'Microsoft.XboxGamingOverlay',
'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay',
'Microsoft.YourPhone',
'Microsoft.ZuneMusic',
'Microsoft.ZuneVideo',
'MicrosoftCorporationII.MicrosoftFamily',
'MicrosoftCorporationII.QuickAssist',
'MSTeams',
'MicrosoftTeams', 
'Microsoft.549981C3F5F10'

$packagesToRemove = $packages | Where-Object {
    $packageName = $_
    $shouldRemove = $false
    foreach ($prefix in $packagePrefixes) {
        if ($packageName -like "*$prefix*") {
            $shouldRemove = $true
            break
        }
    }
    $shouldRemove
}
# Chỉ chạy method cũ nếu debloater không được enable
if ($EnableDebloat -ne 'yes' -or -not (Get-Module -Name tiny11-debloater)) {
    # Filter packages based on options
    $filteredPackages = $packagesToRemove | Where-Object {
        $packageName = $_
        $shouldRemove = $true
        
        # Filter AI packages if RemoveAI = no
        if ($RemoveAI -eq 'no') {
            if ($packageName -like '*Copilot*' -or $packageName -like '*549981C3F5F10*') {
                $shouldRemove = $false
                Write-Output "  Keeping AI package: $packageName"
            }
        }
        
        # Filter Store packages if RemoveStore = no
        if ($RemoveStore -eq 'no') {
            if ($packageName -like '*WindowsStore*' -or $packageName -like '*StorePurchaseApp*' -or $packageName -like '*Store.Engagement*') {
                $shouldRemove = $false
                Write-Output "  Keeping Store package: $packageName"
            }
        }
        
        return $shouldRemove
    }
    
    foreach ($package in $filteredPackages) {
        Write-Output "Removing $package"
        $result = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package" 2>&1
        if ($LASTEXITCODE -ne 0 -or ($result | Select-String -Pattern "Error|failed|not found" -Quiet)) {
            Write-Host "  Warning: Failed to remove $package (continuing...)" -ForegroundColor Yellow
        }
    }

    # Remove Edge only if RemoveEdge = yes
    if ($RemoveEdge -eq 'yes') {
        Write-Output "Removing Edge:"
        Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
        Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
        Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null
        & 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' | Out-Null
        & 'icacls' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
        Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force | Out-Null
    } else {
        Write-Output "Keeping Edge (RemoveEdge = no)"
    }
    
    Write-Output "Removing OneDrive:"
    & 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" | Out-Null
    & 'icacls' "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
    Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe" -Force | Out-Null
    
    Write-Output "Removing OneDrive Start Menu shortcuts:"
    $startMenuPaths = @(
        "$ScratchDisk\scratchdir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$ScratchDisk\scratchdir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive",
        "$ScratchDisk\scratchdir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
        "$ScratchDisk\scratchdir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive"
    )
    
    foreach ($shortcutPath in $startMenuPaths) {
        if (Test-Path $shortcutPath) {
            & 'takeown' '/f' $shortcutPath '/r' | Out-Null
            & 'icacls' $shortcutPath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
            Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    
    # Remove Start Menu shortcuts for debloated apps
    Write-Output "Removing Start Menu shortcuts for debloated apps..."
    $startMenuBasePaths = @(
        "$ScratchDisk\scratchdir\ProgramData\Microsoft\Windows\Start Menu\Programs",
        "$ScratchDisk\scratchdir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
    )
    
    # Apps to remove shortcuts for based on debloat parameters
    $shortcutsToRemove = @()
    
    # Microsoft Edge shortcuts (if RemoveEdge=yes)
    if ($RemoveEdge -eq 'yes') {
        $shortcutsToRemove += "Microsoft Edge.lnk"
        $shortcutsToRemove += "Microsoft Edge"
        $shortcutsToRemove += "Microsoft Edge Update.lnk"
        $shortcutsToRemove += "Microsoft Edge Update"
        Write-Output "  Removing Edge shortcuts..."
    }
    
    # Microsoft Store shortcuts (if RemoveStore=yes)
    if ($RemoveStore -eq 'yes') {
        $shortcutsToRemove += "Microsoft Store.lnk"
        $shortcutsToRemove += "Microsoft Store"
        Write-Output "  Removing Store shortcuts..."
    }
    
    # Remove shortcuts from both Start Menu locations
    foreach ($basePath in $startMenuBasePaths) {
        if (Test-Path $basePath) {
            foreach ($shortcutName in $shortcutsToRemove) {
                $shortcutPath = Join-Path $basePath $shortcutName
                if (Test-Path $shortcutPath) {
                    try {
                        & 'takeown' '/f' $shortcutPath '/r' | Out-Null
                        & 'icacls' $shortcutPath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
                        Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    } catch {
                        # Silently continue if shortcut removal fails
                    }
                }
            }
            
            # Also remove any shortcuts containing "Microsoft Edge" or "Microsoft Store" in their names
            if ($RemoveEdge -eq 'yes') {
                Get-ChildItem -Path $basePath -Filter "*Edge*" -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        & 'takeown' '/f' $_.FullName '/r' | Out-Null
                        & 'icacls' $_.FullName '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    } catch { }
                }
            }
            
            if ($RemoveStore -eq 'yes') {
                Get-ChildItem -Path $basePath -Filter "*Store*" -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        & 'takeown' '/f' $_.FullName '/r' | Out-Null
                        & 'icacls' $_.FullName '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
                        Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
                    } catch { }
                }
            }
        }
    }
    Write-Output "Start Menu shortcuts cleanup complete."
}

Write-Output "Removal complete!"
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Output "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM | Out-Null
Write-Output "Bypassing system requirements(on the system image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "Disabling Sponsored Apps:"
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338387Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'

Write-Output "Disabling Windows Spotlight and Lock Screen tips:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'RotatingLockScreenOverlayEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'

# Apply debloater registry tweaks nếu được enable
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Output "Applying debloater registry tweaks..."
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

Write-Output "Enabling Local Accounts on OOBE (Windows 11 25H2+ compatible):"
# BypassNRO no longer works from Windows 11 25H2+, use ms-cxh:localonly URI scheme instead
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' 'OOBELocalAccount' 'REG_SZ' 'start ms-cxh:localonly'
# Keep BypassNRO for older Windows versions compatibility
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
# Ensure Sysprep directory exists before copying autounattend.xml
$sysprepDir = "$ScratchDisk\scratchdir\Windows\System32\Sysprep"
if (-not (Test-Path $sysprepDir)) {
    New-Item -ItemType Directory -Path $sysprepDir -Force | Out-Null
}
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$sysprepDir\autounattend.xml" -Force | Out-Null

Write-Output "Disabling Reserved Storage:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'

# Remove Defender if requested
if ($RemoveDefender -eq 'yes') {
    Write-Output "Removing Windows Defender..."
    try {
        $defenderPackages = & dism /English /image:"$ScratchDisk\scratchdir" /Get-Packages | 
            Select-String -Pattern "Windows-Defender-Client-Package"
        
        foreach ($package in $defenderPackages) {
            if ($package -match 'Package Identity :\s+(.+)') {
                $packageIdentity = $Matches[1].Trim()
                Write-Output "  Removing Defender package: $packageIdentity"
                $result = & dism /English /image:"$ScratchDisk\scratchdir" /Remove-Package /PackageName:$packageIdentity 2>&1
                if ($LASTEXITCODE -ne 0 -or ($result | Select-String -Pattern "Removal failed|Error|failed" -Quiet)) {
                    Write-Host "  Warning: Failed to remove Defender package $packageIdentity (continuing...)" -ForegroundColor Yellow
                }
            }
        }
        
        # Disable Defender services
        $servicePaths = @("WinDefend", "WdNisSvc", "WdNisDrv", "WdFilter", "Sense")
        foreach ($service in $servicePaths) {
            Set-RegistryValue "HKLM\zSYSTEM\ControlSet001\Services\$service" "Start" "REG_DWORD" "4"
        }
        
        # Hide Defender from Settings
        Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' 'SettingsPageVisibility' 'REG_SZ' 'hide:virus;windowsupdate'
        Write-Output "Windows Defender removed successfully"
    } catch {
        Write-Warning "Failed to remove Defender: $_"
    }
} else {
    Write-Output "Keeping Windows Defender (RemoveDefender=no)"
    Write-Output "Note: Defender needs Windows Update services to update virus definitions"
}

Write-Output "Disabling BitLocker Device Encryption"
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
Write-Output "Disabling Chat icon:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
Write-Output "Disabling Search Highlights:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' 'IsDynamicSearchBoxEnabled' 'REG_DWORD' '0'

Write-Output "Disabling Bing Search in Start Bar:"
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' 'BingSearchEnabled' 'REG_DWORD' '0'

Write-Output "Disabling Auto Discovery:"
# Ensure the registry path exists
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' '/v' 'FolderType' '/t' 'REG_SZ' '/d' 'NotSpecified' '/f' | Out-Null
Write-Output "Removing Edge related registries"
if ($RemoveEdge -eq 'yes') {
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
    Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
}

# Disable Copilot/AI if RemoveAI = no (keep it enabled)
if ($RemoveAI -eq 'yes') {
    Write-Output "Disabling Copilot/AI..."
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
}

# Disable Store if RemoveStore = yes
if ($RemoveStore -eq 'yes') {
    Write-Output "Disabling Microsoft Store..."
    Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\WindowsStore' 'RemoveWindowsStore' 'REG_DWORD' '1'
    Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned' 'Microsoft.WindowsStore_8wekyb3d8bbwe' 'REG_SZ' ''
}
Write-Output "Disabling OneDrive folder backup"
Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
Write-Output "Disabling Telemetry:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
## Prevents installation of DevHome and Outlook
Write-Output "Prevents installation of DevHome and Outlook:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
Write-Output "Disabling Copilot"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
Write-Output "Prevents installation of Teams:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
Write-Output "Prevent installation of New Outlook":
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

Write-Host "Deleting scheduled task definition files..."
$tasksPath = "$ScratchDisk\scratchdir\Windows\System32\Tasks"

# Use parallel processing for file removal if available
$parallelHelperPath = Join-Path $PSScriptRoot "parallel-helper.psm1"
if (Test-Path $parallelHelperPath) {
    Import-Module $parallelHelperPath -Force -ErrorAction SilentlyContinue
    if (Get-Module -Name parallel-helper) {
        Write-Host "Using parallel processing for file removal..." -ForegroundColor Cyan
        $taskPaths = @(
            "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser",
            "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program",
            "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater",
            "$tasksPath\Microsoft\Windows\Chkdsk\Proxy",
            "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting"
        )
        Remove-ItemsParallel -Paths $taskPaths -Recurse -ErrorAction SilentlyContinue | Out-Null
    } else {
        # Fallback to sequential removal
        Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
    }
} else {
    # Fallback to sequential removal
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
}
Write-Host "Task files have been deleted."
Write-Host "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null
Write-Output "Cleaning up image..."

# Inject IRST driver into install.wim if provided or if IRST_Driver folder exists
if ($IrstDriverPath -or (Test-Path (Join-Path $PSScriptRoot "IRST_Driver"))) {
    Add-DriverToImage -MountPath "$ScratchDisk\scratchdir" -DriverPath $IrstDriverPath -ImageName "install.wim"
}

Write-Output "Cleaning up image..."
dism.exe /Image:$ScratchDisk\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Output "Cleanup complete."
Write-Output ' '
Write-Output "Unmounting image..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
Write-Host "Exporting image..."
Dism.exe /Export-Image /SourceImageFile:"$ScratchDisk\tiny11\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$ScratchDisk\tiny11\sources\install2.wim" /Compress:recovery
Remove-Item -Path "$ScratchDisk\tiny11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny11\sources\install2.wim" -NewName "install.wim" | Out-Null
Write-Output "Windows image completed. Continuing with boot.wim."
if (-not $NonInteractive) {
    Start-Sleep -Seconds 2
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Output "Mounting boot image (keeping both WinPE classic menu and Windows Setup)..."
$wimFilePath = "$ScratchDisk\tiny11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
Write-Output "Mounting Windows Setup image (index 2) to modify registry (index 1 - WinPE classic menu will be preserved)..."
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\boot.wim -Index 2 -Path $ScratchDisk\scratchdir
Write-Output "Loading registry..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM

Write-Output "Bypassing system requirements(on the setup image):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "Tweaking complete!"

Write-Output "Unmounting Registry..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

# Inject IRST driver into boot.wim (Windows Setup) if provided or if IRST_Driver folder exists
if ($IrstDriverPath -or (Test-Path (Join-Path $PSScriptRoot "IRST_Driver"))) {
    Add-DriverToImage -MountPath "$ScratchDisk\scratchdir" -DriverPath $IrstDriverPath -ImageName "boot.wim (Windows Setup)"
}

Write-Output "Unmounting image (keeping both indexes intact)..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
if (-not $NonInteractive) {
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Output "The tiny11 image is now completed. Proceeding with the making of the ISO..."
Write-Output "Copying unattended file for bypassing MS account on OOBE..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\tiny11\autounattend.xml" -Force | Out-Null
Write-Output "Creating ISO image..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostarchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Output "Will be using oscdimg.exe from system ADK."
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Output "ADK folder not found. Will be using bundled oscdimg.exe."
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Output "Downloading oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

        if (Test-Path $localOSCDIMGPath) {
            Write-Output "oscdimg.exe downloaded successfully."
        } else {
            Write-Error "Failed to download oscdimg.exe."
            exit 1
        }
    } else {
        Write-Output "oscdimg.exe already exists locally."
    }

    $OSCDIMG = $localOSCDIMGPath
}

# Determine ISO filename
$isoFileName = if ($IsoName -and $IsoName.Trim() -ne '') {
    # Use custom name if provided, ensure it has .iso extension
    $name = $IsoName.Trim()
    if (-not $name.EndsWith('.iso', [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = "$name.iso"
    }
    $name
} else {
    # Default name based on build type (check environment variable if available)
    $buildType = $env:BUILD_TYPE
    if ($buildType -eq 'maker') {
        'maker.iso'
    } else {
        'tiny11.iso'
    }
}

Write-Output "Running oscdimg to create ISO..."
$isoPath = "$PSScriptRoot\$isoFileName"
Write-Host "ISO will be saved as: $isoFileName" -ForegroundColor Cyan
try {
    & "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny11\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" $isoPath 2>&1 | Out-Null
    
    # Verify ISO was created
    Start-Sleep -Seconds 2
    if (-not (Test-Path $isoPath)) {
        Write-Error "ISO was not created at expected path: $isoPath"
        exit 1
    }
    
    $isoSize = (Get-Item $isoPath).Length / 1GB
    Write-Host "✓ ISO created successfully: $isoPath" -ForegroundColor Green
    Write-Output "  ISO size: $([math]::Round($isoSize, 2)) GB"
} catch {
    Write-Error "Failed to create ISO: $($_.Exception.Message)"
    exit 1
}

# Finishing up
Write-Output "Creation completed! Press any key to exit the script..."
if ($NonInteractive) {
    Write-Output "Build complete! Cleaning up..."
} else {
    Read-Host "Press Enter to continue"
}
Write-Output "Performing Cleanup..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null
if (-not $NonInteractive) {
    Write-Output "Ejecting Iso drive"
    Get-Volume -DriveLetter $DriveLetter[0] | Get-DiskImage | Dismount-DiskImage
    Write-Output "Iso drive ejected"
}
Write-Output "Removing oscdimg.exe..."
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Write-Output "Removing autounattend.xml..."
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

Write-Output "Cleanup check :"
if (Test-Path -Path "$ScratchDisk\tiny11") {
    Write-Output "tiny11 folder still exists. Attempting to remove it again..."
    Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\tiny11") {
        Write-Output "Failed to remove tiny11 folder."
    } else {
        Write-Output "tiny11 folder removed successfully."
    }
} else {
    Write-Output "tiny11 folder does not exist. No action needed."
}
if (Test-Path -Path "$ScratchDisk\scratchdir") {
    Write-Output "scratchdir folder still exists. Attempting to remove it again..."
    Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\scratchdir") {
        Write-Output "Failed to remove scratchdir folder."
    } else {
        Write-Output "scratchdir folder removed successfully."
    }
} else {
    Write-Output "scratchdir folder does not exist. No action needed."
}
if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
    Write-Output "oscdimg.exe still exists. Attempting to remove it again..."
    Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
        Write-Output "Failed to remove oscdimg.exe."
    } else {
        Write-Output "oscdimg.exe removed successfully."
    }
} else {
    Write-Output "oscdimg.exe does not exist. No action needed."
}
if (Test-Path -Path "$PSScriptRoot\autounattend.xml") {
    Write-Output "autounattend.xml still exists. Attempting to remove it again..."
    Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$PSScriptRoot\autounattend.xml") {
        Write-Output "Failed to remove autounattend.xml."
    } else {
        Write-Output "autounattend.xml removed successfully."
    }
} else {
    Write-Output "autounattend.xml does not exist. No action needed."
}

# Stop the transcript
Stop-Transcript

exit

