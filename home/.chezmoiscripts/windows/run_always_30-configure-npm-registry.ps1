$ErrorActionPreference = "Stop"

$isWork = $null
if (-not [string]::IsNullOrWhiteSpace($env:CHEZMOI_IS_WORK)) {
    if ($env:CHEZMOI_IS_WORK -notmatch '^(?i:true|false)$') {
        Write-Error "CHEZMOI_IS_WORK must be either true or false."
        exit 1
    }

    $isWork = $env:CHEZMOI_IS_WORK -eq "true"
}
else {
    $chezmoiDataJson = (chezmoi data --format json 2>&1) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not read Chezmoi data to determine whether this is a work device."
        exit $LASTEXITCODE
    }

    $chezmoiData = $chezmoiDataJson | ConvertFrom-Json
    $isWork = [bool]$chezmoiData.isWork
}

if (-not $isWork) {
    Write-Host "[SKIP] Microsoft work npm registry is not required on this device." -ForegroundColor Yellow
    exit 0
}

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "[SKIP] npm is not installed; registry configuration is not required." -ForegroundColor Yellow
    exit 0
}

Write-Host "Configuring the Microsoft work npm registry..." -ForegroundColor Cyan
npm config set registry "https://packagefeedproxy.microsoft.io/npm/" --location=user
if ($LASTEXITCODE -ne 0) {
    Write-Error "npm failed to configure the user registry."
    exit $LASTEXITCODE
}
Write-Host "[OK] npm user registry configured." -ForegroundColor Green
