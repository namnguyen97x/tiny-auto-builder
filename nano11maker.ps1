#---------[ Parameters ]---------#
param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    
    # Non-interactive mode for CI/CD
    [switch]$NonInteractive = $false,
    
    # Version selector (Auto, Pro, Home, ProWorkstations)
    [ValidateSet('Auto','Pro','Home','ProWorkstations')][string]$VersionSelector = 'Auto',
    
    # Optional debloat options (honored from workflow)
    [ValidateSet('yes','no')][string]$RemoveDefender = 'yes',
    [ValidateSet('yes','no')][string]$RemoveAI = 'yes',
    [ValidateSet('yes','no')][string]$RemoveEdge = 'yes',
    [ValidateSet('yes','no')][string]$RemoveStore = 'yes',
    
    # Driver removal options (honored from workflow)
    [ValidateSet('yes','no')][string]$RemovePrinterDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveScannerDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveBluetoothDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveSmartcardDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveTapeDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveRdpDrivers = 'yes'
)

# Set error handling to continue on non-critical errors
# Script will only exit on critical failures (ISO creation, mounting, etc.)
$ErrorActionPreference = 'Continue'

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
    Write-Host "Restarting nano11 image creator as admin in a new window, you can close this one."
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

Start-Transcript -Path "$PSScriptRoot\nano11.log" 

if (-not $NonInteractive) {
    try {
        $Host.UI.RawUI.WindowTitle = "Nano11 image creator"
        Clear-Host
    } catch {
        # Ignore errors in non-interactive environments
    }
}

Write-Output "Welcome to nano11 builder!"
Write-Output "This script generates a significantly reduced Windows 11 image. However, it's not suitable for regular use due to its lack of serviceability - you can't add languages, updates, or features post-creation. nano11 is not a full Windows 11 substitute but a rapid testing or development tool, potentially useful for VM environments."

# RemoveDefender, RemoveAI, RemoveEdge, RemoveStore được set từ parameters (honored from workflow)
Write-Output "Debloat (nano): Defender=$RemoveDefender, AI=$RemoveAI, Edge=$RemoveEdge, Store=$RemoveStore"

if (-not $NonInteractive) {
    Write-Output "Do you want to continue? (y/n)"
    $input = Read-Host
    if ($input -ne 'y') {
        Write-Output "You chose not to continue. The script will now exit."
        exit
    }
    Write-Output "Off we go..."
    Start-Sleep -Seconds 3
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}

$mainOSDrive = $env:SystemDrive
New-Item -ItemType Directory -Force -Path "$mainOSDrive\nano11\sources" | Out-Null

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
        $esdInfo | Format-Table -AutoSize
        
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
        
        Write-Output 'Converting install.esd to install.wim. This may take a while...'
        Export-WindowsImage -SourceImagePath "$DriveLetter\sources\install.esd" -SourceIndex $index -DestinationImagePath "$mainOSDrive\nano11\sources\install.wim" -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "Can't find Windows OS Installation files in the specified Drive Letter.. Exiting."
        exit
    }
}

Write-Output "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$mainOSDrive\nano11" -Recurse -Force | Out-Null
if (Test-Path "$mainOSDrive\nano11\sources\install.esd") {
    Set-ItemProperty -Path "$mainOSDrive\nano11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
    Remove-Item "$mainOSDrive\nano11\sources\install.esd" -ErrorAction SilentlyContinue
}

Write-Output "Getting image information:"
$wimInfoAll = Get-WindowsImage -ImagePath "$mainOSDrive\nano11\sources\install.wim"
$wimInfoAll | Format-Table -AutoSize
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
            Write-Output "Found edition: $($bestEdition.Name) (Index: $index)" -ForegroundColor Green
        } else {
            # Fallback to index 1 if not found
            $index = 1
            Write-Output "Requested edition not found, using default index: $index" -ForegroundColor Yellow
        }
    }
} else {
    # In interactive mode, validate index
    while ($ImagesIndex -notcontains $index) {
        $wimInfoAll | Format-Table -AutoSize
        $index = Read-Host "Please enter the image index"
    }
}

