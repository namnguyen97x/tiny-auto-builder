# Script to copy IRST driver from DriverStore to project folder
Write-Host "=== Copying IRST Driver from DriverStore to Project ===" -ForegroundColor Cyan
Write-Host ""

$driverStore = "C:\Windows\System32\DriverStore\FileRepository"
$projectDriverFolder = Join-Path $PSScriptRoot "IRST_Driver"

if (-not (Test-Path $driverStore)) {
    Write-Host "DriverStore not found!" -ForegroundColor Red
    exit 1
}

if (Test-Path $projectDriverFolder) {
    Write-Host "Removing old IRST_Driver folder..." -ForegroundColor Yellow
    Remove-Item $projectDriverFolder -Recurse -Force -ErrorAction SilentlyContinue
}

New-Item -ItemType Directory -Path $projectDriverFolder -Force | Out-Null
Write-Host "Created folder: $projectDriverFolder" -ForegroundColor Green
Write-Host ""

Write-Host "Searching for IRST drivers..." -ForegroundColor Yellow
$irstDrivers = Get-ChildItem $driverStore -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '*iastor*' }

if (-not $irstDrivers) {
    Write-Host "No IRST drivers found!" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($irstDrivers.Count) IRST driver folder(s)" -ForegroundColor Green
Write-Host ""

foreach ($driver in $irstDrivers) {
    Write-Host "Copying: $($driver.Name)..." -ForegroundColor Gray
    $destPath = Join-Path $projectDriverFolder $driver.Name
    Copy-Item -Path $driver.FullName -Destination $destPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
$infFiles = Get-ChildItem $projectDriverFolder -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue

if ($infFiles) {
    Write-Host ""
    Write-Host "SUCCESS! Driver copied to project!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Driver folder: $projectDriverFolder" -ForegroundColor Cyan
    Write-Host "Total INF files: $($infFiles.Count)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "=== Usage ===" -ForegroundColor Yellow
    Write-Host ".\tiny11maker.ps1 -ISO E -SCRATCH D -IrstDriverPath `"$projectDriverFolder`"" -ForegroundColor White
    Write-Host ""
    
    # Add to .gitignore
    $gitignore = Join-Path $PSScriptRoot ".gitignore"
    if (Test-Path $gitignore) {
        $content = Get-Content $gitignore -Raw -ErrorAction SilentlyContinue
        if ($content -notmatch "IRST_Driver") {
            Add-Content $gitignore "`n# IRST Driver files" -ErrorAction SilentlyContinue
            Add-Content $gitignore "IRST_Driver/" -ErrorAction SilentlyContinue
        }
    } else {
        "IRST_Driver/" | Out-File $gitignore -Encoding UTF8
    }
} else {
    Write-Host "Warning: No INF files found!" -ForegroundColor Yellow
}

Write-Host ""
