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
    [ValidateSet('yes','no')][string]$RemoveStore = 'no',
    
    # Driver removal options (honored from workflow)
    [ValidateSet('yes','no')][string]$RemovePrinterDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveScannerDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveBluetoothDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveSmartcardDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveTapeDrivers = 'yes',
    [ValidateSet('yes','no')][string]$RemoveRdpDrivers = 'yes',
    
    # Custom ISO filename (optional, defaults to nano11.iso)
    [string]$IsoName = '',
    
    # IRST driver path (optional, path to folder containing IRST driver .inf files)
    # If not provided, will use IRST_Driver folder in project root
    [string]$IrstDriverPath = '',
    
    # Add Thorium browser to the image
    [ValidateSet('yes','no')][string]$AddThorium = 'no',
    
    # Preset configuration profile (name or path, e.g. 'gaming', 'minimal-vm', 'default')
    [string]$Preset = ''
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

# Debloat settings
$EnableDebloat = 'yes'
$RemoveOneDrive = 'yes'
$DisableTelemetry = 'yes'
$DisableSponsoredApps = 'yes'
$DisableAds = 'yes'
$DisableThirdPartyTelemetry = 'yes'
$TuneMouseLatency = 'yes'
$TuneDefenderCpuLimit = 'yes'
$EnableUltimatePerformance = 'no'

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

# Load Preset configuration if specified
if ($Preset -and (Get-Command Get-PresetConfig -ErrorAction SilentlyContinue)) {
    $presetObj = Get-PresetConfig -PresetNameOrPath $Preset
    if ($presetObj) {
        Write-Host "Applying Preset: $($presetObj.name) - $($presetObj.description)" -ForegroundColor Cyan
        if ($presetObj.debloat) {
            if (-not $PSBoundParameters.ContainsKey('RemoveDefender') -and $null -ne $presetObj.debloat.removeDefender) { $RemoveDefender = if ($presetObj.debloat.removeDefender) { 'yes' } else { 'no' } }
            if (-not $PSBoundParameters.ContainsKey('RemoveAI') -and $null -ne $presetObj.debloat.removeAI) { $RemoveAI = if ($presetObj.debloat.removeAI) { 'yes' } else { 'no' } }
            if (-not $PSBoundParameters.ContainsKey('RemoveEdge') -and $null -ne $presetObj.debloat.removeEdge) { $RemoveEdge = if ($presetObj.debloat.removeEdge) { 'yes' } else { 'no' } }
            if (-not $PSBoundParameters.ContainsKey('RemoveStore') -and $null -ne $presetObj.debloat.removeStore) { $RemoveStore = if ($presetObj.debloat.removeStore) { 'yes' } else { 'no' } }
        }
        if ($presetObj.privacy) {
            if (-not $PSBoundParameters.ContainsKey('DisableThirdPartyTelemetry') -and $null -ne $presetObj.privacy.disableThirdPartyTelemetry) { $DisableThirdPartyTelemetry = if ($presetObj.privacy.disableThirdPartyTelemetry) { 'yes' } else { 'no' } }
        }
        if ($presetObj.performance) {
            if (-not $PSBoundParameters.ContainsKey('TuneMouseLatency') -and $null -ne $presetObj.performance.tuneMouseLatency) { $TuneMouseLatency = if ($presetObj.performance.tuneMouseLatency) { 'yes' } else { 'no' } }
            if (-not $PSBoundParameters.ContainsKey('TuneDefenderCpuLimit') -and $null -ne $presetObj.performance.tuneDefenderCpuLimit) { $TuneDefenderCpuLimit = if ($presetObj.performance.tuneDefenderCpuLimit) { 'yes' } else { 'no' } }
            if (-not $PSBoundParameters.ContainsKey('EnableUltimatePerformance') -and $null -ne $presetObj.performance.enableUltimatePerformance) { $EnableUltimatePerformance = if ($presetObj.performance.enableUltimatePerformance) { 'yes' } else { 'no' } }
        }
    }
}


