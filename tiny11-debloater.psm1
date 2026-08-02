<#
.SYNOPSIS
    Module tích hợp các tính năng debloat từ Windows-ISO-Debloater vào tiny11builder

.DESCRIPTION
    Module này chứa các functions để remove packages, capabilities, và apply registry tweaks
    từ Windows-ISO-Debloater để tích hợp vào tiny11maker và tiny11Coremaker
#>

# Danh sách AppX packages để remove (áp dụng cho Windows 10, Windows 11 21H2 - 25H2/26H1+)
$script:appxPatternsToRemove = @(
    # AI, Copilot & Recall (Windows 11 24H2/25H2+)
    "Microsoft.Windows.Copilot*",
    "Microsoft.Copilot*",
    "Microsoft.Copilot.Provider*",
    "Microsoft.549981C3F5F10*",
    "Microsoft.Windows.Ai.Studio*",
    "Microsoft.Windows.Ai.Component*",
    "Microsoft.AI.Search*",
    "Microsoft.Windows.StudioEffects*",
    "Microsoft.Windows.Recall*",
    "Recall*",
    "AI.Recall*",
    "Microsoft.Windows.Ai.Shell*",
    
    # 3D & Media
    "Microsoft.Microsoft3DViewer*",
    "Microsoft.MixedReality.Portal*",
    "Microsoft.ZuneMusic*",
    "Microsoft.ZuneVideo*",
    "Microsoft.WindowsSoundRecorder*",
    "Microsoft.Windows.Photos*",
    "Microsoft.ScreenSketch*",
    "Clipchamp.Clipchamp*",
    "Media.WindowsMediaPlayer*",
    
    # News, Weather, Finance, Widgets
    "Microsoft.BingNews*",
    "Microsoft.BingWeather*",
    "Microsoft.BingSports*",
    "Microsoft.BingFinance*",
    "Microsoft.BingSearch*",
    "Microsoft.BingTranslator*",
    "Microsoft.Windows.Widgets*",
    "Microsoft.Windows.Widgets.Platform*",
    
    # Office, DevHome, Communications & Work
    "Microsoft.Windows.DevHome*",
    "MicrosoftCorporationII.MicrosoftFamily*",
    "Microsoft.MicrosoftOfficeHub*",
    "Microsoft.Office.OneNote*",
    "Microsoft.OutlookForWindows*",
    "Microsoft.WindowsCommunicationsapps*",
    "Microsoft.PowerAutomateDesktop*",
    "MicrosoftCorporationII.QuickAssist*",
    "Microsoft.Todos*",
    "Microsoft.People*",
    "Microsoft.SkypeApp*",
    "MicrosoftTeams*",
    "MSTeams*",
    "Microsoft.Windows.Teams*",
    
    # Help, Feedback, Utilities
    "Microsoft.WindowsFeedbackHub*",
    "Microsoft.GetHelp*",
    "Microsoft.Getstarted*",
    "Microsoft.WindowsMaps*",
    "Microsoft.MSPaint*",
    "Microsoft.YourPhone*",
    "MicrosoftWindows.CrossDevice*",
    "Microsoft.MicrosoftSolitaireCollection*",
    "Microsoft.Wallet*",
    "Microsoft.WindowsAlarms*",
    
    # Gaming & Xbox
    "Microsoft.GamingApp*",
    "Microsoft.XboxApp*",
    "Microsoft.XboxGameOverlay*",
    "Microsoft.XboxGamingOverlay*",
    "Microsoft.XboxSpeechToTextOverlay*",
    "Microsoft.Xbox.TCUI*",
    "Microsoft.XboxIdentityProvider*",
    "Microsoft.XboxGameSpeechWindow*",
    "Microsoft.Windows.XboxGameCallableUI*",
    
    # Consumer & Shell Experiences
    "Microsoft.Windows.PeopleExperienceHost*",
    "Microsoft.WindowsStore*",
    "Microsoft.WindowsCamera*",
    "Microsoft.DesktopAppInstaller*",
    "Microsoft.WindowsWebExperiencePack*",
    "Microsoft.MicrosoftEdgeUpdate*",
    "Microsoft.Services.Store.Engagement*",
    "Microsoft.StorePurchaseApp*",
    "Microsoft.WindowsStorePurchaseApp*",
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
    "Microsoft.WindowsTips*",
    "Microsoft.OneDriveSync*",
    "Microsoft.OneDrive*",
    "Microsoft.StartExperiencesApp*",
    "Microsoft.Windows.SharePicker*",
    "Microsoft.Windows.NarratorQuickStart*"
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
        # BypassNRO for Windows 11 OOBE network bypass compatibility
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" "BypassNRO" "REG_DWORD" "1"
    }
    
    # Disable useless junks
    if ($DisableUselessJunks) {
        Write-Output "  Disabling useless junks, AI, Copilot & Recall..."
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate" "workCompleted" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate" "workCompleted" "REG_DWORD" "1"
        Remove-RegKey "SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate"
        Remove-RegKey "SOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\Windows Chat" "ChatIcon" "REG_DWORD" "3"

        # Disable Windows AI, Copilot and Recall (Windows 11 24H2 / 25H2 / 26H1+)
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "TurnOffRecall" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Policies\Microsoft\Windows\WindowsAI" "TurnOffRecall" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" "REG_DWORD" "1"
        Set-RegValue "SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" "REG_DWORD" "0"
        Set-RegValue "NTUSER\Software\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" "REG_DWORD" "1"
        Set-RegValue "NTUSER\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" "REG_DWORD" "0"
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

<#
.SYNOPSIS
    Helper function to set registry values in module scope
#>
function Set-ModuleRegistryValue {
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

function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    Set-ModuleRegistryValue -path $path -name $name -type $type -value $value
}


<#
.SYNOPSIS
    Apply extended privacy, telemetry and performance registry tweaks
#>
function Apply-ExtendedTelemetryAndPerformanceTweaks {
    param(
        [Parameter(Mandatory=$false)][bool]$DisableThirdPartyTelemetry = $true,
        [Parameter(Mandatory=$false)][bool]$TuneMouseLatency = $true,
        [Parameter(Mandatory=$false)][bool]$TuneDefenderCpuLimit = $true,
        [Parameter(Mandatory=$false)][bool]$EnableUltimatePerformance = $false,
        [Parameter(Mandatory=$false)][bool]$BlockFirewallTelemetry = $true,
        [Parameter(Mandatory=$false)][bool]$EnableFastShutdown = $true,
        [Parameter(Mandatory=$false)][bool]$DisableZoneInformation = $true,
        [Parameter(Mandatory=$false)][bool]$EnableDriverBlocklist = $true,
        [Parameter(Mandatory=$false)][bool]$EnableUtcClock = $true,
        [Parameter(Mandatory=$false)][bool]$DisableMouseAcceleration = $true
    )

    Write-Output "Applying extended privacy, telemetry and performance tweaks..."

    if ($DisableThirdPartyTelemetry) {
        Write-Output "  Disabling 3rd-party app telemetry (Adobe, VSCode, Nvidia)..."
        # VS Code Telemetry
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\Policies\Microsoft\VSCode" -name "EnableTelemetry" -type "REG_DWORD" -value "0"
        # Adobe Telemetry
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\Policies\Adobe\CommonFiles" -name "UsageDataCollection" -type "REG_DWORD" -value "0"
        # NVIDIA Telemetry
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\NVIDIA Corporation\Global\NVTweak" -name "DisplayTelemetry" -type "REG_DWORD" -value "0"
    }

    if ($TuneMouseLatency) {
        Write-Output "  Tuning mouse input queue size for reduced latency..."
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Services\mouclass\Parameters" -name "MouseDataQueueSize" -type "REG_DWORD" -value "100"
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Services\kbdclass\Parameters" -name "KeyboardDataQueueSize" -type "REG_DWORD" -value "100"
    }

    if ($DisableMouseAcceleration) {
        Write-Output "  Disabling mouse acceleration for 1:1 raw gaming precision..."
        Set-ModuleRegistryValue -path "HKLM\zNTUSER\Control Panel\Mouse" -name "MouseSpeed" -type "REG_SZ" -value "0"
        Set-ModuleRegistryValue -path "HKLM\zNTUSER\Control Panel\Mouse" -name "MouseThreshold1" -type "REG_SZ" -value "0"
        Set-ModuleRegistryValue -path "HKLM\zNTUSER\Control Panel\Mouse" -name "MouseThreshold2" -type "REG_SZ" -value "0"
    }

    if ($EnableUtcClock) {
        Write-Output "  Enabling UTC hardware clock (RealTimeIsUniversal=1) for seamless Linux dual-boot..."
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Control\TimeZoneInformation" -name "RealTimeIsUniversal" -type "REG_DWORD" -value "1"
    }

    if ($TuneDefenderCpuLimit) {
        Write-Output "  Limiting Windows Defender scan CPU usage to 25%..."
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\Policies\Microsoft\Windows Defender\Scan" -name "AvgCPULoadFactor" -type "REG_DWORD" -value "25"
    }

    if ($EnableUltimatePerformance) {
        Write-Output "  Enabling Ultimate Performance Power Scheme on first boot..."
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" -name "SetUltimatePowerScheme" -type "REG_SZ" -value "powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61"
    }

    if ($BlockFirewallTelemetry) {
        Write-Output "  Adding Windows Firewall rules to block system telemetry outbound connections..."
        $fwRulePath = "HKLM\zSYSTEM\ControlSet001\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules"
        Set-ModuleRegistryValue -path $fwRulePath -name "Block SearchHost" -type "REG_SZ" -value "v2.32|Action=Block|Active=TRUE|Dir=Out|RA42=IntErnet|RA62=IntErnet|App=%SystemRoot%\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\SearchHost.exe|Name=Block SearchHost|Desc=Block SearchHost Outbound Traffic|"
        Set-ModuleRegistryValue -path $fwRulePath -name "Block StartMenuExperienceHost" -type "REG_SZ" -value "v2.32|Action=Block|Active=TRUE|Dir=Out|RA42=IntErnet|RA62=IntErnet|App=%SystemRoot%\SystemApps\Microsoft.Windows.StartMenuExperienceHost_cw5n1h2txyewy\StartMenuExperienceHost.exe|Name=Block StartMenuExperienceHost|Desc=Block Start Menu Outbound Traffic|"
        Set-ModuleRegistryValue -path $fwRulePath -name "Block SystemSettings" -type "REG_SZ" -value "v2.32|Action=Block|Active=TRUE|Dir=Out|RA42=IntErnet|RA62=IntErnet|App=%SystemRoot%\ImmersiveControlPanel\SystemSettings.exe|Name=Block SystemSettings|Desc=Block Settings Outbound Telemetry Traffic|"
        Set-ModuleRegistryValue -path $fwRulePath -name "Block Explorer" -type "REG_SZ" -value "v2.32|Action=Block|Active=TRUE|Dir=Out|RA42=IntErnet|RA62=IntErnet|App=%SystemRoot%\explorer.exe|Name=Block Explorer|Desc=Block Explorer Outbound Home Traffic|"
    }

    if ($EnableFastShutdown) {
        Write-Output "  Applying fast shutdown tweaks..."
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Control" -name "WaitToKillServiceTimeout" -type "REG_SZ" -value "2000"
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Control" -name "HungAppTimeout" -type "REG_SZ" -value "2000"
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Control" -name "AutoEndTasks" -type "REG_SZ" -value "1"
    }

    if ($DisableZoneInformation) {
        Write-Output "  Bypassing internet download security warning popups (Zone.Identifier)..."
        Set-ModuleRegistryValue -path "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Attachments" -name "SaveZoneInformation" -type "REG_DWORD" -value "1"
    }

    if ($EnableDriverBlocklist) {
        Write-Output "  Enabling vulnerable driver blocklist for enhanced kernel security..."
        Set-ModuleRegistryValue -path "HKLM\zSYSTEM\ControlSet001\Control\CI\Config" -name "VulnerableDriverBlocklistEnable" -type "REG_DWORD" -value "1"
    }
}




<#
.SYNOPSIS
    Load preset config from JSON file or name
#>
function Get-PresetConfig {
    param(
        [Parameter(Mandatory=$true)][string]$PresetNameOrPath
    )
    
    $presetPath = $PresetNameOrPath
    if (-not (Test-Path $presetPath)) {
        # Check in presets directory
        $presetPath = Join-Path (Split-Path $PSScriptRoot -Parent) "presets\$PresetNameOrPath.json"
        if (-not (Test-Path $presetPath)) {
            $presetPath = Join-Path $PSScriptRoot "presets\$PresetNameOrPath.json"
        }
    }

    if (Test-Path $presetPath) {
        Write-Output "Loading preset config from: $presetPath"
        return (Get-Content $presetPath -Raw | ConvertFrom-Json)
    } else {
        Write-Warning "Preset file not found: $PresetNameOrPath"
        return $null
    }
}

<#
.SYNOPSIS
    Generate dynamic autounattend.xml file
#>
function New-DynamicAutounattendXml {
    param(
        [string]$OutputPath = "$PSScriptRoot\autounattend.xml",
        [string]$Username = "",
        [switch]$BypassTPM = $true,
        [switch]$BypassRAM = $true,
        [switch]$BypassStorage = $true,
        [switch]$CompactOS = $true,
        [string[]]$CustomCommands = @()
    )

    Write-Output "Generating dynamic autounattend.xml at $OutputPath..."

    $firstLogonXml = ""
    $commandIndex = 1

    if ($CustomCommands.Count -gt 0) {
        $firstLogonXml += "            <FirstLogonCommands>`n"
        
        # Custom commands
        foreach ($cmd in $CustomCommands) {
            if (-not [string]::IsNullOrWhiteSpace($cmd)) {
                $firstLogonXml += "                <SynchronousCommand wcm:action=`"add`">`n"
                $firstLogonXml += "                    <Order>$commandIndex</Order>`n"
                $firstLogonXml += "                    <CommandLine>$cmd</CommandLine>`n"
                $firstLogonXml += "                    <Description>Custom Post-Install Command</Description>`n"
                $firstLogonXml += "                </SynchronousCommand>`n"
                $commandIndex++
            }
        }

        $firstLogonXml += "            </FirstLogonCommands>`n"
    }

    $compactStr = if ($CompactOS) { "true" } else { "false" }


    $xmlContent = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`n" +
"<unattend xmlns=`"urn:schemas-microsoft-com:unattend`">`n" +
"    <settings pass=`"oobeSystem`">`n" +
"        <component name=`"Microsoft-Windows-Shell-Setup`" processorArchitecture=`"*`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`" xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`n" +
"            <OOBE>`n" +
"                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>`n" +
"                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>`n" +
"                <ProtectYourPC>3</ProtectYourPC>`n" +
"            </OOBE>`n" +
"            <ConfigureChatAutoInstall>false</ConfigureChatAutoInstall>`n" +
"$firstLogonXml" +
"        </component>`n" +
"    </settings>`n" +
"    <settings pass=`"windowsPE`">`n" +
"        <component name=`"Microsoft-Windows-Setup`" processorArchitecture=`"*`" publicKeyToken=`"31bf3856ad364e35`" language=`"neutral`" versionScope=`"nonSxS`" xmlns:wcm=`"http://schemas.microsoft.com/WMIConfig/2002/State`" xmlns:xsi=`"http://www.w3.org/2001/XMLSchema-instance`">`n" +
"            <DynamicUpdate>`n" +
"                <WillShowUI>OnError</WillShowUI>`n" +
"            </DynamicUpdate>`n" +
"            <ImageInstall>`n" +
"                <OSImage>`n" +
"                    <Compact>$compactStr</Compact>`n" +
"                    <WillShowUI>Always</WillShowUI>`n" +
"                </OSImage>`n" +
"            </ImageInstall>`n" +
"            <UserData>`n" +
"                <ProductKey>`n" +
"                    <WillShowUI>Always</WillShowUI>`n" +
"                </ProductKey>`n" +
"            </UserData>`n" +
"            <RunSynchronous>`n" +
"                <RunSynchronousCommand wcm:action=`"add`">`n" +
"                    <Order>1</Order>`n" +
"                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>`n" +
"                </RunSynchronousCommand>`n" +
"                <RunSynchronousCommand wcm:action=`"add`">`n" +
"                    <Order>2</Order>`n" +
"                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>`n" +
"                </RunSynchronousCommand>`n" +
"                <RunSynchronousCommand wcm:action=`"add`">`n" +
"                    <Order>3</Order>`n" +
"                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassStorageCheck /t REG_DWORD /d 1 /f</Path>`n" +
"                </RunSynchronousCommand>`n" +
"                <RunSynchronousCommand wcm:action=`"add`">`n" +
"                    <Order>4</Order>`n" +
"                    <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>`n" +
"                </RunSynchronousCommand>`n" +
"            </RunSynchronous>`n" +
"        </component>`n" +
"    </settings>`n" +
"</unattend>`n"

    Set-Content -Path $OutputPath -Value $xmlContent -Encoding UTF8
    Write-Output "[+] Dynamic autounattend.xml generated successfully."
}

# Export các functions
Export-ModuleMember -Function Remove-DebloatPackages, Apply-DebloatRegistryTweaks, Remove-DebloatFiles, Get-CapabilitiesToRemove, Get-WindowsPackagesToRemove, Apply-ExtendedTelemetryAndPerformanceTweaks, Get-PresetConfig, New-DynamicAutounattendXml, Set-RegistryValue, Set-ModuleRegistryValue