Write-Output "Mounting Windows image. This may take a while."
$wimFilePath = "$mainOSDrive\nano11\sources\install.wim" 
& takeown "/F" $wimFilePath 
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # This block will catch the error and suppress it.
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
New-Item -ItemType Directory -Force -Path "$mainOSDrive\scratchdir" | Out-Null
Mount-WindowsImage -ImagePath "$mainOSDrive\nano11\sources\install.wim" -Index $index -Path "$mainOSDrive\scratchdir"

# --- Proactively take ownership of all target folders for install.wim ---
$scratchDir = "$mainOSDrive\scratchdir"
$foldersToOwn = @(
    "$scratchDir\Windows\System32\DriverStore\FileRepository",
    "$scratchDir\Windows\Fonts",
    "$scratchDir\Windows\Web",
    "$scratchDir\Windows\Help",
    "$scratchDir\Windows\Cursors",
    "$scratchDir\Program Files (x86)\Microsoft",
    "$scratchDir\Program Files\WindowsApps",
    "$scratchDir\Windows\System32\Microsoft-Edge-Webview",
    "$scratchDir\Windows\System32\Recovery",
    "$scratchDir\Windows\WinSxS",
    "$scratchDir\Windows\assembly",
    "$scratchDir\Windows\System32\InputMethod",
    "$scratchDir\Windows\Speech",
    "$scratchDir\Windows\Temp"
)
# Only remove Defender folder if RemoveDefender=yes
if ($RemoveDefender -eq 'yes') {
    $foldersToOwn += "$scratchDir\ProgramData\Microsoft\Windows Defender"
}
$filesToOwn = @( "$scratchDir\Windows\System32\OneDriveSetup.exe" )

foreach ($folder in $foldersToOwn) {
    if (Test-Path $folder) {
        Write-Host "Taking ownership of folder: $folder"
        & takeown.exe /F $folder /R /D Y
        & icacls.exe $folder /grant "$($adminGroup.Value):(F)" /T /C
    }
}

foreach ($file in $filesToOwn) {
    if (Test-Path $file) {
        Write-Host "Taking ownership of file: $file"
        & takeown.exe /F $file /D Y
        & icacls.exe $file /grant "$($adminGroup.Value):(F)" /C
    }
}