function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' 2>&1 | Out-Null
        Write-Output "Set registry value: $path\$name"
    } catch {
        Write-Output "Error setting registry value: $_"
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

function Dismount-RegistryHives {
    param(
        [string[]]$Hives = @('zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM')
    )
    Write-Host "Unmounting registry hives..." -ForegroundColor Cyan
    
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Start-Sleep -Seconds 1

    foreach ($hive in $Hives) {
        $regPath = "HKLM\$hive"
        $unloaded = $false
        for ($i = 1; $i -le 5; $i++) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            $res = & reg unload $regPath 2>&1
            if ($LASTEXITCODE -eq 0 -or $res -match "not loaded" -or $res -match "unable to find") {
                Write-Host "  ✓ Unloaded or not mounted: $regPath" -ForegroundColor Green
                $unloaded = $true
                break
            } else {
                Write-Host "  Attempt $($i): Failed to unload $regPath ($res). Retrying in 2 seconds..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }

        if (-not $unloaded) {
            Write-Warning "Failed to unload registry hive $regPath after 5 attempts."
        }
    }
}

function Dismount-WindowsImageWithRetry {
    param(
        [string]$Path,
        [switch]$Save = $true
    )
    Write-Host "Dismounting Windows Image at $Path..." -ForegroundColor Cyan
    
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.GC]::Collect()
    Start-Sleep -Seconds 2

    $success = $false
    for ($i = 1; $i -le 5; $i++) {
        try {
            if ($Save) {
                Dismount-WindowsImage -Path $Path -Save -ErrorAction Stop
            } else {
                Dismount-WindowsImage -Path $Path -Discard -ErrorAction Stop
            }
            Write-Host "✓ Dismounted Windows Image at $Path successfully" -ForegroundColor Green
            $success = $true
            break
        } catch {
            Write-Host "  Attempt $($i): Dismount-WindowsImage failed ($($_.Exception.Message)). Retrying in 5 seconds..." -ForegroundColor Yellow
            
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
            [System.GC]::Collect()
            Start-Sleep -Seconds 5
            
            if ($i -ge 3) {
                Write-Host "  Attempting direct dism.exe unmount command..." -ForegroundColor Cyan
                $saveFlag = if ($Save) { '/commit' } else { '/discard' }
                $dismRes = & dism.exe /English /unmount-image "/mountdir:$Path" $saveFlag 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ Direct dism.exe unmount succeeded!" -ForegroundColor Green
                    $success = $true
                    break
                } else {
                    Write-Host "  Direct dism.exe unmount output: $dismRes" -ForegroundColor Yellow
                }
            }
        }
    }

    if (-not $success) {
        Write-Error "The directory could not be completely unmounted at $Path after multiple attempts."
        & dism.exe /Cleanup-Wim 2>&1 | Out-Null
    }
    return $success
}

