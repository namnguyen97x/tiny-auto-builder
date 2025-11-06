# Windows LTSC ISO Builder with Microsoft Store
# Supports: Enterprise LTSC, IoT Enterprise LTSC, IoT Enterprise Subscription LTSC
# Includes debloat features (similar to tiny11maker) but keeps AI and optionally adds Store

param(
    [Parameter(Mandatory=$true)]
    [string]$DriveLetter,
    
    [Parameter(Mandatory=$false)]
    [string]$StorePackagesDir = '',
    
    [Parameter(Mandatory=$true)]
    [string]$Edition,
    
    [Parameter(Mandatory=$true)]
    [string]$IsoName,
    
    # Debloat options (similar to tiny11maker)
    [ValidateSet('yes','no')]
    [string]$RemoveDefender = 'no',
    
    [ValidateSet('yes','no')]
    [string]$RemoveEdge = 'yes',
    
    # Remove AI option (yes = remove AI/Copilot, no = keep AI) - default no vì LTSC thường không có AI
    [ValidateSet('yes','no')]
    [string]$RemoveAI = 'no',
    
    # Add Store option (yes = add Store, no = don't add Store)
    [ValidateSet('yes','no')]
    [string]$AddStore = 'yes',
    
    # IRST driver path (optional, path to folder containing IRST driver .inf files)
    # If not provided, will use IRST_Driver folder in project root
    [string]$IrstDriverPath = ''
)

$ErrorActionPreference = 'Continue'

# Debloat settings - tự động enable theo chính sách của maker
# RemoveAI được set từ parameter (default='no' vì LTSC thường không có AI chính thức)
# và có option AddStore để thêm Microsoft Store
$EnableDebloat = 'yes'
$RemoveAppx = 'yes'
$RemoveCapabilities = 'yes'
$RemoveWindowsPackages = 'yes'
$RemoveOneDrive = 'yes'
$DisableTelemetry = 'yes'
$DisableSponsoredApps = 'yes'
$DisableAds = 'yes'
# $RemoveAI được set từ parameter (không hardcode nữa)
$RemoveStore = if ($AddStore -eq 'yes') { 'no' } else { 'yes' }  # Remove Store if AddStore=no

# Determine script root directory (works in both local and GitHub Actions)
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    # Fallback for GitHub Actions or when script is dot-sourced
    $scriptRoot = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { $PWD.Path }
}

# Import debloater module
if ($EnableDebloat -eq 'yes') {
    $modulePath = Join-Path $scriptRoot "tiny11-debloater.psm1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force -ErrorAction SilentlyContinue
        Write-Host "Debloater module loaded" -ForegroundColor Green
    } else {
        Write-Warning "Debloater module not found at $modulePath. Debloat features will be disabled."
        $EnableDebloat = 'no'
    }
}

Write-Host "=== Windows LTSC ISO Builder with Store ===" -ForegroundColor Cyan
Write-Host "Drive Letter: $DriveLetter"
Write-Host "Store Packages: $StorePackagesDir"
Write-Host "Target Edition: $Edition"
Write-Host "ISO Name: $IsoName"
Write-Host "Debloat options: Defender=$RemoveDefender, AI=$RemoveAI, Edge=$RemoveEdge, Store=$RemoveStore, AddStore=$AddStore" -ForegroundColor Cyan

# Validate inputs
if (-not (Test-Path "$DriveLetter\sources\install.wim") -and -not (Test-Path "$DriveLetter\sources\install.esd")) {
    Write-Error "Windows installation files not found in $DriveLetter"
    exit 1
}

# StorePackagesDir is only required if AddStore = yes
if ($AddStore -eq 'yes' -and (-not $StorePackagesDir -or -not (Test-Path $StorePackagesDir))) {
    Write-Error "Store packages directory required when AddStore=yes, but not found: $StorePackagesDir"
    exit 1
}

