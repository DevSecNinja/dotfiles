# Chezmoi utilities

function Reset-ChezmoiScripts {
    # Clears Chezmoi script execution state to force re-running of run_once_* and run_onchange_* scripts
    chezmoi state delete-bucket --bucket=scriptState
    Write-Host "Chezmoi script state cleared. run_once_* scripts will re-execute on next 'chezmoi apply'." -ForegroundColor Green
}

function Reset-ChezmoiEntries {
    # Clears Chezmoi entry state to force reprocessing of all managed files
    chezmoi state delete-bucket --bucket=entryState
    Write-Host "Chezmoi entry state cleared. All files will be reprocessed on next 'chezmoi apply'." -ForegroundColor Yellow
    Write-Host "Warning: This may cause unexpected changes. Use 'chezmoi apply --dry-run' first." -ForegroundColor Yellow
}

function Invoke-ChezmoiSigning {
    param(
        [string]$CertificateThumbprint = "421f66cf0a29ef657c83316a88d5d2ff918eeb7b"
    )

    # Signs PowerShell scripts in the Chezmoi source directory and repository root
    $chezmoiSourceDir = chezmoi source-path
    if ($LASTEXITCODE -ne 0 -or -not $chezmoiSourceDir) {
        Write-Host "Error: Failed to get Chezmoi source directory" -ForegroundColor Red
        return
    }

    # Get repository root (parent of Chezmoi source dir, which is typically 'home/')
    $repoRoot = Split-Path -Parent $chezmoiSourceDir

    $signingScript = Join-Path -Path $chezmoiSourceDir -ChildPath "dot_config\powershell\scripts\Sign-PowerShellScripts.ps1"

    if (-not (Test-Path $signingScript)) {
        Write-Host "Error: Sign-PowerShellScripts.ps1 not found at $signingScript" -ForegroundColor Red
        return
    }

    # Sign all PowerShell scripts in the repository (includes tests/, .github/, etc.)
    & $signingScript -CertificateThumbprint $CertificateThumbprint -Path $repoRoot
}
