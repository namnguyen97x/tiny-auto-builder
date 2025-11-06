# Windows LTSC ISO Builder with Microsoft Store
# Supports: Enterprise LTSC, IoT Enterprise LTSC, IoT Enterprise Subscription LTSC
# Includes debloat features (similar to tiny11maker) but keeps AI and optionally adds Store

param(
    [Parameter(Mandatory=$true)]
    [string]$DriveLetter,
    
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
    
    # IRST driver path (optional, path to folder containing IRST driver .inf files)
    # If not provided, will use IRST_Driver folder in project root
    [string]$IrstDriverPath = '',
    
    # Add Thorium browser to replace Edge (yes = add Thorium if Edge is removed, no = don't add)
    [ValidateSet('yes','no')]
    [string]$AddThorium = 'yes'
)

$ErrorActionPreference = 'Continue'

# Debloat settings - tự động enable theo chính sách của maker
# RemoveAI được set từ parameter (default='no' vì LTSC thường không có AI chính thức)
$EnableDebloat = 'yes'
$RemoveAppx = 'yes'
$RemoveCapabilities = 'yes'
$RemoveWindowsPackages = 'yes'
$RemoveOneDrive = 'yes'
$DisableTelemetry = 'yes'
$DisableSponsoredApps = 'yes'
$DisableAds = 'yes'
# $RemoveAI được set từ parameter (không hardcode nữa)
# Store feature removed: always remove Store components
$RemoveStore = 'yes'

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
Write-Host "Target Edition: $Edition"
Write-Host "ISO Name: $IsoName"
Write-Host "Debloat options: Defender=$RemoveDefender, AI=$RemoveAI, Edge=$RemoveEdge, Store=$RemoveStore, AddStore=$AddStore" -ForegroundColor Cyan
Write-Host "Browser options: AddThorium=$AddThorium" -ForegroundColor Cyan

# Validate inputs
if (-not (Test-Path "$DriveLetter\sources\install.wim") -and -not (Test-Path "$DriveLetter\sources\install.esd")) {
    Write-Error "Windows installation files not found in $DriveLetter"
    exit 1
}

# Store feature removed: no StorePackagesDir validation

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
& icacls $wimFilePath "/grant" "$( $adminGroup.Value):(F)" 2>&1 | Out-Null

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

# Store original WIM size for comparison
$originalWimPath = "$mainOSDrive\ltsc\sources\install.wim"
if (Test-Path $originalWimPath) {
    $originalSize = (Get-Item $originalWimPath).Length / 1GB
    Write-Host "=== Original WIM Size: $([math]::Round($originalSize, 2)) GB ===" -ForegroundColor Yellow
}

# Perform debloat (similar to tiny11maker)
Write-Host "=== Starting Debloat Process ===" -ForegroundColor Cyan

# Count packages before debloat
$packagesBefore = (Get-ProvisionedAppxPackage -Path $scratchDir -ErrorAction SilentlyContinue).Count
Write-Host "AppX packages before debloat: $packagesBefore" -ForegroundColor Gray

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
    
    # Count packages after debloat
    $packagesAfter = (Get-ProvisionedAppxPackage -Path $scratchDir -ErrorAction SilentlyContinue).Count
    $packagesRemoved = $packagesBefore - $packagesAfter
    Write-Host "AppX packages after debloat: $packagesAfter" -ForegroundColor Gray
    Write-Host "AppX packages removed: $packagesRemoved" -ForegroundColor Green
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

# Ensure Microsoft Store is allowed and required services are enabled (avoid Store not opening)
Write-Host "Ensuring Store policies and services are enabled..." -ForegroundColor Cyan
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\WindowsStore' '/v' 'RemoveWindowsStore' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\ClipSVC' '/v' 'Start' '/t' 'REG_DWORD' '/d' '3' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\AppXSvc' '/v' 'Start' '/t' 'REG_DWORD' '/d' '3' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\AppXSvc' '/v' 'DelayedAutoStart' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' '/v' 'NoUseStoreOpenWith' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null