$mainOSDrive = $env:SystemDrive
$scratchDir = "$mainOSDrive\scratchdir"

# Check for admin privileges (required for DISM operations)
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Script is not running with administrator privileges. Some operations may fail."
    Write-Warning "In GitHub Actions, runner should have admin privileges by default."
}

# Create working directories with proper permissions
Write-Host "Creating working directories..."
try {
    New-Item -ItemType Directory -Force -Path "$mainOSDrive\ltsc" -ErrorAction Stop | Out-Null
    New-Item -ItemType Directory -Force -Path "$mainOSDrive\ltsc\sources" -ErrorAction Stop | Out-Null
    
    # Ensure scratch directory has write permissions
    if (Test-Path $scratchDir) {
        Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Force -Path $scratchDir -ErrorAction Stop | Out-Null
    
    Write-Host "Directories created successfully" -ForegroundColor Green
} catch {
    Write-Error "Failed to create working directories: $_"
    exit 1
}

Write-Host "Copying Windows image..."
Copy-Item -Path "$DriveLetter\*" -Destination "$mainOSDrive\ltsc" -Recurse -Force | Out-Null

# Convert ESD to WIM if needed
if (Test-Path "$mainOSDrive\ltsc\sources\install.esd") {
    Write-Host "Converting install.esd to install.wim..."
    & 'dism' '/English' '/Export-Image' "/SourceImageFile:$mainOSDrive\ltsc\sources\install.esd" "/SourceIndex:1" "/DestinationImageFile:$mainOSDrive\ltsc\sources\install.wim" '/Compress:max' '/CheckIntegrity'
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to convert ESD to WIM"
        exit 1
    }
    Remove-Item "$mainOSDrive\ltsc\sources\install.esd" -Force -ErrorAction SilentlyContinue
}

Write-Host "Getting image information..."
$wimInfoOutput = & 'dism' '/English' "/Get-WimInfo" "/wimfile:$mainOSDrive\ltsc\sources\install.wim"
$wimInfoOutput | Write-Host

# Auto-detect edition
Write-Host "Auto-detecting edition: $Edition" -ForegroundColor Cyan
$index = $null
$targetEditions = @()
$currentIndex = $null
$currentName = $null

foreach ($line in $wimInfoOutput) {
    if ($line -match 'Index : (\d+)') {
        $currentIndex = [int]$Matches[1]
    } elseif ($line -match 'Name : (.+)') {
        $currentName = $Matches[1].Trim()
        if ($currentIndex -and $currentName) {
            $match = $false
            $priority = 999
            
            # Check for exact match first (highest priority)
            if ($currentName -eq $Edition) {
                $match = $true
                $priority = 1
            }
            # Check for partial match based on edition type
            elseif ($Edition -eq 'IoT Enterprise LTSC' -and $currentName -like '*IoT Enterprise LTSC*' -and $currentName -notlike '*Subscription*') {
                $match = $true
                $priority = 2
            }
            elseif ($Edition -eq 'Enterprise LTSC' -and $currentName -like '*Enterprise LTSC*' -and $currentName -notlike '*IoT*') {
                $match = $true
                $priority = 2
            }
            elseif ($Edition -eq 'IoT Enterprise Subscription LTSC' -and $currentName -like '*IoT Enterprise Subscription LTSC*') {
                $match = $true
                $priority = 2
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
    $bestEdition = $targetEditions | Sort-Object Priority | Select-Object -First 1
    $index = $bestEdition.Index
    Write-Host "Found edition: $($bestEdition.Name) (Index: $index)" -ForegroundColor Green
} else {
    Write-Host "Edition '$Edition' not found in available editions, using index 1" -ForegroundColor Yellow
    $index = 1
}

# Mount image
Write-Host "Mounting Windows image (Index: $index)..." -ForegroundColor Cyan

# Set permissions for WIM file before mounting (same as tiny11maker.ps1)
$wimFilePath = "$mainOSDrive\ltsc\sources\install.wim"
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])

Write-Host "Setting permissions for WIM file..." -ForegroundColor Gray
& takeown "/F" $wimFilePath 2>&1 | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)" 2>&1 | Out-Null