$imageIntl = & dism /English /Get-Intl "/Image:$scratchDir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
if ($languageLine) { $languageCode = $Matches[1]; Write-Host "Default system UI language code: $languageCode" } else { Write-Host "Default system UI language code not found." }
$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$wimFilePath" "/index:$index"
$lines = $imageInfo -split '\r?\n'
foreach ($line in $lines) { if ($line -like '*Architecture : *') { $architecture = $line -replace 'Architecture : ',''; if ($architecture -eq 'x64') { $architecture = 'amd64' }; Write-Host "Architecture: $architecture"; break } }
if (-not $architecture) { Write-Host "Architecture information not found." }
Write-Host "Removing provisioned AppX packages (bloatware)..."
$packagesToRemove = Get-AppxProvisionedPackage -Path $scratchDir | Where-Object { $_.PackageName -like '*Zune*' -or $_.PackageName -like '*Bing*' -or $_.PackageName -like '*Clipchamp*' -or $_.PackageName -like '*Gaming*' -or $_.PackageName -like '*People*' -or $_.PackageName -like '*PowerAutomate*' -or $_.PackageName -like '*Teams*' -or $_.PackageName -like '*Todos*' -or $_.PackageName -like '*YourPhone*' -or $_.PackageName -like '*SoundRecorder*' -or $_.PackageName -like '*Solitaire*' -or $_.PackageName -like '*FeedbackHub*' -or $_.PackageName -like '*Maps*' -or $_.PackageName -like '*OfficeHub*' -or $_.PackageName -like '*Help*' -or $_.PackageName -like '*Family*' -or $_.PackageName -like '*Alarms*' -or $_.PackageName -like '*CommunicationsApps*' -or $_.PackageName -like '*Copilot*' -or $_.PackageName -like '*CompatibilityEnhancements*' -or $_.PackageName -like '*AV1VideoExtension*' -or $_.PackageName -like '*AVCEncoderVideoExtension*' -or $_.PackageName -like '*HEIFImageExtension*' -or $_.PackageName -like '*HEVCVideoExtension*' -or $_.PackageName -like '*MicrosoftStickyNotes*' -or $_.PackageName -like '*OutlookForWindows*' -or $_.PackageName -like '*RawImageExtension*' -or $_.PackageName -like '*SecHealthUI*' -or $_.PackageName -like '*VP9VideoExtensions*' -or $_.PackageName -like '*WebpImageExtension*' -or $_.PackageName -like '*DevHome*' -or $_.PackageName -like '*Photos*' -or $_.PackageName -like '*Camera*' -or $_.PackageName -like '*QuickAssist*' -or $_.PackageName -like '*CoreAI*'  -or $_.PackageName -like '*PeopleExperienceHost*' -or $_.PackageName -like '*PinningConfirmationDialog*' -or $_.PackageName -like '*SecureAssessmentBrowser*' -or $_.PackageName -like '*Paint*' -or $_.PackageName -like '*Notepad*' -or $_.PackageName -like '*Microsoft3DViewer*' -or $_.PackageName -like '*ScreenSketch*' -or $_.PackageName -like '*Cortana*' -or $_.PackageName -like '*SkypeApp*' -or $_.PackageName -like '*OneDrive*' -or $_.PackageName -like '*OneNote*' -or $_.PackageName -like '*Xbox*' -or $_.PackageName -like '*WindowsTips*' -or $_.PackageName -like '*Calculator*' -or $_.PackageName -like '*Terminal*' -or $_.PackageName -like '*ContentDeliveryManager*' -or $_.PackageName -like '*BingSports*' -or $_.PackageName -like '*BingFinance*'  }
foreach ($package in $packagesToRemove) { 
    try {
        Write-Host "Removing: $($package.DisplayName)"
        Remove-AppxProvisionedPackage -Path $scratchDir -PackageName $package.PackageName -ErrorAction Stop
        Write-Host "  ✓ Removed successfully" -ForegroundColor Green
    } catch {
        Write-Host "  Warning: Failed to remove $($package.DisplayName) - $($_.Exception.Message) (continuing...)" -ForegroundColor Yellow
    }
}

Write-Host "Attempting to remove leftover WindowsApps folders..."
foreach ($package in $packagesToRemove) { $folderPath = Join-Path "$scratchDir\Program Files\WindowsApps" $package.PackageName; if (Test-Path $folderPath) { Write-Host "Deleting folder: $($package.PackageName)"; Remove-Item $folderPath -Recurse -Force -ErrorAction SilentlyContinue } }

