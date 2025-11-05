<#
.SYNOPSIS
    Module tích hợp các tính năng debloat từ Windows-ISO-Debloater vào tiny11builder

.DESCRIPTION
    Module này chứa các functions để remove packages, capabilities, và apply registry tweaks
    từ Windows-ISO-Debloater để tích hợp vào tiny11maker và tiny11Coremaker
#>

# Danh sách AppX packages để remove (áp dụng cho cả Windows 10 và Windows 11)
$script:appxPatternsToRemove = @(
    "Microsoft.Microsoft3DViewer*",
    "Microsoft.WindowsAlarms*",
    "Microsoft.BingNews*",
    "Microsoft.BingWeather*",
    "Microsoft.BingSports*",
    "Microsoft.BingFinance*",
    "Clipchamp.Clipchamp*",
    "Microsoft.549981C3F5F10*",
    "Microsoft.Windows.DevHome*",
    "MicrosoftCorporationII.MicrosoftFamily*",
    "Microsoft.WindowsFeedbackHub*",
    "Microsoft.GetHelp*",
    "Microsoft.Getstarted*",
    "Microsoft.WindowsCommunicationsapps*",
    "Microsoft.WindowsMaps*",
    "Microsoft.MixedReality.Portal*",
    "Microsoft.ZuneMusic*",
    "Microsoft.MicrosoftOfficeHub*",
    "Microsoft.Office.OneNote*",
    "Microsoft.OutlookForWindows*",
    "Microsoft.MSPaint*",
    "Microsoft.People*",
    "Microsoft.YourPhone*",
    "Microsoft.PowerAutomateDesktop*",
    "MicrosoftCorporationII.QuickAssist*",
    "Microsoft.SkypeApp*",
    "Microsoft.MicrosoftSolitaireCollection*",
    "MicrosoftTeams*",
    "MSTeams*",
    "Microsoft.Windows.Teams*",
    "Microsoft.Todos*",
    "Microsoft.ZuneVideo*",
    "Microsoft.Wallet*",
    "Microsoft.GamingApp*",
    "Microsoft.XboxApp*",
    "Microsoft.XboxGameOverlay*",
    "Microsoft.XboxGamingOverlay*",
    "Microsoft.XboxSpeechToTextOverlay*",
    "Microsoft.Xbox.TCUI*",
    "Microsoft.XboxIdentityProvider*",
    "Microsoft.XboxGameSpeechWindow*",
    "Microsoft.Windows.XboxGameCallableUI*",
    "MicrosoftWindows.CrossDevice*",
    "Microsoft.Windows.PeopleExperienceHost*",
    "Windows.CBSPreview*",
    "Microsoft.BingSearch*",
    "Microsoft.WindowsStore*",
    "Microsoft.WindowsCamera*",
    "Microsoft.WindowsSoundRecorder*",
    "Microsoft.Windows.Photos*",
    "Microsoft.ScreenSketch*",
    "Microsoft.DesktopAppInstaller*",
    "Microsoft.WindowsWebExperiencePack*",
    "Microsoft.MicrosoftEdgeUpdate*",
    "Microsoft.Services.Store.Engagement*",
    "Microsoft.StorePurchaseApp*",
    "Microsoft.WindowsStorePurchaseApp*",
    "Microsoft.BingTranslator*",
    "Microsoft.Windows.PrintQueue*",
    "Microsoft.Windows.InkWorkSpace*",
    "Microsoft.Windows.ParentalControls*",
    "Microsoft.Windows.ReadingList*",
    "Microsoft.Windows.SecureAssessmentBrowser*",
    "Microsoft.Windows.Search.Cortana*",
    "Microsoft.Windows.TouchKeyboard*",
    "Microsoft.Windows.WifiSense*",
    "Microsoft.Windows.AssignedAccessLockApp*",
    "Microsoft.Windows.ContentDeliveryManager*",
    "Microsoft.Windows.ContentDeliveryManagerDeliveryOptimization*",
    "Microsoft.Windows.ContentDeliveryManager.WindowsContentDeliveryManager*",
    "Microsoft.MicrosoftStickyNotes*",
    "Microsoft.WindowsCalculator*",
    "Microsoft.WindowsTerminal*",
    "Microsoft.WindowsNotepad*",
    "Microsoft.WindowsPaint*",
    "Microsoft.Windows.CloudExperienceHost*",
    "Microsoft.WindowsTips*",
    "Microsoft.OneDriveSync*",
    "Microsoft.OneDrive*"
)