try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
    Write-Host "WIM file permissions set successfully" -ForegroundColor Green
} catch {
    Write-Warning "WIM file IsReadOnly property may not be settable (continuing...)"
}

# Ensure scratch directory exists
New-Item -ItemType Directory -Force -Path $scratchDir -ErrorAction Stop | Out-Null

# Mount using Mount-WindowsImage (same as tiny11maker.ps1)
Write-Host "Mounting image (this may take a while)..." -ForegroundColor Gray
Mount-WindowsImage -ImagePath $wimFilePath -Index $index -Path $scratchDir

Write-Host "Image mounted successfully" -ForegroundColor Green

# Get language code and architecture for debloat
Write-Host "Getting image information for debloat..." -ForegroundColor Gray
$imageIntl = & dism /English /Get-Intl "/Image:$scratchDir"
$languageLine = $imageIntl -split '\n' | Where-Object { $_ -match 'Default system UI language : ([a-zA-Z]{2}-[a-zA-Z]{2})' }
$languageCode = if ($languageLine) { $Matches[1] } else { 'en-US' }

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$mainOSDrive\ltsc\sources\install.wim" "/index:$index"
$lines = $imageInfo -split '\r?\n'
$architecture = 'amd64'
foreach ($line in $lines) {
    if ($line -like '*Architecture : *') {
        $arch = $line -replace 'Architecture : ',''
        if ($arch -eq 'x64') { $architecture = 'amd64' }
        elseif ($arch -eq 'ARM64') { $architecture = 'arm64' }
        else { $architecture = $arch.ToLower() }
        break
    }
}

Write-Host "Language: $languageCode, Architecture: $architecture" -ForegroundColor Gray

