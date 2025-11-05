# Script to find IRST driver location on Windows machine
# After installing IRST driver, this script will help locate the driver files

Write-Host "=== Finding IRST Driver Locations ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check DriverStore (where Windows stores installed drivers)
Write-Host "1. Checking DriverStore (C:\Windows\System32\DriverStore\FileRepository)..." -ForegroundColor Yellow
$driverStore = "C:\Windows\System32\DriverStore\FileRepository"
if (Test-Path $driverStore) {
    $irstDrivers = Get-ChildItem $driverStore -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like '*irst*' -or 
        $_.Name -like '*iaStor*' -or 
        $_.Name -like '*Rapid*Storage*' -or
        $_.Name -like '*iastor*'
    }
    
    if ($irstDrivers) {
        Write-Host "   Found IRST drivers:" -ForegroundColor Green
        foreach ($driver in $irstDrivers) {
            Write-Host "   - $($driver.FullName)" -ForegroundColor Green
            $infFiles = Get-ChildItem $driver.FullName -Filter "*.inf" -ErrorAction SilentlyContinue
            if ($infFiles) {
                Write-Host "     Contains: $($infFiles.Count) .inf file(s)" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "   No IRST drivers found in DriverStore" -ForegroundColor Gray
    }
} else {
    Write-Host "   DriverStore path not found" -ForegroundColor Red
}

Write-Host ""

# 2. Check Program Files
Write-Host "2. Checking Program Files..." -ForegroundColor Yellow
$programFilesPaths = @(
    "C:\Program Files\Intel\Intel(R) Rapid Storage Technology",
    "C:\Program Files (x86)\Intel\Intel(R) Rapid Storage Technology",
    "C:\Program Files\Intel",
    "C:\Program Files (x86)\Intel"
)

foreach ($path in $programFilesPaths) {
    if (Test-Path $path) {
        Write-Host "   Found: $path" -ForegroundColor Green
        $infFiles = Get-ChildItem $path -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($infFiles) {
            Write-Host "   Driver folder: $($infFiles.Directory.FullName)" -ForegroundColor Cyan
        }
    }
}

Write-Host ""

# 3. Check Temp folders
Write-Host "3. Checking Temp folders..." -ForegroundColor Yellow
$tempFolders = @(
    "$env:TEMP\Intel",
    "$env:LOCALAPPDATA\Temp\Intel",
    "C:\Windows\Temp\Intel"
)

foreach ($folder in $tempFolders) {
    if (Test-Path $folder) {
        Write-Host "   Found: $folder" -ForegroundColor Green
        $infFiles = Get-ChildItem $folder -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($infFiles) {
            Write-Host "   Driver folder: $($infFiles.Directory.FullName)" -ForegroundColor Cyan
        }
    }
}

Write-Host ""

# 4. Instructions for extracting from SetupRST.exe
Write-Host "=== How to Extract Driver from SetupRST.exe (RECOMMENDED) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "If you have SetupRST.exe installer, you can extract drivers WITHOUT installing:" -ForegroundColor Yellow
Write-Host ""
Write-Host "Method 1:" -ForegroundColor Green
Write-Host "  SetupRST.exe -extractdrivers C:\ExtractedIRST" -ForegroundColor White
Write-Host ""
Write-Host "Method 2:" -ForegroundColor Green
Write-Host "  SetupRST.exe /extract:C:\ExtractedIRST" -ForegroundColor White
Write-Host ""
Write-Host "Then use the extracted folder:" -ForegroundColor Yellow
Write-Host "  .\tiny11maker.ps1 -ISO E -SCRATCH D -IrstDriverPath C:\ExtractedIRST" -ForegroundColor White
Write-Host ""

# 5. Check if SetupRST.exe exists in Downloads or common locations
Write-Host "=== Searching for SetupRST.exe ===" -ForegroundColor Cyan
$searchPaths = @(
    "$env:USERPROFILE\Downloads",
    "$env:USERPROFILE\Desktop",
    "C:\",
    "D:\"
)

$foundSetup = $false
foreach ($basePath in $searchPaths) {
    if (Test-Path $basePath) {
        $setupFiles = Get-ChildItem $basePath -Filter "*SetupRST*.exe" -Recurse -ErrorAction SilentlyContinue -Depth 2 | Select-Object -First 1
        if ($setupFiles) {
            Write-Host "Found SetupRST.exe: $($setupFiles.FullName)" -ForegroundColor Green
            Write-Host "You can extract drivers using:" -ForegroundColor Yellow
            Write-Host "  `"$($setupFiles.FullName)`" -extractdrivers C:\ExtractedIRST" -ForegroundColor White
            $foundSetup = $true
            break
        }
    }
}

if (-not $foundSetup) {
    Write-Host "SetupRST.exe not found in common locations" -ForegroundColor Gray
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "For best results, extract driver from SetupRST.exe installer" -ForegroundColor Yellow
Write-Host "Driver folder should contain .inf files that can be used with -IrstDriverPath parameter" -ForegroundColor Yellow