Write-Output "Removing of system apps complete! Now proceeding to removal of system packages..."
if (-not $NonInteractive) {
    Start-Sleep -Seconds 1
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
$packagePatterns = @(
    # --- Legacy Components & Optional Apps ---
    "Microsoft-Windows-InternetExplorer-Optional-Package~",
    "Microsoft-Windows-MediaPlayer-Package~",
    "Microsoft-Windows-WordPad-FoD-Package~",
    "Microsoft-Windows-StepsRecorder-Package~",
    "Microsoft-Windows-MSPaint-FoD-Package~",
    "Microsoft-Windows-SnippingTool-FoD-Package~",
    "Microsoft-Windows-TabletPCMath-Package~",
    "Microsoft-Windows-Xps-Xps-Viewer-Opt-Package~",
    "Microsoft-Windows-PowerShell-ISE-FOD-Package~",
    "OpenSSH-Client-Package~",

    # --- Language & Input Features (Assumes primary language only) ---
    "Microsoft-Windows-LanguageFeatures-Handwriting-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-OCR-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-Speech-$languageCode-Package~",
    "Microsoft-Windows-LanguageFeatures-TextToSpeech-$languageCode-Package~",
    "*IME-ja-jp*",
    "*IME-ko-kr*",
    "*IME-zh-cn*",
    "*IME-zh-tw*",

    # --- Core OS Features (Removal is aggressive and will break functionality) ---
    "Microsoft-Windows-Search-Engine-Client-Package~",
    "Microsoft-Windows-Kernel-LA57-FoD-Package~",

    # --- Security & Identity (Breaks these features) ---
    "Microsoft-Windows-Hello-Face-Package~",
    "Microsoft-Windows-Hello-BioEnrollment-Package~",
    "Microsoft-Windows-BitLocker-DriveEncryption-FVE-Package~",
    "Microsoft-Windows-TPM-WMI-Provider-Package~",

    # --- Accessibility Tools ---
    "Microsoft-Windows-Narrator-App-Package~",
    "Microsoft-Windows-Magnifier-App-Package~",

    # --- Miscellaneous Features ---
    "Microsoft-Windows-Printing-PMCPPC-FoD-Package~",
    "Microsoft-Windows-WebcamExperience-Package~",
    "Microsoft-Media-MPEG2-Decoder-Package~",
    "Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~"
)

# Honor RemoveDefender parameter from workflow
if ($RemoveDefender -eq 'yes') {
    $packagePatterns += "Windows-Defender-Client-Package~"
} else {
    Write-Output "Keeping Windows Defender (RemoveDefender=no)"
}

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

# Enable .NET Framework 3.5 automatically for nano build
Write-Host "Enabling .NET Framework 3.5..."
try {
    & 'dism' "/image:$mainOSDrive\scratchdir" '/enable-feature' '/featurename:NetFX3' '/All' "/source:$($env:SystemDrive)\nano11\sources\sxs" 
    if ($LASTEXITCODE -eq 0) {
        Write-Host ".NET 3.5 has been enabled successfully." -ForegroundColor Green
    } else {
        Write-Warning "Failed to enable .NET 3.5 (exit code: $LASTEXITCODE). Continuing..."
    }
} catch {
    Write-Warning "Error enabling .NET 3.5: $($_.Exception.Message). Continuing..."
}

Write-Host "Removing pre-compiled .NET assemblies (Native Images)..."
Remove-Item -Path "$scratchDir\Windows\assembly\NativeImages_*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Performing aggressive manual file deletions..."
$winDir = "$scratchDir\Windows"
Write-Host "Slimming the DriverStore... (removing non-essential driver classes)"
$driverRepo = Join-Path -Path $winDir -ChildPath "System32\DriverStore\FileRepository"
$patternsToRemove = @()

# Add driver patterns based on parameters
# Only add patterns for drivers that should be removed (parameter = 'yes')
# If parameter = 'no', the driver will be kept (not added to removal list)
if ($RemovePrinterDrivers -eq 'yes') {
    $patternsToRemove += 'prn*'  # Printer drivers (e.g., prnms001.inf, prnge001.inf)
}
if ($RemoveScannerDrivers -eq 'yes') {
    $patternsToRemove += 'scan*'  # Scanner drivers
    $patternsToRemove += 'mfd*'  # Multi-function device drivers
}
if ($RemoveSmartcardDrivers -eq 'yes') {
    $patternsToRemove += 'wscsmd.inf*'  # Smartcard readers
}
if ($RemoveTapeDrivers -eq 'yes') {
    $patternsToRemove += 'tapdrv*'  # Tape drives
}
if ($RemoveRdpDrivers -eq 'yes') {
    $patternsToRemove += 'rdpbus.inf*'  # Remote Desktop virtual bus
}
if ($RemoveBluetoothDrivers -eq 'yes') {
    $patternsToRemove += 'tdibth.inf*'  # Bluetooth Personal Area Network
}

Write-Host "Driver removal settings: Printer=$RemovePrinterDrivers, Scanner=$RemoveScannerDrivers, Bluetooth=$RemoveBluetoothDrivers, Smartcard=$RemoveSmartcardDrivers, Tape=$RemoveTapeDrivers, RDP=$RemoveRdpDrivers"

# Get all driver packages and remove the ones matching the patterns
Get-ChildItem -Path $driverRepo -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $driverFolder = $_.Name
    foreach ($pattern in $patternsToRemove) {
        if ($driverFolder -like $pattern) {
            Write-Host "Removing non-essential driver package: $driverFolder"
            try {
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                Write-Host "  Warning: Failed to remove $driverFolder (continuing...)" -ForegroundColor Yellow
            }
            break # Move to the next folder once a match is found
        }
    }
}
$fontsPath = Join-Path -Path $winDir -ChildPath "Fonts"
if (Test-Path $fontsPath) { 
    try {
        Get-ChildItem -Path $fontsPath -Exclude "segoe*.*", "tahoma*.*", "marlett.ttf", "8541oem.fon", "segui*.*", "consol*.*", "lucon*.*", "calibri*.*", "arial*.*", "times*.*", "cou*.*", "8*.*" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem -Path $fontsPath -Include "mingli*", "msjh*", "msyh*", "malgun*", "meiryo*", "yugoth*", "segoeuihistoric.ttf" -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  Warning: Some fonts could not be removed (continuing...)" -ForegroundColor Yellow
    }
}
# Use parallel processing for file removal if available
$parallelHelperPath = Join-Path $PSScriptRoot "parallel-helper.psm1"
if (Test-Path $parallelHelperPath) {
    Import-Module $parallelHelperPath -Force -ErrorAction SilentlyContinue
    if (Get-Module -Name parallel-helper) {
        Write-Host "Using parallel processing for file removal..." -ForegroundColor Cyan
        $filesToRemove = @(
            (Join-Path -Path $winDir -ChildPath "Speech\Engines\TTS")
        )
        
        # Only remove Defender Definition Updates if RemoveDefender=yes
        if ($RemoveDefender -eq 'yes') {
            $filesToRemove += "$scratchDir\ProgramData\Microsoft\Windows Defender\Definition Updates"
        }
        
        # Input method paths
        $inputMethodPaths = @("CHS", "CHT", "JPN", "KOR")
        foreach ($imPath in $inputMethodPaths) {
            $filesToRemove += "$scratchDir\Windows\System32\InputMethod\$imPath"
        }
        
        # Folders to remove
        $foldersToRemove = @("Web", "Help", "Cursors")
        foreach ($folder in $foldersToRemove) {
            $filesToRemove += (Join-Path -Path $winDir -ChildPath $folder)
        }
        
        # Remove Windows Temp contents (handle separately)
        Remove-Item -Path "$scratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Remove all other items in parallel
        Remove-ItemsParallel -Paths $filesToRemove -Recurse -ErrorAction SilentlyContinue | Out-Null
    } else {
        # Fallback to sequential removal
        Remove-Item -Path (Join-Path -Path $winDir -ChildPath "Speech\Engines\TTS") -Recurse -Force -ErrorAction SilentlyContinue
        if ($RemoveDefender -eq 'yes') {
            Remove-Item -Path "$scratchDir\ProgramData\Microsoft\Windows Defender\Definition Updates" -Recurse -Force -ErrorAction SilentlyContinue
        }
        $inputMethodPaths = @("CHS", "CHT", "JPN", "KOR")
        foreach ($imPath in $inputMethodPaths) {
            Remove-Item -Path "$scratchDir\Windows\System32\InputMethod\$imPath" -Recurse -Force -ErrorAction SilentlyContinue
        }
        Remove-Item -Path "$scratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        $foldersToRemove = @("Web", "Help", "Cursors")
        foreach ($folder in $foldersToRemove) {
            Remove-Item -Path (Join-Path -Path $winDir -ChildPath $folder) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    # Fallback to sequential removal
    Remove-Item -Path (Join-Path -Path $winDir -ChildPath "Speech\Engines\TTS") -Recurse -Force -ErrorAction SilentlyContinue
    if ($RemoveDefender -eq 'yes') {
        Remove-Item -Path "$scratchDir\ProgramData\Microsoft\Windows Defender\Definition Updates" -Recurse -Force -ErrorAction SilentlyContinue
    }
    $inputMethodPaths = @("CHS", "CHT", "JPN", "KOR")
    foreach ($imPath in $inputMethodPaths) {
        Remove-Item -Path "$scratchDir\Windows\System32\InputMethod\$imPath" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path "$scratchDir\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    $foldersToRemove = @("Web", "Help", "Cursors")
    foreach ($folder in $foldersToRemove) {
        Remove-Item -Path (Join-Path -Path $winDir -ChildPath $folder) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Honor RemoveEdge parameter from workflow
if ($RemoveEdge -eq 'yes') {
    Write-Host "Removing Edge..."
    try {
        Get-ChildItem -Path "$scratchDir\Program Files (x86)" -Filter "Microsoft\Edge*" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "  Warning: Some Edge files could not be removed (continuing...)" -ForegroundColor Yellow
    }

    if ($architecture -eq 'amd64') { 
    try {
        $folderPath = Get-ChildItem -Path "$scratchDir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($folderPath) { 
            Remove-Item -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {
        Write-Host "  Warning: Edge WebView WinSxS folder could not be removed (continuing...)" -ForegroundColor Yellow
    }
    }

    Remove-Item -Path "$scratchDir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "Keeping Edge (RemoveEdge=no)"
}

# Keep WinRE.wim to preserve "Previous Version of Setup" option in Windows Setup
# Removing WinRE.wim causes the "Previous Version of Setup" option to disappear
# if (Test-Path "$scratchDir\Windows\System32\Recovery\winre.wim") {
#     try {
#         Remove-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -Recurse -Force -ErrorAction Stop
#         New-Item -Path "$scratchDir\Windows\System32\Recovery\winre.wim" -ItemType File -Force | Out-Null
#     } catch {
#         Write-Host "  Warning: WinRE could not be removed/replaced (continuing...)" -ForegroundColor Yellow
#     }
# }

Remove-Item -Path "$scratchDir\Windows\System32\OneDriveSetup.exe" -Force -ErrorAction SilentlyContinue 

Write-Host "Removing OneDrive Start Menu shortcuts:"
$startMenuPaths = @(
    "$scratchDir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
    "$scratchDir\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive",
    "$scratchDir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
    "$scratchDir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive"
)

foreach ($shortcutPath in $startMenuPaths) {
    if (Test-Path $shortcutPath) {
        & 'takeown' '/f' $shortcutPath '/r' 2>&1 | Out-Null
        & 'icacls' $shortcutPath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>&1 | Out-Null
        Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

& 'dism' '/English' "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' 

Write-Host "Taking ownership of the WinSxS folder. This might take a while..."
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\WinSxS" '/r'
& 'icacls' "$mainOSDrive\scratchdir\Windows\WinSxS" '/grant' "$($adminGroup.Value):(F)" '/T' '/C'
Write-host "Complete!"
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
} elseif ($architecture -eq "arm64") {
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
Write-Host "Enabling Local Accounts on OOBE (Windows 11 25H2+ compatible):"
# BypassNRO no longer works from Windows 11 25H2+, use ms-cxh:localonly URI scheme instead
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' '/v' 'OOBELocalAccount' '/t' 'REG_SZ' '/d' 'start ms-cxh:localonly' '/f' | Out-Null
# Keep BypassNRO for older Windows versions compatibility
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
Write-Host "Disabling Copilot"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' '/v' 'TurnOffWindowsCopilot' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' '/v' 'HubsSidebarEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' '/v' 'DisableSearchBoxSuggestions' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Prevents installation of Teams:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' '/v' 'DisableInstallation' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Prevent installation of New Outlook":
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' '/v' 'PreventRun' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
$tasksPath = "$mainOSDrive\scratchdir\Windows\System32\Tasks"

Write-Host "Deleting scheduled task definition files..."

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
# If Defender is kept, we need to allow Defender updates but can still disable OS updates
if ($RemoveDefender -eq 'yes') {
    Write-Host "Disabling Windows Update (Defender removed, so no updates needed)..."
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
} else {
    Write-Host "Keeping Windows Update services enabled (Defender needs them for definition updates)..."
    Write-Host "Disabling automatic OS updates (but allowing Defender updates)..."
    # Disable automatic OS updates, but keep Windows Update service running for Defender
    # Do NOT block Windows Update completely - Defender needs it for definition updates
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' '/v' 'NoAutoUpdate' '/t' 'REG_DWORD' '/d' '1' '/f'
    & 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' '/v' 'AUOptions' '/t' 'REG_DWORD' '/d' '1' '/f'  # Notify only
    # Keep wuauserv service enabled (Start = 2 = Automatic, but updates are manual)
    & 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv' '/v' 'Start' '/t' 'REG_DWORD' '/d' '2' '/f'
    # Do NOT delete WaaSMedicSVC and UsoSvc - Defender needs them
    Write-Host "Windows Update service kept enabled for Defender definition updates"
    Write-Host "Note: OS updates are disabled, but Defender can still update definitions"
}
# Honor RemoveDefender parameter from workflow
if ($RemoveDefender -eq 'yes') {
    Write-Host "Disabling Windows Defender"
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

Write-Host "Loading registry hives to remove services..."
reg load HKLM\zSYSTEM "$scratchDir\Windows\System32\config\SYSTEM" | Out-Null
$servicesToRemove = @( 
    'Spooler', 
    'PrintNotify', 
    'Fax', 
    'RemoteRegistry', 
    'diagsvc', 
    'WerSvc', 
    'PcaSvc', 
    #'DPS', 
    # 'Audiosrv', # CRITICAL: Removing this is a likely cause of boot failure.
    # 'AudioEndpointBuilder', # CRITICAL: Dependency for Audiosrv.
    'MapsBroker', 
    'WalletService', 
    # 'BthAvctpSvc', # KEPT to preserve Bluetooth functionality
    # 'BluetoothUserService', # KEPT to preserve Bluetooth functionality
    # 'WbioSrvc', # RISKY: Can cause logon screen to hang.
)
# Only remove Windows Update services if Defender is removed
# Defender needs Windows Update services to download definition updates
if ($RemoveDefender -eq 'yes') {
    $servicesToRemove += 'wuauserv'
    $servicesToRemove += 'UsoSvc'
    $servicesToRemove += 'WaaSMedicSvc'
    Write-Host "Windows Update services will be removed (Defender removed)"
} else {
    Write-Host "Keeping Windows Update services (wuauserv, UsoSvc, WaaSMedicSvc) for Defender updates"
}
foreach ($service in $servicesToRemove) { Write-Host "Removing service: $service"; & 'reg' 'delete' "HKLM\zSYSTEM\ControlSet001\Services\$service" /f | Out-Null }
reg unload HKLM\zSYSTEM 

Write-Host "Cleaning up and unmounting install.wim..."
& 'dism' '/English' "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' 
& 'dism' '/English' '/unmount-image' "/mountdir:$scratchDir" '/commit'
& 'dism' '/English' '/Export-Image' "/SourceImageFile:$mainOSDrive\nano11\sources\install.wim" "/SourceIndex:$index" "/DestinationImageFile:$mainOSDrive\nano11\sources\install2.wim" '/compress:max'
Remove-Item -Path "$mainOSDrive\nano11\sources\install.wim" -Force 
Rename-Item -Path "$mainOSDrive\nano11\sources\install2.wim" -NewName "install.wim" 

Write-Host "Mounting boot image (keeping both WinPE classic menu and Windows Setup)..."
$bootWimPath = "$mainOSDrive\nano11\sources\boot.wim" 
Write-Host "Taking ownership of $bootWimPath..."
& takeown "/F" $bootWimPath
& icacls $bootWimPath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $bootWimPath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Warning "$bootWimPath IsReadOnly property may not be settable (continuing...)"
}
Write-Host "Mounting Windows Setup image (index 2) to modify registry..."
& 'dism' '/English' '/mount-image' "/imagefile:$bootWimPath" '/index:2' "/mountdir:$scratchDir"
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM | Out-Null
Write-Host "Bypassing system requirements(on the setup image):"
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
Write-Host "Disabling BitLocker Device Encryption"
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' '/v' 'PreventDeviceEncryption' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "Tweaking complete!"
Write-Host "Unmounting Registry..."
reg unload HKLM\zNTUSER
reg unload HKLM\zDEFAULT
reg unload HKLM\zSOFTWARE
reg unload HKLM\zSYSTEM | Out-Null
Start-Sleep -Seconds 10
Write-Host "Unmounting image (keeping both indexes intact)..."
& 'dism' '/English' '/unmount-image' "/mountdir:$scratchDir" '/commit'

if (-not $NonInteractive) {
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Output "Exporting final image to highly compressed ESD format..."
& dism /Export-Image /SourceImageFile:"$mainOSDrive\nano11\sources\install.wim" /SourceIndex:1 /DestinationImageFile:"$mainOSDrive\nano11\sources\install.esd" /Compress:recovery
Remove-Item "$mainOSDrive\nano11\sources\install.wim" -ErrorAction SilentlyContinue

Write-Host "Performing final cleanup of installation folder root..."
$isoRoot = "$mainOSDrive\nano11"
$keepList = @("boot", "efi", "sources", "bootmgr", "bootmgr.efi", "setup.exe", "autounattend.xml")
Get-ChildItem -Path $isoRoot | Where-Object { $_.Name -notin $keepList } | ForEach-Object {
    Write-Host "Removing non-essential file/folder from ISO root: $($_.Name)"
    Remove-Item -Path $_.FullName -Recurse -Force
}

Write-Host "Creating bootable ISO image..."
$OSCDIMG = "$PSScriptRoot\oscdimg.exe"
if (-not (Test-Path $OSCDIMG)) { 
    try {
        $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
        Write-Host "Downloading oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $OSCDIMG -ErrorAction Stop
        Write-Host "✓ oscdimg.exe downloaded successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to download oscdimg.exe: $($_.Exception.Message)"
        exit 1
    }
}

$isoPath = "$PSScriptRoot\nano11.iso"
Write-Host "Running oscdimg to create ISO..."
try {
    & "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$mainOSDrive\nano11\boot\etfsboot.com#pEF,e,b$mainOSDrive\nano11\efi\microsoft\boot\efisys.bin" "$mainOSDrive\nano11" $isoPath 2>&1 | Out-Null
    
    # Verify ISO was created
    Start-Sleep -Seconds 2
    if (-not (Test-Path $isoPath)) {
        Write-Error "ISO was not created at expected path: $isoPath"
        exit 1
    }
    
    $isoSize = (Get-Item $isoPath).Length / 1GB
    Write-Output "✓ ISO created successfully: $isoPath" -ForegroundColor Green
    Write-Output "  ISO size: $([math]::Round($isoSize, 2)) GB"
    Write-Output "Creation completed! Your ISO is named nano11.iso"
} catch {
    Write-Error "Failed to create ISO: $($_.Exception.Message)"
    exit 1
}
if ($NonInteractive) {
    Write-Output "Build complete! Cleaning up..."
} else {
    Read-Host "Press Enter to perform cleanup and exit."
}
Write-Output "Performing Cleanup..."
& 'dism' '/English' '/unmount-image' "/mountdir:$scratchDir" '/discard' -ErrorAction SilentlyContinue
Remove-Item -Path "$mainOSDrive\nano11" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$mainOSDrive\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
Stop-Transcript
exit