# Function to inject driver into mounted image
function Add-DriverToImage {
    param (
        [string]$MountPath,
        [string]$DriverPath,
        [string]$ImageName
    )
    
    # 1. Locate or auto-acquire IRST Driver folder
    if (-not $DriverPath -or -not (Test-Path $DriverPath)) {
        $projectIrstFolder = Join-Path $PSScriptRoot "IRST_Driver"
        if (Test-Path $projectIrstFolder) {
            Write-Host "Using IRST driver from project folder: $projectIrstFolder" -ForegroundColor Cyan
            $DriverPath = $projectIrstFolder
        } else {
            # Check workspace root as secondary fallback
            $workspaceIrstFolder = Join-Path $env:GITHUB_WORKSPACE "IRST_Driver"
            if ($env:GITHUB_WORKSPACE -and (Test-Path $workspaceIrstFolder)) {
                $DriverPath = $workspaceIrstFolder
            } else {
                Write-Host "IRST driver folder not found. Auto-downloading universal Intel RST VMD drivers..." -ForegroundColor Cyan
                $tempIrstDir = Join-Path $env:TEMP "Universal_IRST_Driver"
                try {
                    if (-not (Test-Path $tempIrstDir)) { New-Item -ItemType Directory -Path $tempIrstDir -Force | Out-Null }
                    # Download VMD driver package
                    $vmdUrl = "https://raw.githubusercontent.com/namnguyen97x/tiny-auto-builder/main/IRST_Driver/iastorvd.inf_amd64_15c9ea6001a5206d/iaStorVD.inf"
                    $sysUrl = "https://raw.githubusercontent.com/namnguyen97x/tiny-auto-builder/main/IRST_Driver/iastorvd.inf_amd64_15c9ea6001a5206d/iaStorVD.sys"
                    $catUrl = "https://raw.githubusercontent.com/namnguyen97x/tiny-auto-builder/main/IRST_Driver/iastorvd.inf_amd64_15c9ea6001a5206d/iaStorVD.cat"
                    Invoke-WebRequest -Uri $vmdUrl -OutFile (Join-Path $tempIrstDir "iaStorVD.inf") -UseBasicParsing -ErrorAction SilentlyContinue
                    Invoke-WebRequest -Uri $sysUrl -OutFile (Join-Path $tempIrstDir "iaStorVD.sys") -UseBasicParsing -ErrorAction SilentlyContinue
                    Invoke-WebRequest -Uri $catUrl -OutFile (Join-Path $tempIrstDir "iaStorVD.cat") -UseBasicParsing -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Could not auto-download IRST fallback: $_"
                }
                if (Test-Path (Join-Path $tempIrstDir "iaStorVD.inf")) {
                    $DriverPath = $tempIrstDir
                } else {
                    Write-Host "IRST driver path not provided and IRST_Driver folder not found, skipping driver injection." -ForegroundColor Yellow
                    return
                }
            }
        }
    }
    
    Write-Host "Injecting IRST driver into $ImageName..." -ForegroundColor Cyan
    Write-Host "Driver path: $DriverPath" -ForegroundColor Gray
    
    $infFiles = Get-ChildItem -Path $DriverPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
    if (-not $infFiles) {
        Write-Warning "No .inf files found in driver path: $DriverPath"
        return
    }
    
    # 2. Attempt fast recursive batch injection first
    try {
        $result = & dism /English /image:"$MountPath" /add-driver /driver:"$DriverPath" /recurse 2>&1
        $outputString = $result -join "`n"
        if ($LASTEXITCODE -eq 0 -and -not ($outputString | Select-String -Pattern "Error|Failed|failed" -Quiet)) {
            Write-Host "✓ IRST drivers injected successfully into $ImageName" -ForegroundColor Green
            return
        }
    } catch {
        Write-Warning "Direct batch injection returned an error, trying subfolder fallback..."
    }

    # 3. Fallback to subfolder-by-subfolder injection if batch call failed
    $driverFolders = Get-ChildItem -Path $DriverPath -Directory -ErrorAction SilentlyContinue | Where-Object {
        (Get-ChildItem -Path $_.FullName -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue).Count -gt 0
    }
    
    if ($driverFolders.Count -gt 0) {
        Write-Host "Injecting $($driverFolders.Count) driver subfolders into $ImageName..." -ForegroundColor Cyan
        $successCount = 0
        $failCount = 0
        
        foreach ($driverFolder in $driverFolders) {
            try {
                $result = & dism /English /image:"$MountPath" /add-driver /driver:"$($driverFolder.FullName)" /recurse 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $successCount++
                } else {
                    $failCount++
                }
            } catch {
                $failCount++
            }
        }
        Write-Host "Driver injection completed: $successCount succeeded, $failCount failed" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Yellow" })
    }
} 

if (-not $NonInteractive) {
    try {
        $Host.UI.RawUI.WindowTitle = "Nano11 image creator"
        Clear-Host
    } catch {
        # Ignore errors in non-interactive environments
    }
}