# Danh sách Capabilities để remove
function Get-CapabilitiesToRemove {
    param([string]$LanguageCode)
    return @(
        "Browser.InternetExplorer*",
        "Internet-Explorer*",
        "App.StepsRecorder*",
        "Language.Handwriting~~~$LanguageCode*",
        "Language.OCR~~~$LanguageCode*",
        "Language.Speech~~~$LanguageCode*",
        "Language.TextToSpeech~~~$LanguageCode*",
        "Microsoft.Windows.WordPad*",
        "MathRecognizer*",
        "Media.WindowsMediaPlayer*"
    )
}

# Danh sách Windows Packages để remove
function Get-WindowsPackagesToRemove {
    param([string]$LanguageCode)
    return @(
        "Microsoft-Windows-InternetExplorer-Optional-Package*",
        "Microsoft-Windows-LanguageFeatures-Handwriting-$LanguageCode-Package*",
        "Microsoft-Windows-LanguageFeatures-OCR-$LanguageCode-Package*",
        "Microsoft-Windows-LanguageFeatures-Speech-$LanguageCode-Package*",
        "Microsoft-Windows-LanguageFeatures-TextToSpeech-$LanguageCode-Package*",
        "Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package*",
        "Microsoft-Windows-WordPad-FoD-Package*",
        "Microsoft-Windows-MediaPlayer-Package*",
        "Microsoft-Windows-TabletPCMath-Package*",
        "Microsoft-Windows-StepsRecorder-Package*"
    )
}

<#
.SYNOPSIS
    Remove packages từ mounted image
#>
function Remove-DebloatPackages {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MountPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveAppx = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveCapabilities = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveWindowsPackages = $true,
        
        [Parameter(Mandatory=$false)]
        [string]$LanguageCode = "en-US",
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveStore = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveAI = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveDefender = $true
    )
    
    Write-Output "Removing debloat packages..."
    
    # Remove AppX Packages
    if ($RemoveAppx) {
        Write-Output "Removing AppX packages..."
        $packages = Get-ProvisionedAppxPackage -Path $MountPath -ErrorAction SilentlyContinue
        $removedCount = 0
        
        # Filter patterns based on RemoveStore and RemoveAI settings
        $patternsToUse = $script:appxPatternsToRemove | Where-Object {
            $pattern = $_
            $shouldInclude = $true
            
            # Exclude Store packages if RemoveStore = false
            if (-not $RemoveStore) {
                if ($pattern -like "*WindowsStore*" -or $pattern -like "*StorePurchaseApp*" -or $pattern -like "*Store.Engagement*") {
                    $shouldInclude = $false
                }
            }
            
            # Exclude AI packages if RemoveAI = false
            if (-not $RemoveAI) {
                if ($pattern -like "*Copilot*" -or $pattern -like "*549981C3F5F10*") {
                    $shouldInclude = $false
                }
            }
            
            return $shouldInclude
        }
        
        foreach ($pattern in $patternsToUse) {
            $matched = $packages | Where-Object { $_.PackageName -like $pattern }
            foreach ($pkg in $matched) {
                try {
                    Remove-ProvisionedAppxPackage -Path $MountPath -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                    Write-Output "  Removed: $($pkg.PackageName)"
                    $removedCount++
                } catch {
                    Write-Warning "  Failed to remove: $($pkg.PackageName) - $($_.Exception.Message)"
                }
            }
        }
        Write-Output "Removed $removedCount AppX packages"
    }
    
    # Remove Capabilities
    if ($RemoveCapabilities) {
        Write-Output "Removing Windows Capabilities..."
        $capabilities = Get-CapabilitiesToRemove -LanguageCode $LanguageCode
        $removedCount = 0
        
        foreach ($pattern in $capabilities) {
            try {
                $matched = Get-WindowsCapability -Path $MountPath -ErrorAction SilentlyContinue | Where-Object { $_.Name -like $pattern }
                foreach ($cap in $matched) {
                    try {
                        Remove-WindowsCapability -Path $MountPath -Name $cap.Name -ErrorAction Stop | Out-Null
                        Write-Output "  Removed capability: $($cap.Name)"
                        $removedCount++
                    } catch {
                        Write-Warning "  Failed to remove capability: $($cap.Name) - $($_.Exception.Message)"
                    }
                }
            } catch {
                Write-Warning "  Failed to remove capability: $pattern"
            }
        }
        Write-Output "Removed $removedCount capabilities"
    }
    
    # Remove Windows Packages
    if ($RemoveWindowsPackages) {
        Write-Output "Removing Windows Packages..."
        $packagePatterns = Get-WindowsPackagesToRemove -LanguageCode $LanguageCode
        
        # Filter Defender packages if RemoveDefender = false
        if (-not $RemoveDefender) {
            $packagePatterns = $packagePatterns | Where-Object { $_ -notlike "*Defender*" -and $_ -notlike "*Windows-Defender*" }
        }
        
        $removedCount = 0
        
        foreach ($pattern in $packagePatterns) {
            try {
                $matched = Get-WindowsPackage -Path $MountPath -ErrorAction SilentlyContinue | Where-Object { $_.PackageName -like $pattern }
                foreach ($pkg in $matched) {
                    # Double check for Defender if RemoveDefender = false
                    if (-not $RemoveDefender) {
                        if ($pkg.PackageName -like "*Defender*" -or $pkg.PackageName -like "*Windows-Defender*") {
                            continue
                        }
                    }
                    
                    try {
                        Remove-WindowsPackage -Path $MountPath -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null
                        Write-Output "  Removed package: $($pkg.PackageName)"
                        $removedCount++
                    } catch {
                        Write-Warning "  Failed to remove package: $($pkg.PackageName) - $($_.Exception.Message)"
                    }
                }
            } catch {
                Write-Warning "  Failed to remove package: $pattern"
            }
        }
        Write-Output "Removed $removedCount Windows packages"
    }
}