# Function to inject driver into mounted image
function Add-DriverToImage {
    param (
        [string]$MountPath,
        [string]$DriverPath,
        [string]$ImageName
    )
    
    # If no driver path provided, try to use IRST_Driver folder in project root
    if (-not $DriverPath -or -not (Test-Path $DriverPath)) {
        $projectIrstFolder = Join-Path $scriptRoot "IRST_Driver"
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

# Perform debloat (similar to tiny11maker)
Write-Host "=== Starting Debloat Process ===" -ForegroundColor Cyan

# Sử dụng debloater module nếu được enable (same as tiny11maker.ps1)
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Host "Using integrated debloater from Windows-ISO-Debloater..." -ForegroundColor Cyan
    
    # Get packages để filter Store và AI (same as tiny11maker.ps1)
    $allPackages = Get-ProvisionedAppxPackage -Path $scratchDir -ErrorAction SilentlyContinue
    
    # Filter Store packages if RemoveStore = no
    if ($RemoveStore -eq 'no') {
        $storePackages = $allPackages | Where-Object { $_.PackageName -like '*WindowsStore*' -or $_.PackageName -like '*StorePurchaseApp*' -or $_.PackageName -like '*Store.Engagement*' }
        foreach ($storePkg in $storePackages) {
            Write-Host "  Keeping Store package: $($storePkg.PackageName)" -ForegroundColor Gray
        }
    }
    
    # Filter AI packages if RemoveAI = no
    if ($RemoveAI -eq 'no') {
        $aiPackages = $allPackages | Where-Object { $_.PackageName -like '*Copilot*' -or $_.PackageName -like '*549981C3F5F10*' }
        foreach ($aiPkg in $aiPackages) {
            Write-Host "  Keeping AI package: $($aiPkg.PackageName)" -ForegroundColor Gray
        }
    }
    
    Remove-DebloatPackages -MountPath $scratchDir `
        -RemoveAppx:($RemoveAppx -eq 'yes') `
        -RemoveCapabilities:($RemoveCapabilities -eq 'yes') `
        -RemoveWindowsPackages:($RemoveWindowsPackages -eq 'yes') `
        -LanguageCode $languageCode `
        -RemoveStore:($RemoveStore -eq 'yes') `
        -RemoveAI:($RemoveAI -eq 'yes') `
        -RemoveDefender:($RemoveDefender -eq 'yes')
    
    Remove-DebloatFiles -MountPath $scratchDir `
        -RemoveEdge:($RemoveEdge -eq 'yes') `
        -RemoveOneDrive:($RemoveOneDrive -eq 'yes') `
        -Architecture $architecture
    
    # Remove Store packages manually if RemoveStore = yes (same as tiny11maker.ps1)
    # Note: If RemoveAppx = yes, these may already be removed by Remove-DebloatPackages
    if ($RemoveStore -eq 'yes') {
        Write-Host "Removing Microsoft Store packages..." -ForegroundColor Cyan
        # Get fresh package list after Remove-DebloatPackages may have removed some
        $currentPackages = Get-ProvisionedAppxPackage -Path $scratchDir -ErrorAction SilentlyContinue
        $storePackages = $currentPackages | Where-Object { $_.PackageName -like '*WindowsStore*' -or $_.PackageName -like '*StorePurchaseApp*' -or $_.PackageName -like '*Store.Engagement*' }
        
        if ($storePackages.Count -eq 0) {
            Write-Host "  No Store packages found (may have been removed already by debloater)" -ForegroundColor Gray
        } else {
            foreach ($storePkg in $storePackages) {
                Write-Host "  Removing: $($storePkg.PackageName)" -ForegroundColor Gray
                try {
                    Remove-ProvisionedAppxPackage -Path $scratchDir -PackageName $storePkg.PackageName -ErrorAction Stop | Out-Null
                    Write-Host "    ✓ Removed successfully" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠ Warning: Failed to remove $($storePkg.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    # Remove AI packages manually if RemoveAI = yes (same as tiny11maker.ps1)
    # Note: If RemoveAppx = yes, these may already be removed by Remove-DebloatPackages
    if ($RemoveAI -eq 'yes') {
        Write-Host "Removing AI/Copilot packages..." -ForegroundColor Cyan
        # Get fresh package list after Remove-DebloatPackages may have removed some
        $currentPackages = Get-ProvisionedAppxPackage -Path $scratchDir -ErrorAction SilentlyContinue
        $aiPackages = $currentPackages | Where-Object { $_.PackageName -like '*Copilot*' -or $_.PackageName -like '*549981C3F5F10*' }
        
        if ($aiPackages.Count -eq 0) {
            Write-Host "  No AI packages found (may have been removed already by debloater)" -ForegroundColor Gray
        } else {
            foreach ($aiPkg in $aiPackages) {
                Write-Host "  Removing: $($aiPkg.PackageName)" -ForegroundColor Gray
                try {
                    Remove-ProvisionedAppxPackage -Path $scratchDir -PackageName $aiPkg.PackageName -ErrorAction Stop | Out-Null
                    Write-Host "    ✓ Removed successfully" -ForegroundColor Green
                } catch {
                    Write-Host "    ⚠ Warning: Failed to remove $($aiPkg.PackageName) - $($_.Exception.Message)" -ForegroundColor Yellow
                }
            }
        }
    }
    
    Write-Host "Debloat packages removal completed" -ForegroundColor Green
} else {
    Write-Warning "Debloater module not available, skipping advanced debloat..."
}

# Load registry for tweaks
Write-Host "Loading registry for tweaks..." -ForegroundColor Cyan
reg load HKLM\zCOMPONENTS $scratchDir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $scratchDir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $scratchDir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $scratchDir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $scratchDir\Windows\System32\config\SYSTEM | Out-Null

# Apply registry tweaks (similar to tiny11maker)
if ($EnableDebloat -eq 'yes' -and (Get-Module -Name tiny11-debloater)) {
    Write-Host "Applying registry tweaks..." -ForegroundColor Cyan
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

# Bypass system requirements
Write-Host "Bypassing system requirements..." -ForegroundColor Cyan
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

# Disable Bing Search in Start Bar
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Search' '/v' 'BingSearchEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

# Disable Auto Discovery
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell' '/v' 'FolderType' '/t' 'REG_SZ' '/d' 'NotSpecified' '/f' | Out-Null

# Disable Windows Spotlight and Lock Screen tips
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338387Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'RotatingLockScreenEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'RotatingLockScreenOverlayEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

# Enable Local Accounts on OOBE
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' '/v' 'OOBELocalAccount' '/t' 'REG_SZ' '/d' 'start ms-cxh:localonly' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'BypassNRO' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null

# Disable Reserved Storage
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' '/v' 'ShippedWithReserves' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

# Remove Defender if requested
if ($RemoveDefender -eq 'yes') {
    Write-Host "Removing Windows Defender..." -ForegroundColor Cyan
    try {
        $defenderPackages = & dism /English /image:"$scratchDir" /Get-Packages | 
            Select-String -Pattern "Windows-Defender-Client-Package"
        
        foreach ($package in $defenderPackages) {
            if ($package -match 'Package Identity :\s+(.+)') {
                $packageIdentity = $Matches[1].Trim()
                Write-Host "  Removing Defender package: $packageIdentity" -ForegroundColor Gray
                $result = & dism /English /image:"$scratchDir" /Remove-Package /PackageName:$packageIdentity 2>&1
                if ($LASTEXITCODE -ne 0 -or ($result | Select-String -Pattern "Removal failed|Error|failed" -Quiet)) {
                    Write-Warning "  Failed to remove Defender package $packageIdentity (continuing...)"
                }
            }
        }
        
        # Disable Defender services
        $servicePaths = @("WinDefend", "WdNisSvc", "WdNisDrv", "WdFilter", "Sense")
        foreach ($service in $servicePaths) {
            & 'reg' 'add' "HKLM\zSYSTEM\ControlSet001\Services\$service" '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f' | Out-Null
        }
        
        & 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' '/v' 'SettingsPageVisibility' '/t' 'REG_SZ' '/d' 'hide:virus;windowsupdate' '/f' | Out-Null
        Write-Host "Windows Defender removed successfully" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to remove Defender: $_"
    }
} else {
    Write-Host "Keeping Windows Defender (RemoveDefender=no)" -ForegroundColor Green
}

# Unload registry
Write-Host "Unmounting registry..." -ForegroundColor Gray
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

# Inject IRST driver into install.wim if provided or if IRST_Driver folder exists
if ($IrstDriverPath -or (Test-Path (Join-Path $scriptRoot "IRST_Driver"))) {
    Add-DriverToImage -MountPath $scratchDir -DriverPath $IrstDriverPath -ImageName "install.wim"
}

# Add Store packages if AddStore = yes
if ($AddStore -eq 'yes' -and $StorePackagesDir -and (Test-Path $StorePackagesDir)) {
    Write-Host "=== Adding Microsoft Store Packages ===" -ForegroundColor Cyan
    $storePackages = Get-ChildItem -Path $StorePackagesDir -Filter "*.Appx*" -Recurse

    if ($storePackages.Count -eq 0) {
        Write-Warning "No Store packages found in $StorePackagesDir"
        Write-Warning "Skipping Store installation..."
    } else {
    Write-Host "Found $($storePackages.Count) Store package file(s)" -ForegroundColor Green
    
    # Install dependencies first, then Store
    # Order theo script batch: NET.Native.Framework -> NET.Native.Runtime -> UI.Xaml -> VCLibs -> WindowsStore -> DesktopAppInstaller -> StorePurchaseApp -> XboxIdentityProvider
    # Mỗi package cài x64 trước, sau đó x86 (nếu có)
    $dependencyOrder = @(
        @{ Pattern = 'Microsoft.NET.Native.Framework'; Name = 'NET Native Framework'; ArchOrder = @('x64', 'x86') },
        @{ Pattern = 'Microsoft.NET.Native.Runtime'; Name = 'NET Native Runtime'; ArchOrder = @('x64', 'x86') },
        @{ Pattern = 'Microsoft.UI.Xaml'; Name = 'UI Xaml'; ArchOrder = @('x64', 'x86') },
        @{ Pattern = 'Microsoft.VCLibs.140.00'; Name = 'VCLibs'; ArchOrder = @('x64', 'x86') },
        @{ Pattern = 'Microsoft.WindowsStore'; Name = 'WindowsStore'; ArchOrder = @('neutral', 'x64', 'x86') },
        @{ Pattern = 'Microsoft.DesktopAppInstaller'; Name = 'DesktopAppInstaller'; ArchOrder = @('neutral', 'x64', 'x86') },
        @{ Pattern = 'Microsoft.StorePurchaseApp'; Name = 'StorePurchaseApp'; ArchOrder = @('neutral', 'x64', 'x86') },
        @{ Pattern = 'Microsoft.XboxIdentityProvider'; Name = 'XboxIdentityProvider'; ArchOrder = @('neutral', 'x64', 'x86') }
    )
    
    $installedPackages = @()
    $failedPackages = @()
    
    # Helper function to detect architecture from filename
    function Get-PackageArchitecture {
        param([string]$FileName)
        if ($FileName -like '*_neutral_*') { return 'neutral' }
        if ($FileName -like '*_x64_*' -or $FileName -like '*x64*') { return 'x64' }
        if ($FileName -like '*_x86_*' -or $FileName -like '*x86*') { return 'x86' }
        if ($FileName -like '*_arm64_*' -or $FileName -like '*arm64*') { return 'arm64' }
        return 'unknown'
    }
    
    foreach ($dep in $dependencyOrder) {
        $packageFiles = $storePackages | Where-Object { $_.Name -like "$($dep.Pattern)*" }
        
        if ($packageFiles.Count -eq 0) {
            Write-Host "No packages found for: $($dep.Name)" -ForegroundColor Gray
            continue
        }
        
        Write-Host "Installing: $($dep.Name)" -ForegroundColor Cyan
        
        # Sort packages by architecture order (x64 first, then x86, then neutral)
        $sortedPackages = $packageFiles | ForEach-Object {
            $arch = Get-PackageArchitecture -FileName $_.Name
            $order = $dep.ArchOrder.IndexOf($arch)
            if ($order -eq -1) { $order = 999 }  # Unknown arch goes last
            return @{
                File = $_
                Arch = $arch
                Order = $order
            }
        } | Sort-Object Order | ForEach-Object { $_.File }
        
        foreach ($packageFile in $sortedPackages) {
            $arch = Get-PackageArchitecture -FileName $packageFile.Name
            Write-Host "  Installing: $($packageFile.Name) ($arch)" -ForegroundColor Gray
            try {
                $result = Add-ProvisionedAppxPackage -Path $scratchDir -PackagePath $packageFile.FullName -SkipLicense -ErrorAction Stop
                if ($result) {
                    Write-Host "    ✓ Success" -ForegroundColor Green
                    $installedPackages += $packageFile.Name
                } else {
                    Write-Warning "    ⚠ No output from Add-ProvisionedAppxPackage"
                    $failedPackages += $packageFile.Name
                }
            } catch {
                Write-Warning "    ✗ Failed: $_"
                $failedPackages += $packageFile.Name
            }
        }
    }
    
        Write-Host "=== Store Installation Summary ===" -ForegroundColor Cyan
        Write-Host "Successfully installed: $($installedPackages.Count) package(s)" -ForegroundColor Green
        if ($failedPackages.Count -gt 0) {
            Write-Host "Failed: $($failedPackages.Count) package(s)" -ForegroundColor Yellow
            foreach ($failed in $failedPackages) {
                Write-Host "  - $failed" -ForegroundColor Yellow
            }
        }
    }
} else {
    if ($AddStore -eq 'yes') {
        Write-Warning "AddStore=yes but Store packages directory not provided or not found. Skipping Store installation."
    } else {
        Write-Host "AddStore=no, skipping Store installation" -ForegroundColor Gray
    }
}

# Cleanup image
Write-Host "Cleaning up image..." -ForegroundColor Cyan
& 'dism' '/English' "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' 2>&1 | Out-Null

# Commit and unmount (same as tiny11maker.ps1)
Write-Host "Unmounting image..." -ForegroundColor Cyan
Dismount-WindowsImage -Path $scratchDir -Save

# Create ISO (same as tiny11maker.ps1)
Write-Host "The LTSC image is now completed. Proceeding with the making of the ISO..." -ForegroundColor Cyan
Write-Host "Creating ISO image..." -ForegroundColor Cyan

# Determine script root directory (works in both local and GitHub Actions)
$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    # Fallback for GitHub Actions or when script is dot-sourced
    $scriptRoot = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { $PWD.Path }
}

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
$localOSCDIMGPath = Join-Path $scriptRoot "oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Host "Will be using oscdimg.exe from system ADK." -ForegroundColor Green
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Host "ADK folder not found. Will be using bundled oscdimg.exe." -ForegroundColor Yellow
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Host "Downloading oscdimg.exe..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath -ErrorAction Stop
            if (Test-Path $localOSCDIMGPath) {
                Write-Host "oscdimg.exe downloaded successfully." -ForegroundColor Green
            } else {
                Write-Error "Failed to download oscdimg.exe."
                exit 1
            }
        } catch {
            Write-Error "Failed to download oscdimg.exe: $_"
            exit 1
        }
    } else {
        Write-Host "oscdimg.exe already exists locally." -ForegroundColor Green
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
    'ltsc-store.iso'
}

Write-Host "Running oscdimg to create ISO..." -ForegroundColor Cyan
$isoPath = Join-Path $scriptRoot $isoFileName
Write-Host "ISO will be saved as: $isoFileName" -ForegroundColor Cyan
Write-Host "ISO path: $isoPath" -ForegroundColor Gray

try {
    $bootData = "2#p0,e,b$mainOSDrive\ltsc\boot\etfsboot.com#pEF,e,b$mainOSDrive\ltsc\efi\microsoft\boot\efisys.bin"
    & $OSCDIMG '-m' '-o' '-u2' '-udfver102' "-bootdata:$bootData" "$mainOSDrive\ltsc" $isoPath 2>&1 | Out-Null
    
    # Verify ISO was created
    Start-Sleep -Seconds 2
    if (-not (Test-Path $isoPath)) {
        Write-Error "ISO was not created at expected path: $isoPath"
        exit 1
    }
    
    $isoSize = (Get-Item $isoPath).Length / 1GB
    Write-Host "✓ ISO created successfully: $isoPath" -ForegroundColor Green
    Write-Host "  ISO size: $([math]::Round($isoSize, 2)) GB" -ForegroundColor Green
    
    # Output ISO path for workflow (use Write-Output for parsing)
    Write-Output "ISO_PATH=$isoPath"
    Write-Output "ISO_NAME=$isoFileName"
} catch {
    Write-Error "Failed to create ISO: $($_.Exception.Message)"
    exit 1
}

# Cleanup
Write-Host "Cleaning up temporary files..." -ForegroundColor Gray
Remove-Item -Path "$mainOSDrive\ltsc" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $scratchDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "=== Build Completed Successfully ===" -ForegroundColor Green