Write-Output "Welcome to nano11 builder!"
Write-Output "This script generates a significantly reduced Windows 11 image. However, it is not suitable for regular use due to its lack of serviceability - you cannot add languages, updates, or drivers after deployment. This is designed for creating minimal Windows 11 ISOs."

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
    # Exclude Recovery folder to preserve WinRE.wim and "Previous Version of Setup" option
    # "$scratchDir\Windows\System32\Recovery",
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
foreach ($line in $lines) { if ($line -like '*Architecture : *') { $architecture = $line -replace 'Architecture : ',''; if ($architecture -eq 'x64') { $architecture = 'amd64' }; Write-Host "Architecture: $architecture" } }
if (-not $architecture) { Write-Host "Architecture information not found." }
Write-Host "Removing provisioned AppX packages (bloatware)..."
$packagesToRemove = Get-AppxProvisionedPackage -Path $scratchDir | Where-Object { $_.PackageName -like '*Zune*' -or $_.PackageName -like '*Bing*' -or $_.PackageName -like '*Clipchamp*' -or $_.PackageName -like '*OneDrive*' -or $_.PackageName -like '*Teams*' -or $_.PackageName -like '*XboxApp*' -or $_.PackageName -like '*SkypeApp*' }
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
foreach ($package in $packagesToRemove) { $folderPath = Join-Path "$scratchDir\Program Files\WindowsApps" $package.PackageName; if (Test-Path $folderPath) { Write-Host "Deleting folder: $($package.PackageName)"; Remove-Item -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue } }

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

# Note: .NET Framework 3.5 will be enabled AFTER Windows Update services are configured
# This ensures Windows Update services are available for .NET 3.5 installation in Windows 11 25H2

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

# Remove Start Menu shortcuts for debloated apps
Write-Host "Removing Start Menu shortcuts for debloated apps..."
$startMenuBasePaths = @(
    "$scratchDir\ProgramData\Microsoft\Windows\Start Menu\Programs",
    "$scratchDir\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
)

# Apps to remove shortcuts for based on debloat parameters
$shortcutsToRemove = @()

# Microsoft Edge shortcuts (if RemoveEdge=yes)
if ($RemoveEdge -eq 'yes') {
    $shortcutsToRemove += "Microsoft Edge.lnk"
    $shortcutsToRemove += "Microsoft Edge"
    $shortcutsToRemove += "Microsoft Edge Update.lnk"
    $shortcutsToRemove += "Microsoft Edge Update"
    Write-Host "  Removing Edge shortcuts..."
}

# Microsoft Store shortcuts (if RemoveStore=yes)
if ($RemoveStore -eq 'yes') {
    $shortcutsToRemove += "Microsoft Store.lnk"
    $shortcutsToRemove += "Microsoft Store"
    Write-Host "  Removing Store shortcuts..."
}

# Remove shortcuts from both Start Menu locations
foreach ($basePath in $startMenuBasePaths) {
    if (Test-Path $basePath) {
        foreach ($shortcutName in $shortcutsToRemove) {
            $shortcutPath = Join-Path $basePath $shortcutName
            if (Test-Path $shortcutPath) {
                try {
                    & 'takeown' '/f' $shortcutPath '/r' 2>&1 | Out-Null
                    & 'icacls' $shortcutPath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>&1 | Out-Null
                    Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    # Silently continue if shortcut removal fails
                }
            }
        }
        
        # Also remove any shortcuts containing "Microsoft Edge" or "Microsoft Store" in their names
        if ($RemoveEdge -eq 'yes') {
            Get-ChildItem -Path $basePath -Filter "*Edge*" -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    & 'takeown' '/f' $_.FullName '/r' 2>&1 | Out-Null
                    & 'icacls' $_.FullName '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>&1 | Out-Null
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        }
        
        if ($RemoveStore -eq 'yes') {
            Get-ChildItem -Path $basePath -Filter "*Store*" -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    & 'takeown' '/f' $_.FullName '/r' 2>&1 | Out-Null
                    & 'icacls' $_.FullName '/grant' "$($adminGroup.Value):(F)" '/T' '/C' 2>&1 | Out-Null
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                } catch { }
            }
        }
    }
}
Write-Host "Start Menu shortcuts cleanup complete."