# First-boot fix: re-register Store/App Installer and reset cache
try {
    $setupScriptsDir = "$scratchDir\Windows\Setup\Scripts"
    if (-not (Test-Path $setupScriptsDir)) { New-Item -ItemType Directory -Path $setupScriptsDir -Force | Out-Null }
    $firstBootCmd = Join-Path $setupScriptsDir 'FirstBoot-StoreFix.cmd'
    $cmdContent = @"
@echo off
REM Ensure services
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Try { Set-Service -Name ClipSVC -StartupType Manual; Start-Service ClipSVC; Set-Service -Name AppXSVC -StartupType Manual; Start-Service AppXSVC } Catch {}"
REM Re-register Store and App Installer for all users
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$pkgs = 'Microsoft.WindowsStore','Microsoft.DesktopAppInstaller','Microsoft.StorePurchaseApp','Microsoft.XboxIdentityProvider'; foreach($n in $pkgs){ try { $p = Get-AppxPackage -AllUsers $n -ErrorAction SilentlyContinue; if($p -and (Test-Path \"$($p.InstallLocation)\\AppxManifest.xml\")){ Add-AppxPackage -DisableDevelopmentMode -Register \"$($p.InstallLocation)\\AppxManifest.xml\" -ErrorAction SilentlyContinue } } catch {} }"
REM Reset Store cache (ignore errors on LTSC)
wsreset.exe 2>nul
exit /b 0
"@
    Set-Content -LiteralPath $firstBootCmd -Value $cmdContent -Encoding ASCII -Force
    & 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce' '/v' 'FirstBootStoreFix' '/t' 'REG_SZ' '/d' 'C:\\Windows\\Setup\\Scripts\\FirstBoot-StoreFix.cmd' '/f' | Out-Null
    Write-Host "Scheduled first-boot Store re-registration via RunOnce" -ForegroundColor Green
} catch { Write-Warning "Failed to stage first-boot Store fix: $_" }

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

# Copy autounattend.xml to Sysprep directory (same as tiny11maker.ps1)
$autounattendPath = Join-Path $scriptRoot "autounattend.xml"
if (-not (Test-Path $autounattendPath)) {
    Write-Host "Downloading autounattend.xml..." -ForegroundColor Cyan
    try {
        Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile $autounattendPath -ErrorAction Stop
        Write-Host "autounattend.xml downloaded successfully" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to download autounattend.xml: $_"
    }
}

if (Test-Path $autounattendPath) {
    $sysprepDir = "$scratchDir\Windows\System32\Sysprep"
    if (-not (Test-Path $sysprepDir)) {
        New-Item -ItemType Directory -Path $sysprepDir -Force | Out-Null
    }
    Copy-Item -Path $autounattendPath -Destination "$sysprepDir\autounattend.xml" -Force | Out-Null
    Write-Host "autounattend.xml copied to Sysprep directory" -ForegroundColor Green
}

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

# Store feature removed: no Store installation logic

# Add Thorium browser (independent of Edge removal)
if ($AddThorium -eq 'yes') {
    Write-Host "=== Adding Thorium Browser ===" -ForegroundColor Cyan
    Write-Host "Note: Adding Thorium will increase image size (~150-200MB)" -ForegroundColor Yellow
    
    # Function to download and inject Thorium
    function Add-ThoriumBrowser {
        param(
            [string]$MountPath,
            [string]$ScriptRoot
        )
        
        $tempDir = "$env:TEMP\ThoriumDownload"
        $thoriumDir = "$MountPath\Program Files\Thorium"
        
        try {
            # Create temp directory
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            
            Write-Host "Downloading Thorium browser from GitHub..." -ForegroundColor Cyan
            
            # Get latest Thorium release from GitHub
            $apiUrl = "https://api.github.com/repos/Alex313031/Thorium-Win/releases/latest"
            try {
                $release = Invoke-RestMethod -Uri $apiUrl -ErrorAction Stop
                $asset = $release.assets | Where-Object { 
                    $_.name -like '*Windows*' -and (
                        $_.name -like '*x64*.zip' -or 
                        $_.name -like '*x64*.7z' -or
                        $_.name -like '*win64*.zip' -or
                        $_.name -like '*win64*.7z'
                    )
                } | Select-Object -First 1
                
                if (-not $asset) {
                    # Fallback: try to find any zip/7z file
                    $asset = $release.assets | Where-Object { 
                        $_.name -like '*.zip' -or $_.name -like '*.7z'
                    } | Select-Object -First 1
                }
                
                if ($asset) {
                    Write-Host "Found release: $($release.tag_name)" -ForegroundColor Green
                    Write-Host "Downloading: $($asset.name)..." -ForegroundColor Gray
                    
                    $downloadPath = Join-Path $tempDir $asset.name
                    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing
                    
                    Write-Host "Extracting Thorium..." -ForegroundColor Cyan
                    
                    # Extract based on file type
                    if ($asset.name -like '*.zip') {
                        Expand-Archive -Path $downloadPath -DestinationPath $tempDir -Force
                    } elseif ($asset.name -like '*.7z') {
                        # Try 7-Zip if available (check multiple possible locations)
                        $7zipPaths = @(
                            "C:\\Program Files\\7-Zip\\7z.exe",
                            "C:\\Program Files (x86)\\7-Zip\\7z.exe",
                            "$env:ProgramFiles\\7-Zip\\7z.exe"
                        )
                        $7zipPath = $null
                        foreach ($path in $7zipPaths) {
                            if (Test-Path $path) {
                                $7zipPath = $path
                                break
                            }
                        }
                        
                        if ($7zipPath) {
                            Write-Host "Using 7-Zip at: $7zipPath" -ForegroundColor Gray
                            & $7zipPath x "$downloadPath" "-o$tempDir" -y | Out-Null
                            if ($LASTEXITCODE -ne 0) {
                                Write-Warning "7-Zip extraction failed (exit code: $LASTEXITCODE)"
                                return $false
                            }
                        } else {
                            Write-Warning "7-Zip not found. Cannot extract .7z file."
                            Write-Warning "Please ensure 7-Zip is installed or use a .zip release"
                            return $false
                        }
                    } else {
                        Write-Warning "Unsupported archive format: $($asset.name)"
                        return $false
                    }
                    
                    # Find extracted Thorium folder
                    $extractedDirs = Get-ChildItem -Path $tempDir -Directory | Where-Object {
                        $_.Name -like '*Thorium*' -or $_.Name -like '*thorium*'
                    }
                    
                    if ($extractedDirs.Count -eq 0) {
                        # Might be extracted directly to tempDir
                        $thoriumExe = Get-ChildItem -Path $tempDir -Filter "thorium.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
                        if ($thoriumExe) {
                            $extractedPath = $thoriumExe.Directory.FullName
                        } else {
                            Write-Warning "Could not find Thorium executable in extracted files"
                            return $false
                        }
                    } else {
                        $extractedPath = $extractedDirs[0].FullName
                    }
                    
                    Write-Host "Copying Thorium to Program Files..." -ForegroundColor Cyan
                    
                    # Create Program Files\Thorium directory
                    if (Test-Path $thoriumDir) {
                        Remove-Item -Path $thoriumDir -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    New-Item -ItemType Directory -Path $thoriumDir -Force | Out-Null
                    
                    # Copy all files
                    Copy-Item -Path "$extractedPath\*" -Destination $thoriumDir -Recurse -Force
                    
                    # Verify thorium.exe exists
                    if (-not (Test-Path "$thoriumDir\thorium.exe")) {
                        Write-Warning "thorium.exe not found after copy"
                        return $false
                    }
                    
                    Write-Host "Creating Start Menu shortcuts..." -ForegroundColor Cyan
                    
                    # Create Start Menu shortcuts
                    $startMenuPath = "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs"
                    $startMenuPrograms = "$startMenuPath\Thorium"
                    if (-not (Test-Path $startMenuPrograms)) {
                        New-Item -ItemType Directory -Path $startMenuPrograms -Force | Out-Null
                    }
                    
                    # Create shortcut using WScript (works in offline image)
                    $shortcutPath = "$startMenuPrograms\Thorium Browser.lnk"
                    $wshShell = New-Object -ComObject WScript.Shell
                    $shortcut = $wshShell.CreateShortcut($shortcutPath)
                    $shortcut.TargetPath = "C:\\Program Files\\Thorium\\thorium.exe"
                    $shortcut.WorkingDirectory = "C:\\Program Files\\Thorium"
                    $shortcut.Description = "Thorium Browser - Fast Chromium-based browser"
                    $shortcut.Save()
                    
                    # Also create in Default User Start Menu
                    $defaultUserStartMenu = "$MountPath\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
                    $defaultUserPrograms = "$defaultUserStartMenu\Thorium"
                    if (-not (Test-Path $defaultUserPrograms)) {
                        New-Item -ItemType Directory -Path $defaultUserPrograms -Force | Out-Null
                    }
                    $defaultShortcutPath = "$defaultUserPrograms\Thorium Browser.lnk"
                    $shortcut2 = $wshShell.CreateShortcut($defaultShortcutPath)
                    $shortcut2.TargetPath = "C:\\Program Files\\Thorium\\thorium.exe"
                    $shortcut2.WorkingDirectory = "C:\\Program Files\\Thorium"
                    $shortcut2.Description = "Thorium Browser - Fast Chromium-based browser"
                    $shortcut2.Save()
                    
                    Write-Host "✓ Thorium browser installed successfully" -ForegroundColor Green
                    Write-Host "  Location: C:\\Program Files\\Thorium" -ForegroundColor Gray
                    return $true
                } else {
                    Write-Warning "No suitable download found in latest release"
                    return $false
                }
            } catch {
                Write-Warning "Failed to download Thorium from GitHub: $_"
                return $false
            }
        } catch {
            Write-Warning "Error installing Thorium: $_"
            return $false
        } finally {
            # Cleanup temp directory
            if (Test-Path $tempDir) {
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    # Load registry for Thorium installation
    Write-Host "Loading registry for Thorium installation..." -ForegroundColor Gray
    reg load HKLM\zSOFTWARE $scratchDir\Windows\System32\config\SOFTWARE | Out-Null
    
    # Install Thorium
    $thoriumInstalled = Add-ThoriumBrowser -MountPath $scratchDir -ScriptRoot $scriptRoot
    
    # Set Thorium as default browser (optional, via registry)
    if ($thoriumInstalled) {
        Write-Host "Configuring Thorium as default browser..." -ForegroundColor Cyan
        try {
            # Set HTTP/HTTPS handlers to Thorium
            $thoriumPath = "C:\\Program Files\\Thorium\\thorium.exe"
            & 'reg' 'add' 'HKLM\zSOFTWARE\Classes\http\shell\open\command' '/ve' '/t' 'REG_SZ' "/d`"$thoriumPath`" `"%1`"" '/f' | Out-Null
            & 'reg' 'add' 'HKLM\zSOFTWARE\Classes\https\shell\open\command' '/ve' '/t' 'REG_SZ' "/d`"$thoriumPath`" `"%1`"" '/f' | Out-Null
            Write-Host "  ✓ Thorium configured as default browser" -ForegroundColor Green
        } catch {
            Write-Warning "  ⚠ Failed to set Thorium as default browser: $_"
        }
    } else {
        Write-Warning "Thorium installation failed, skipping default browser configuration"
    }
    
    # Unload registry
    reg unload HKLM\zSOFTWARE | Out-Null
    
    Write-Host "=== Thorium Installation Complete ===" -ForegroundColor Cyan
}

# Cleanup image
Write-Host "Cleaning up image..." -ForegroundColor Cyan
& 'dism' '/English' "/image:$scratchDir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' 2>&1 | Out-Null
Write-Host "Cleanup complete." -ForegroundColor Green

# Commit and unmount (same as tiny11maker.ps1)
Write-Host "Unmounting image..." -ForegroundColor Cyan
Dismount-WindowsImage -Path $scratchDir -Save

# Export image with compression to reduce size (same as tiny11maker.ps1)
Write-Host "Exporting image with compression to reduce size..." -ForegroundColor Cyan
$wimFilePath = "$mainOSDrive\ltsc\sources\install.wim"
$tempWimFile = "$mainOSDrive\ltsc\sources\install2.wim"

Write-Host "Exporting from index $index to compressed WIM..." -ForegroundColor Gray
& Dism.exe /Export-Image /SourceImageFile:"$wimFilePath" /SourceIndex:$index /DestinationImageFile:"$tempWimFile" /Compress:recovery 2>&1 | Out-Null

if (Test-Path $tempWimFile) {
    Write-Host "Removing old WIM file..." -ForegroundColor Gray
    $oldSize = if (Test-Path $wimFilePath) { (Get-Item $wimFilePath).Length / 1GB } else { 0 }
    Remove-Item -Path $wimFilePath -Force -ErrorAction SilentlyContinue
    Write-Host "Renaming compressed WIM file..." -ForegroundColor Gray
    Rename-Item -Path $tempWimFile -NewName "install.wim" -Force | Out-Null
    Write-Host "✓ Image exported and compressed successfully" -ForegroundColor Green
    
    # Show size comparison
    $newSize = (Get-Item $wimFilePath).Length / 1GB
    $sizeReduction = $oldSize - $newSize
    $sizeReductionPercent = if ($oldSize -gt 0) { [math]::Round(($sizeReduction / $oldSize) * 100, 2) } else { 0 }
    Write-Host "  Original WIM size: $([math]::Round($oldSize, 2)) GB" -ForegroundColor Gray
    Write-Host "  Compressed WIM size: $([math]::Round($newSize, 2)) GB" -ForegroundColor Green
    Write-Host "  Size reduction: $([math]::Round($sizeReduction, 2)) GB ($sizeReductionPercent%)" -ForegroundColor $(if ($sizeReduction -gt 0) { "Green" } else { "Yellow" })
} else {
    Write-Warning "Failed to export compressed image, using original WIM file"
}

Write-Host "Windows image completed. Continuing with boot.wim..." -ForegroundColor Cyan

# Mount boot.wim to modify Windows Setup (same as tiny11maker.ps1)
Write-Host "Mounting boot image (keeping both WinPE classic menu and Windows Setup)..." -ForegroundColor Cyan
$bootWimPath = "$mainOSDrive\ltsc\sources\boot.wim"

# Set permissions for boot.wim file
Write-Host "Setting permissions for boot.wim file..." -ForegroundColor Gray
& takeown "/F" $bootWimPath 2>&1 | Out-Null
& icacls $bootWimPath "/grant" "$( $adminGroup.Value):(F)" 2>&1 | Out-Null

try {
    Set-ItemProperty -Path $bootWimPath -Name IsReadOnly -Value $false -ErrorAction Stop
    Write-Host "boot.wim file permissions set successfully" -ForegroundColor Green
} catch {
    Write-Warning "boot.wim file IsReadOnly property may not be settable (continuing...)"
}

# Mount Windows Setup image (index 2) to modify registry (index 1 - WinPE classic menu will be preserved)
Write-Host "Mounting Windows Setup image (index 2) to modify registry..." -ForegroundColor Gray
Mount-WindowsImage -ImagePath $bootWimPath -Index 2 -Path $scratchDir

Write-Host "Loading registry for boot.wim..." -ForegroundColor Gray
reg load HKLM\zCOMPONENTS $scratchDir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $scratchDir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $scratchDir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $scratchDir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $scratchDir\Windows\System32\config\SYSTEM | Out-Null

# Bypass system requirements on the setup image (same as tiny11maker.ps1)
Write-Host "Bypassing system requirements on the setup image..." -ForegroundColor Cyan
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Write-Host "✓ System requirements bypass applied to Windows Setup" -ForegroundColor Green

# Unload registry
Write-Host "Unmounting registry..." -ForegroundColor Gray
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

# Inject IRST driver into boot.wim (Windows Setup) if provided
if ($IrstDriverPath -or (Test-Path (Join-Path $scriptRoot "IRST_Driver"))) {
    Add-DriverToImage -MountPath $scratchDir -DriverPath $IrstDriverPath -ImageName "boot.wim (Windows Setup)"
}

# Unmount boot.wim (keeping both indexes intact)
Write-Host "Unmounting boot.wim image..." -ForegroundColor Cyan
Dismount-WindowsImage -Path $scratchDir -Save
Write-Host "✓ boot.wim modifications completed" -ForegroundColor Green

# Create ISO (same as tiny11maker.ps1)
Write-Host "The LTSC image is now completed. Proceeding with the making of the ISO..." -ForegroundColor Cyan

# Copy autounattend.xml to ISO root for bypassing MS account on OOBE (same as tiny11maker.ps1)
$autounattendPath = Join-Path $scriptRoot "autounattend.xml"
if (Test-Path $autounattendPath) {
    Write-Host "Copying autounattend.xml to ISO root for bypassing MS account on OOBE..." -ForegroundColor Cyan
    Copy-Item -Path $autounattendPath -Destination "$mainOSDrive\ltsc\autounattend.xml" -Force | Out-Null
    Write-Host "autounattend.xml copied to ISO root" -ForegroundColor Green
} else {
    Write-Warning "autounattend.xml not found, OOBE bypass may not work"
}

Write-Host "Creating ISO image..." -ForegroundColor Cyan

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
$ADKDepTools = "C:\\Program Files (x86)\\Windows Kits\\10\\Assessment and Deployment Kit\\Deployment Tools\\$hostArchitecture\\Oscdimg"
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
