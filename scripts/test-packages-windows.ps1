# Test script to validate packages.yaml for Windows
# This script tests if the YAML file can be parsed and accessed by Chezmoi

$ErrorActionPreference = "Stop"

Write-Host "Testing packages.yaml for Windows..." -ForegroundColor Cyan

# Check if chezmoi is available
$chezmoi = Get-Command chezmoi -ErrorAction SilentlyContinue
if (-not $chezmoi) {
    Write-Warning "Chezmoi not found. This test requires chezmoi to be installed."
    exit 1
}

# Test parsing the packages.yaml through chezmoi data
Write-Host "`nTesting chezmoi data access..." -ForegroundColor Yellow

# Change to repo root
$repoRoot = Split-Path $PSScriptRoot -Parent
Push-Location $repoRoot

try {
    # Get chezmoi data to verify packages.yaml is loaded
    $output = chezmoi data --format=json --source=. 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Chezmoi command failed: $output"
        Pop-Location
        exit 1
    }
    $data = $output | ConvertFrom-Json
    
    if ($data.packages) {
        Write-Host "✅ packages.yaml is loaded by chezmoi" -ForegroundColor Green
        
        # Check Windows section
        if ($data.packages.windows) {
            Write-Host "✅ Windows packages section found" -ForegroundColor Green
            
            # Check winget packages
            if ($data.packages.windows.winget) {
                if ($data.packages.windows.winget.light) {
                    $lightCount = $data.packages.windows.winget.light.Count
                    Write-Host "✅ Found $lightCount light WinGet packages" -ForegroundColor Green
                    Write-Host "   Light: $($data.packages.windows.winget.light -join ', ')" -ForegroundColor Gray
                }
                if ($data.packages.windows.winget.full) {
                    $fullCount = $data.packages.windows.winget.full.Count
                    Write-Host "✅ Found $fullCount additional full WinGet packages" -ForegroundColor Green
                    Write-Host "   Full: $($data.packages.windows.winget.full -join ', ')" -ForegroundColor Gray
                }
            } else {
                Write-Warning "⚠️ No winget packages found"
            }
            
            # Check PowerShell modules
            if ($data.packages.windows.powershell_modules) {
                if ($data.packages.windows.powershell_modules.light) {
                    $lightModCount = $data.packages.windows.powershell_modules.light.Count
                    Write-Host "✅ Found $lightModCount light PowerShell modules" -ForegroundColor Green
                    Write-Host "   Light: $($data.packages.windows.powershell_modules.light -join ', ')" -ForegroundColor Gray
                }
                if ($data.packages.windows.powershell_modules.full) {
                    $fullModCount = $data.packages.windows.powershell_modules.full.Count
                    Write-Host "✅ Found $fullModCount additional full PowerShell modules" -ForegroundColor Green
                    Write-Host "   Full: $($data.packages.windows.powershell_modules.full -join ', ')" -ForegroundColor Gray
                }
            } else {
                Write-Warning "⚠️ No PowerShell modules found"
            }
        } else {
            Write-Error "❌ Windows packages section not found"
            exit 1
        }
        
    } else {
        Write-Error "❌ packages data not found in chezmoi data"
        exit 1
    }
    
    Write-Host "`n✅ All tests passed! packages.yaml is valid for Windows" -ForegroundColor Green
    
} catch {
    Write-Error "❌ Error testing chezmoi data: $_"
    Pop-Location
    exit 1
} finally {
    Pop-Location
}