& 'dism' '/English' "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' 

Write-Host "Taking ownership of the WinSxS folder. This might take a while..."
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\WinSxS" '/r'
& 'icacls' "$mainOSDrive\scratchdir\Windows\WinSxS" '/grant' "$($adminGroup.Value):(F)" '/T' '/C'
Write-host "Complete!"
$folderPath = Join-Path -Path $mainOSDrive -ChildPath "\scratchdir\Windows\WinSxS_edit"
$sourceDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS"
$destinationDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS_edit"
New-Item -Path $folderPath -ItemType Directory -Force | Out-Null
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
            Write-Host "Copying $($sourceDir.FullName) to $destDir"
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
     foreach ($dir in $dirsToCopy) {
        $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory
        foreach ($sourceDir in $sourceDirs) {
            $destDir = Join-Path -Path $destinationDirectory -ChildPath $sourceDir.Name
            Write-Host "Copying $($sourceDir.FullName) to $destDir"
            Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force
        }
    }
} else {
    Write-Host "Unknown architecture: $architecture. Skipping WinSxS optimization."
}


Write-Host "Deleting WinSxS. This may take a while..."
        Remove-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS -Recurse -Force

Rename-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS_edit -NewName WinSxS
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
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338387Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SystemPaneSuggestionsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

Write-Host "Disabling Windows Spotlight and Lock Screen tips:"
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'RotatingLockScreenEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'RotatingLockScreenOverlayEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
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

    if (Get-Command Apply-ExtendedTelemetryAndPerformanceTweaks -ErrorAction SilentlyContinue) {
        Apply-ExtendedTelemetryAndPerformanceTweaks `
            -DisableThirdPartyTelemetry ($DisableThirdPartyTelemetry -eq 'yes') `
            -TuneMouseLatency ($TuneMouseLatency -eq 'yes') `
            -TuneDefenderCpuLimit ($TuneDefenderCpuLimit -eq 'yes') `
            -EnableUltimatePerformance ($EnableUltimatePerformance -eq 'yes')
    }

}

Write-Host "Enabling Local Accounts on OOBE (Windows 11 25H2+ compatible):"
# BypassNRO no longer works from Windows 11 25H2+, use ms-cxh:localonly URI scheme instead
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' '/v' 'OOBELocalAccount' '/t' 'REG_SZ' '/d' 'start ms-cxh:localonly' '/f' | Out-Null
# Keep BypassNRO for older Windows versions compatibility
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'BypassNRO' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null

# Generate dynamic autounattend.xml
if (Get-Command New-DynamicAutounattendXml -ErrorAction SilentlyContinue) {
    New-DynamicAutounattendXml -OutputPath "$PSScriptRoot\autounattend.xml" `
        -BypassTPM:$true `
        -BypassRAM:$true `
        -BypassStorage:$true `
        -CompactOS:$true
}

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
Write-Host "Disabling Search Highlights:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\SearchSettings' '/v' 'IsDynamicSearchBoxEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

Write-Host "Disabling Bing Search in Start Bar:"
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' '/v' 'BingSearchEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

Write-Host "Disabling Auto Discovery:"
# Ensure the registry path exists
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' '/v' 'FolderType' '/t' 'REG_SZ' '/d' 'NotSpecified' '/f' | Out-Null
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
    & 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisableWUPostOOBE1' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\wuauserv /v Start /t REG_DWORD /d 4' '/f'
    & 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisableWUPostOOBE2' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\WaaSMedicSvc /v Start /t REG_DWORD /d 4' '/f'
} else {
    Write-Host "Keeping Windows Update (RemoveDefender=no, so we need Windows Update for Defender)"
}

