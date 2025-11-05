# Script to extract IRST driver from SetupRST.exe
# This extracts drivers WITHOUT installing them

Write-Host "=== Extract IRST Driver from SetupRST.exe ===" -ForegroundColor Cyan
Write-Host ""

$setupRstPath = "C:\Users\DUC NAM\Downloads\Programs\SetupRST.exe"
$extractPath = "C:\ExtractedIRST"

# Check if SetupRST.exe exists
if (-not (Test-Path $setupRstPath)) {
    Write-Host "SetupRST.exe not found at: $setupRstPath" -ForegroundColor Red
    Write-Host "Please update the path in this script or provide the correct path." -ForegroundColor Yellow
    exit 1
}

Write-Host "Found SetupRST.exe: $setupRstPath" -ForegroundColor Green
Write-Host ""

# Clean up old extract folder if exists
if (Test-Path $extractPath) {
    Write-Host "Removing old extraction folder..." -ForegroundColor Yellow
    Remove-Item $extractPath -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Extracting IRST driver to: $extractPath" -ForegroundColor Yellow
Write-Host "This may take a few moments..." -ForegroundColor Gray
Write-Host ""

try {
    # Run SetupRST.exe with extract parameter using & operator
    Write-Host "Running: & `"$setupRstPath`" -extractdrivers $extractPath" -ForegroundColor Gray
    & $setupRstPath -extractdrivers $extractPath
    
    Write-Host "Extract command executed!" -ForegroundColor Green
    Write-Host ""
    
    # Wait a bit for files to be written
    Start-Sleep -Seconds 3
    
    # Check if extraction was successful
    if (Test-Path $extractPath) {
        Write-Host "Checking extracted driver files..." -ForegroundColor Cyan
        
        # Find .inf files
        $infFiles = Get-ChildItem $extractPath -Filter "*.inf" -Recurse -ErrorAction SilentlyContinue
        
        if ($infFiles) {
            Write-Host ""
            Write-Host "SUCCESS! Driver extracted successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "Found $($infFiles.Count) .inf file(s)" -ForegroundColor Cyan
            
            # Find the main driver folder (usually contains the .inf files)
            $driverFolders = $infFiles | Group-Object Directory | Sort-Object Count -Descending
            $mainDriverFolder = $driverFolders[0].Group[0].Directory.FullName
            
            Write-Host ""
            Write-Host "Main driver folder:" -ForegroundColor Yellow
            Write-Host "  $mainDriverFolder" -ForegroundColor Green
            Write-Host ""
            Write-Host "Sample .inf files:" -ForegroundColor Yellow
            $infFiles | Select-Object -First 5 | ForEach-Object {
                Write-Host "  - $($_.Name)" -ForegroundColor Gray
            }
            
            Write-Host ""
            Write-Host "=== Usage in Script ===" -ForegroundColor Cyan
            Write-Host "Use this path in your build script:" -ForegroundColor Yellow
            Write-Host "  .\tiny11maker.ps1 -ISO E -SCRATCH D -IrstDriverPath `"$mainDriverFolder`"" -ForegroundColor White
            Write-Host ""
            Write-Host "Or use the root extraction folder:" -ForegroundColor Yellow
            Write-Host "  .\tiny11maker.ps1 -ISO E -SCRATCH D -IrstDriverPath `"$extractPath`"" -ForegroundColor White
            
        } else {
            Write-Host ""
            Write-Host "Extraction folder created but no .inf files found." -ForegroundColor Yellow
            Write-Host "Extracted folder: $extractPath" -ForegroundColor Cyan
            Write-Host "Please check the folder manually." -ForegroundColor Yellow
        }
    } else {
        Write-Host ""
        Write-Host "Extraction folder was not created." -ForegroundColor Yellow
        Write-Host "This may require Administrator privileges." -ForegroundColor Yellow
        Write-Host "Try running manually with & operator:" -ForegroundColor Yellow
        Write-Host "  & `"$setupRstPath`" -extractdrivers $extractPath" -ForegroundColor White
    }
} catch {
    Write-Host ""
    Write-Host "Error during extraction: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Try running manually with & operator:" -ForegroundColor Yellow
    Write-Host "  & `"$setupRstPath`" -extractdrivers $extractPath" -ForegroundColor White
}

Write-Host ""