<#
.SYNOPSIS
    Apply registry tweaks từ Windows-ISO-Debloater
#>
function Apply-DebloatRegistryTweaks {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RegistryPrefix,  # "zSOFTWARE", "zNTUSER", "zSYSTEM", etc.
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableTelemetry = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableSponsoredApps = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableAds = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableBitlocker = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableOneDrive = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableGameDVR = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$TweakOOBE = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$DisableUselessJunks = $true
    )
    
    Write-Output "Applying registry tweaks..."
    
    # Helper function để set registry
    function Set-RegValue {
        param([string]$Key, [string]$Value, [string]$Type, [string]$Data)
        try {
            & reg add "$RegistryPrefix\$Key" /v $Value /t $Type /d $Data /f 2>&1 | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    
    function Remove-RegKey {
        param([string]$Key)
        try {
            & reg delete "$RegistryPrefix\$Key" /f 2>&1 | Out-Null
            return $true
        } catch {
            return $false
        }
    }
    
    # Disable Sponsored Apps
    if ($DisableSponsoredApps) {
        Write-Output "  Disabling Sponsored Apps..."
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "OemPreInstalledAppsEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" "REG_DWORD" "0"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Microsoft\PolicyManager\current\device\Start" "ConfigureStartPins" "REG_SZ" '{"pinnedList": [{}]}'
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContentEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "ContentDeliveryAllowed" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEverEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" "REG_DWORD" "0"
        Remove-RegKey "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions"
        Remove-RegKey "NTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps"
    }
    
    # Disable Telemetry
    if ($DisableTelemetry) {
        Write-Output "  Disabling Telemetry..."
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Personalization\Settings" "AcceptedPrivacyPolicy" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy" "HasAccepted" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\InputPersonalization" "RestrictImplicitInkCollection" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore" "HarvestContacts" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" "REG_DWORD" "0"
        Set-RegValue "SYSTEM\ControlSet001\Services\dmwappushservice" "Start" "REG_DWORD" "4"
    }
    
    # Disable Ads
    if ($DisableAds) {
        Write-Output "  Disabling Ads..."
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\CloudContent" "DisableCloudOptimizedContent" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\MRT" "DontOfferThroughWUAU" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Teams" "DisableInstallation" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\Windows Mail" "PreventRun" "REG_DWORD" "1"
    }
    
    # Disable Bitlocker
    if ($DisableBitlocker) {
        Write-Output "  Disabling Bitlocker..."
        Set-RegValue "SYSTEM\ControlSet001\Control\BitLocker" "PreventDeviceEncryption" "REG_DWORD" "1"
    }
    
    # Disable OneDrive
    if ($DisableOneDrive) {
        Write-Output "  Disabling OneDrive..."
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
        Remove-RegKey "NTUSER\Software\Microsoft\Windows\CurrentVersion\Run\OneDriveSetup"
    }
    
    # Disable GameDVR
    if ($DisableGameDVR) {
        Write-Output "  Disabling GameDVR..."
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" "REG_DWORD" "0"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\GameDVR" "AllowGameDVR" "REG_DWORD" "0"
        Set-RegValue "SYSTEM\ControlSet001\Services\BcastDVRUserService" "Start" "REG_DWORD" "4"
        Set-RegValue "SYSTEM\ControlSet001\Services\GameBarPresenceWriter" "Start" "REG_DWORD" "4"
    }
    
    # OOBE Tweaks
    if ($TweakOOBE) {
        Write-Output "  Tweaking OOBE..."
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" "BypassNRO" "REG_DWORD" "1"
    }
    
    # Disable useless junks
    if ($DisableUselessJunks) {
        Write-Output "  Disabling useless junks..."
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate" "workCompleted" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate" "workCompleted" "REG_DWORD" "1"
        Remove-RegKey "SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate"
        Remove-RegKey "SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon" "REG_DWORD" "3"
    }
}

<#
.SYNOPSIS
    Remove files và folders (Edge, OneDrive, etc.)
#>
function Remove-DebloatFiles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MountPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveEdge = $true,
        
        [Parameter(Mandatory=$false)]
        [switch]$RemoveOneDrive = $true,
        
        [Parameter(Mandatory=$false)]
        [string]$Architecture = "amd64"
    )
    
    Write-Output "Removing debloat files..."
    
    # Remove Edge
    if ($RemoveEdge) {
        Write-Output "  Removing Edge..."
        $edgePaths = @(
            "$MountPath\Program Files (x86)\Microsoft\Edge",
            "$MountPath\Program Files (x86)\Microsoft\EdgeUpdate",
            "$MountPath\Program Files (x86)\Microsoft\EdgeCore",
            "$MountPath\Windows\System32\Microsoft-Edge-Webview"
        )
        
        foreach ($path in $edgePaths) {
            if (Test-Path $path) {
                try {
                    Remove-Item -Path $path -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "    Removed: $path"
                } catch {
                    Write-Warning "    Failed to remove: $path"
                }
            }
        }
        
        # Remove Edge WebView from WinSxS
        if ($Architecture -eq "amd64") {
            $webviewPath = Get-ChildItem -Path "$MountPath\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        } elseif ($Architecture -eq "arm64") {
            $webviewPath = Get-ChildItem -Path "$MountPath\Windows\WinSxS" -Filter "arm64_microsoft-edge-webview_31bf3856ad364e35*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        }
        
        if ($webviewPath) {
            try {
                & takeown /f $webviewPath /r 2>&1 | Out-Null
                & icacls $webviewPath /grant "Administrators:(F)" /T /C 2>&1 | Out-Null
                Remove-Item -Path $webviewPath -Recurse -Force -ErrorAction SilentlyContinue
                Write-Output "    Removed Edge WebView from WinSxS"
            } catch {
                Write-Warning "    Failed to remove Edge WebView from WinSxS"
            }
        }
    }
    
    # Remove OneDrive
    if ($RemoveOneDrive) {
        Write-Output "  Removing OneDrive..."
        $oneDrivePath = "$MountPath\Windows\System32\OneDriveSetup.exe"
        if (Test-Path $oneDrivePath) {
            try {
                & takeown /f $oneDrivePath 2>&1 | Out-Null
                & icacls $oneDrivePath /grant "Administrators:(F)" /T /C 2>&1 | Out-Null
                Remove-Item -Path $oneDrivePath -Force -ErrorAction SilentlyContinue
                Write-Output "    Removed: $oneDrivePath"
            } catch {
                Write-Warning "    Failed to remove: $oneDrivePath"
            }
        }
        
        # Remove OneDrive shortcuts from Start Menu
        Write-Output "  Removing OneDrive Start Menu shortcuts..."
        $startMenuPaths = @(
            "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
            "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive",
            "$MountPath\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
            "$MountPath\Users\Default\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\OneDrive"
        )
        
        foreach ($shortcutPath in $startMenuPaths) {
            if (Test-Path $shortcutPath) {
                try {
                    & takeown /f $shortcutPath /r 2>&1 | Out-Null
                    & icacls $shortcutPath /grant "Administrators:(F)" /T /C 2>&1 | Out-Null
                    Remove-Item -Path $shortcutPath -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Output "    Removed shortcut: $shortcutPath"
                } catch {
                    Write-Warning "    Failed to remove shortcut: $shortcutPath"
                }
            }
        }
        
        # Remove OneDrive from Start Menu tiles/cache
        try {
            $tileCachePaths = @(
                "$MountPath\ProgramData\Microsoft\Windows\Start Menu\Programs\OneDrive.lnk",
                "$MountPath\Users\Default\AppData\Local\TileDataLayer\Database\*OneDrive*"
            )
            
            foreach ($cachePath in $tileCachePaths) {
                if (Test-Path $cachePath) {
                    & takeown /f $cachePath /r 2>&1 | Out-Null
                    & icacls $cachePath /grant "Administrators:(F)" /T /C 2>&1 | Out-Null
                    Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        } catch {
            Write-Warning "    Failed to remove OneDrive tile cache"
        }
    }
}

# Export các functions
Export-ModuleMember -Function Remove-DebloatPackages, Apply-DebloatRegistryTweaks, Remove-DebloatFiles, Get-CapabilitiesToRemove, Get-WindowsPackagesToRemove