Dismount-RegistryHives

# Inject IRST driver into install.wim (uses IRST_Driver folder or auto-downloads universal VMD drivers)
Add-DriverToImage -MountPath "$mainOSDrive\scratchdir" -DriverPath $IrstDriverPath -ImageName "install.wim"

# Add Thorium browser (optional)
if ($AddThorium -eq 'yes') {
    Write-Host "=== Adding Thorium Browser ===" -ForegroundColor Cyan
    function Add-ThoriumBrowser {
        param([string]$MountPath)
        $tempDir = "$env:TEMP\ThoriumDownload"
        $thoriumDir = "$MountPath\Program Files\Thorium"
        try {
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            Write-Host "Fetching Thorium release info from GitHub..." -ForegroundColor Cyan
            $asset = $null
            $apiUrl = "https://api.github.com/repos/Alex313031/Thorium-Win/releases"
            try {
                $releases = Invoke-RestMethod -Uri $apiUrl -Headers @{ 'User-Agent' = 'PowerShell' } -ErrorAction Stop
                foreach ($rel in $releases) {
                    $match = $rel.assets | Where-Object { 
                        $_.name -like '*.zip' -and $_.name -notlike '*policy*' -and $_.name -notlike '*debug*'
                    } | Select-Object -First 1
                    if ($match) {
                        $asset = $match
                        break
                    }
                }
            } catch {
                Write-Warning "Failed to query Thorium GitHub API: $($_.Exception.Message)"
            }
            if (-not $asset) { Write-Warning "No suitable Thorium asset found"; return $false }
            Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
            $downloadPath = Join-Path $tempDir $asset.name
            Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
            if ($asset.name -like '*.zip') {
                Expand-Archive -Path $downloadPath -DestinationPath $tempDir -Force
            } elseif ($asset.name -like '*.7z') {
                $seven = "C:\Program Files\7-Zip\7z.exe"
                if (-not (Test-Path $seven)) { Write-Warning "7-Zip not found; use .zip"; return $false }
                & $seven x "$downloadPath" "-o$tempDir" -y | Out-Null
            }
            $extracted = (Get-ChildItem -Path $tempDir -Directory | Where-Object { $_.Name -like '*thorium*' -or $_.Name -like '*Thorium*' } | Select-Object -First 1)
            if (-not $extracted) {
                $exe = Get-ChildItem -Path $tempDir -Filter 'thorium.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exe) { $extracted = $exe.Directory }
            }
            if (-not $extracted) { Write-Warning "Thorium extraction not found"; return $false }
            if (Test-Path $thoriumDir) { Remove-Item -Path $thoriumDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $thoriumDir -Force | Out-Null
            Copy-Item -Path "$($extracted.FullName)\*" -Destination $thoriumDir -Recurse -Force
            if (-not (Test-Path "$thoriumDir\thorium.exe")) { Write-Warning "thorium.exe missing after copy"; return $false }
            $startMenuPath = "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs"
            $startMenuPrograms = "$startMenuPath\Thorium"
            if (-not (Test-Path $startMenuPrograms)) { New-Item -ItemType Directory -Path $startMenuPrograms -Force | Out-Null }
            $wshShell = New-Object -ComObject WScript.Shell
            $shortcut = $wshShell.CreateShortcut("$startMenuPrograms\Thorium Browser.lnk")
            $shortcut.TargetPath = "C:\Program Files\Thorium\thorium.exe"
            $shortcut.WorkingDirectory = "C:\Program Files\Thorium"
            $shortcut.Description = "Thorium Browser"
            $shortcut.Save()
            return $true
        } catch {
            Write-Warning "Thorium install failed: $($_.Exception.Message)"
            return $false
        } finally {
            if (Test-Path $tempDir) { Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    $ok = Add-ThoriumBrowser -MountPath "$mainOSDrive\scratchdir"
    if ($ok) { Write-Host "✓ Thorium installed" -ForegroundColor Green } else { Write-Host "⚠ Thorium installation failed" -ForegroundColor Yellow }
}

Write-Output "Cleaning up image..."
dism.exe /Image:$mainOSDrive\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Output "Cleanup complete."
Write-Output ' '
Write-Output "Unmounting image..."
Dismount-WindowsImageWithRetry -Path "$mainOSDrive\scratchdir" -Save
Write-Host "Exporting image..."
Dism.exe /Export-Image /SourceImageFile:"$mainOSDrive\nano11\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$mainOSDrive\nano11\sources\install2.wim" /Compress:recovery
Remove-Item -Path "$mainOSDrive\nano11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$mainOSDrive\nano11\sources\install2.wim" -NewName "install.wim" | Out-Null
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
$wimFilePath = "$mainOSDrive\nano11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    Write-Warning "$wimFilePath IsReadOnly property may not be settable (continuing...)"
}
Write-Output "Mounting Windows Setup image (index 2) to modify registry..."
Mount-WindowsImage -ImagePath $mainOSDrive\nano11\sources\boot.wim -Index 2 -Path "$mainOSDrive\scratchdir"
Write-Output "Loading registry..."
reg load HKLM\zCOMPONENTS $mainOSDrive\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM

Write-Output "Bypassing system requirements(on the setup image):"
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
Write-Output "Tweaking complete!"

Dismount-RegistryHives

# Inject IRST driver into boot.wim (Windows Setup) (uses IRST_Driver folder or auto-downloads universal VMD drivers)
Add-DriverToImage -MountPath "$mainOSDrive\scratchdir" -DriverPath $IrstDriverPath -ImageName "boot.wim (Windows Setup)"

Write-Output "Unmounting image (keeping both indexes intact)..."
Dismount-WindowsImageWithRetry -Path "$mainOSDrive\scratchdir" -Save
if (-not $NonInteractive) {
    try {
        Clear-Host
    } catch {
        # Ignore Clear-Host errors in non-interactive environments
    }
}
Write-Output "The nano11 image is now completed. Proceeding with the making of the ISO..."
Write-Output "Copying unattended file for bypassing MS account on OOBE..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$mainOSDrive\nano11\autounattend.xml" -Force | Out-Null
Write-Output "Creating ISO image..."
$hostArchitecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
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
    $name = $IsoName.Trim()
    if (-not $name.EndsWith('.iso', [System.StringComparison]::OrdinalIgnoreCase)) {
        $name = "$name.iso"
    }
    $name
} else {
    'nano11.iso'
}

Write-Output "Running oscdimg to create ISO..."
$isoPath = "$PSScriptRoot\$isoFileName"
Write-Host "ISO will be saved as: $isoFileName" -ForegroundColor Cyan
try {
    $oscdimgOutput = & "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$mainOSDrive\nano11\boot\etfsboot.com#pEF,e,b$mainOSDrive\nano11\efi\microsoft\boot\efisys.bin" "$mainOSDrive\nano11" $isoPath 2>&1
    Write-Host ($oscdimgOutput -join "`n") -ForegroundColor Gray
    
    # Verify ISO was created
    Start-Sleep -Seconds 2
    if (-not (Test-Path $isoPath)) {
        Write-Error "ISO was not created at expected path: $isoPath"
        if ($oscdimgOutput) {
            Write-Error "oscdimg output: $($oscdimgOutput -join "`n")"
        }
        exit 1
    }
    
    $isoSize = (Get-Item $isoPath).Length / 1GB
    Write-Host "✓ ISO created successfully: $isoPath" -ForegroundColor Green
    Write-Output "  ISO size: $([math]::Round($isoSize, 2)) GB"
    exit 0
} catch {
    Write-Error "Failed to create ISO: $($_.Exception.Message)"
    exit 1
}


