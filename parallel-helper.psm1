<#
.SYNOPSIS
    Helper module for parallel processing in PowerShell scripts

.DESCRIPTION
    This module provides functions to parallelize operations that can be run concurrently,
    such as file removal, registry operations, and other independent tasks.
#>

# Get max parallel jobs from environment or calculate from CPU cores
function Get-MaxParallelJobs {
    if ($env:MAX_PARALLEL_JOBS) {
        return [int]$env:MAX_PARALLEL_JOBS
    }
    $cpuCores = $env:NUMBER_OF_PROCESSORS
    if (-not $cpuCores) {
        $cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors
    }
    # Ensure $cpuCores is an integer
    $cpuCores = [int]$cpuCores
    if ($cpuCores -le 0) {
        $cpuCores = 2  # Fallback to minimum
    }
    # Default to 80% of CPU cores, minimum 2
    return [math]::Max(2, [math]::Floor($cpuCores * 0.8))
}

<#
.SYNOPSIS
    Remove multiple items in parallel
#>
function Remove-ItemsParallel {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Paths,
        
        [Parameter(Mandatory=$false)]
        [switch]$Recurse = $false,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxParallel = -1
    )
    
    if ($MaxParallel -le 0) {
        $MaxParallel = Get-MaxParallelJobs
    }
    
    # Ensure MaxParallel is an integer
    $MaxParallel = [int]$MaxParallel
    if ($MaxParallel -le 0) {
        $MaxParallel = 2  # Fallback to minimum
    }
    
    Write-Host "Removing $($Paths.Count) items in parallel (max $MaxParallel concurrent operations)..." -ForegroundColor Cyan
    
    $jobs = @()
    $batchSize = $MaxParallel
    $totalBatches = [math]::Ceiling($Paths.Count / $batchSize)
    
    for ($batch = 0; $batch -lt $totalBatches; $batch++) {
        # Calculate batch range safely
        $startIndex = $batch * $batchSize
        $endIndex = [math]::Min(($batch + 1) * $batchSize - 1, $Paths.Count - 1)
        $batchPaths = $Paths[$startIndex..$endIndex]
        
        $batchJobs = $batchPaths | ForEach-Object -Parallel {
            $path = $_
            $recurse = $using:Recurse
            try {
                if (Test-Path $path) {
                    Remove-Item -Path $path -Recurse:$recurse -Force -ErrorAction SilentlyContinue
                    return @{ Path = $path; Success = $true }
                } else {
                    return @{ Path = $path; Success = $true; Skipped = $true }
                }
            } catch {
                return @{ Path = $path; Success = $false; Error = $_.Exception.Message }
            }
        } -ThrottleLimit $batchSize
        
        $jobs += $batchJobs
        
        # Progress update
        $completed = ($batch + 1) * $batchSize
        if ($completed -gt $Paths.Count) { $completed = $Paths.Count }
        Write-Host "  Progress: $completed/$($Paths.Count) items processed" -ForegroundColor Gray
    }
    
    $successCount = ($jobs | Where-Object { $_.Success }).Count
    $skippedCount = ($jobs | Where-Object { $_.Skipped }).Count
    $failedCount = ($jobs | Where-Object { -not $_.Success }).Count
    
    Write-Host "  Completed: $successCount succeeded, $skippedCount skipped, $failedCount failed" -ForegroundColor Green
    
    return $jobs
}

<#
.SYNOPSIS
    Execute multiple registry operations in parallel
#>
function Set-RegistryValuesParallel {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable[]]$RegistryOperations,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxParallel = -1
    )
    
    if ($MaxParallel -le 0) {
        $MaxParallel = Get-MaxParallelJobs
    }
    
    # Ensure MaxParallel is an integer
    $MaxParallel = [int]$MaxParallel
    if ($MaxParallel -le 0) {
        $MaxParallel = 2  # Fallback to minimum
    }
    
    Write-Host "Setting $($RegistryOperations.Count) registry values in parallel (max $MaxParallel concurrent operations)..." -ForegroundColor Cyan
    
    $results = $RegistryOperations | ForEach-Object -Parallel {
        $op = $_
        try {
            & reg add $op.Path /v $op.Name /t $op.Type /d $op.Value /f 2>&1 | Out-Null
            return @{ Path = $op.Path; Name = $op.Name; Success = $true }
        } catch {
            return @{ Path = $op.Path; Name = $op.Name; Success = $false; Error = $_.Exception.Message }
        }
    } -ThrottleLimit $MaxParallel
    
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failedCount = ($results | Where-Object { -not $_.Success }).Count
    
    Write-Host "  Completed: $successCount succeeded, $failedCount failed" -ForegroundColor Green
    
    return $results
}

<#
.SYNOPSIS
    Execute multiple commands in parallel (for independent operations)
#>
function Invoke-CommandsParallel {
    param(
        [Parameter(Mandatory=$true)]
        [scriptblock[]]$Commands,
        
        [Parameter(Mandatory=$false)]
        [int]$MaxParallel = -1
    )
    
    if ($MaxParallel -le 0) {
        $MaxParallel = Get-MaxParallelJobs
    }
    
    # Ensure MaxParallel is an integer
    $MaxParallel = [int]$MaxParallel
    if ($MaxParallel -le 0) {
        $MaxParallel = 2  # Fallback to minimum
    }
    
    Write-Host "Executing $($Commands.Count) commands in parallel (max $MaxParallel concurrent operations)..." -ForegroundColor Cyan
    
    $results = $Commands | ForEach-Object -Parallel {
        $cmd = $_
        try {
            $output = & $cmd 2>&1
            return @{ Success = $true; Output = $output }
        } catch {
            return @{ Success = $false; Error = $_.Exception.Message }
        }
    } -ThrottleLimit $MaxParallel
    
    $successCount = ($results | Where-Object { $_.Success }).Count
    $failedCount = ($results | Where-Object { -not $_.Success }).Count
    
    Write-Host "  Completed: $successCount succeeded, $failedCount failed" -ForegroundColor Green
    
    return $results
}

# Export functions
Export-ModuleMember -Function Get-MaxParallelJobs, Remove-ItemsParallel, Set-RegistryValuesParallel, Invoke-CommandsParallel

