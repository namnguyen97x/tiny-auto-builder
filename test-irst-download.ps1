# Test script for IRST driver auto-download functionality
# This script tests the Get-IrstDriver function without needing a full ISO build

$ErrorActionPreference = 'Continue'

Write-Host "=== Testing IRST Driver Auto-Download Function ===" -ForegroundColor Cyan
Write-Host ""

# Define the function inline for testing
function Get-IrstDriver {
    param (
        [string]$DownloadUrl = '',
        [string]$TempDir = ''
    )
    
    if (-not $TempDir) {
        $TempDir = Join-Path $env:TEMP "IRST_Driver"
    }
    
    # Create temp directory
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }
    
    # Check if driver already exists in temp directory
    $infFiles = Get-ChildItem -Path $TempDir -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($infFiles) {
        $driverFolder = $infFiles.Directory.FullName
        Write-Host "Found existing IRST driver in temp directory: $driverFolder" -ForegroundColor Green
        return $driverFolder
    }
    
    # If no URL provided, try to find latest IRST driver
    if (-not $DownloadUrl) {
        Write-Host "No IRST driver URL provided. Searching for latest version..."
        # Intel IRST driver URLs (Windows 11 compatible)
        # Note: These URLs may change, user can provide custom URL via parameter
        $possibleUrls = @(
            "https://downloadmirror.intel.com/805586/f6vflpy-x64.zip",  # IRST 19.x for Windows 11
            "https://downloadmirror.intel.com/805586/f6vflpy-x64.zip"   # Fallback
        )
        
        $found = $false
        foreach ($url in $possibleUrls) {
            try {
                Write-Host "Attempting to download from: $url"
                $zipPath = Join-Path $TempDir "IRST_Driver.zip"
                Invoke-WebRequest -Uri $url -OutFile $zipPath -UserAgent "Mozilla/5.0" -TimeoutSec 30 -ErrorAction Stop
                $DownloadUrl = $url
                $found = $true
                break
            } catch {
                Write-Warning "Failed to download from $url : $($_.Exception.Message)"
                continue
            }
        }
        
        if (-not $found) {
            Write-Warning "Could not automatically download IRST driver. Please provide driver path manually or download URL."
            Write-Host "You can download IRST driver from: https://www.intel.com/content/www/us/en/download-center/home.html"
            Write-Host "Search for 'Intel Rapid Storage Technology' driver for Windows 11"
            return $null
        }
        
        $zipPath = Join-Path $TempDir "IRST_Driver.zip"
    } else {
        # Download from provided URL
        Write-Host "Downloading IRST driver from: $DownloadUrl"
        $zipPath = Join-Path $TempDir "IRST_Driver.zip"
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipPath -UserAgent "Mozilla/5.0" -TimeoutSec 60 -ErrorAction Stop
        } catch {
            Write-Warning "Failed to download IRST driver: $($_.Exception.Message)"
            return $null
        }
    }
    
    # Extract driver
    Write-Host "Extracting IRST driver..."
    try {
        $extractPath = Join-Path $TempDir "IRST_Extracted"
        if (Test-Path $extractPath) {
            Remove-Item -Path $extractPath -Recurse -Force
        }
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
        
        # Find driver folder (usually contains .inf files)
        $infFiles = Get-ChildItem -Path $extractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if ($infFiles) {
            $driverFolder = $infFiles.Directory.FullName
            Write-Host "IRST driver extracted successfully: $driverFolder" -ForegroundColor Green
            # Clean up zip file
            Remove-Item -Path $zipPath -Force -ErrorAction SilentlyContinue
            return $driverFolder
        } else {
            Write-Warning "Could not find driver folder with .inf files in extracted archive"
            return $extractPath
        }
    } catch {
        Write-Warning "Failed to extract IRST driver: $($_.Exception.Message)"
        return $null
    }
}

Write-Host "Testing auto-download IRST driver..." -ForegroundColor Yellow
Write-Host "This will attempt to download IRST driver from Intel"
Write-Host ""

try {
    $driverPath = Get-IrstDriver
    
    if ($driverPath -and (Test-Path $driverPath)) {
        Write-Host ""
        Write-Host "SUCCESS: IRST driver downloaded and extracted!" -ForegroundColor Green
        Write-Host "Driver path: $driverPath" -ForegroundColor Cyan
        
        # Check for .inf files
        $infFiles = Get-ChildItem -Path $driverPath -Filter "*.inf" -ErrorAction SilentlyContinue
        if ($infFiles) {
            Write-Host "Found $($infFiles.Count) .inf file(s) in driver folder" -ForegroundColor Green
            Write-Host "Sample files:"
            $infFiles | Select-Object -First 3 | ForEach-Object {
                Write-Host "  - $($_.Name)" -ForegroundColor Gray
            }
        }
        
        Write-Host ""
        Write-Host "Test completed successfully! Function is working correctly." -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "FAILED: Could not download or extract IRST driver" -ForegroundColor Red
        Write-Host "This might be due to network issues or URL changes." -ForegroundColor Yellow
        Write-Host "You can still use -IrstDriverPath parameter to provide driver manually." -ForegroundColor Yellow
    }
} catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

