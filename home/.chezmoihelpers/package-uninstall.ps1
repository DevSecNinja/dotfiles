function Uninstall-WinGetPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9.+_-]*$')]
        [string]$Id
    )

    if (-not $PSCmdlet.ShouldProcess($Id, 'Uninstall WinGet package')) {
        return
    }

    # WinGet reports absence with a specific HRESULT, not a successful exit.
    $PSNativeCommandUseErrorActionPreference = $false
    $notInstalled = -1978335212 # 0x8A150014: APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND
    $output = winget uninstall --id $Id --exact --all-versions --silent --accept-source-agreements --disable-interactivity 2>&1
    if ($LASTEXITCODE -eq $notInstalled) {
        Write-Host "[SKIP] WinGet package '$Id' is not installed"
        return
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Could not uninstall WinGet package '$Id' (exit code $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }

    $output = winget list --id $Id --exact --accept-source-agreements --disable-interactivity 2>&1
    if ($LASTEXITCODE -eq 0) {
        throw "WinGet package '$Id' is still installed after uninstalling."
    }
    if ($LASTEXITCODE -ne $notInstalled) {
        throw "Could not verify removal of WinGet package '$Id' (exit code $LASTEXITCODE): $($output -join [Environment]::NewLine)"
    }
    Write-Host "[OK] Uninstalled WinGet package '$Id'" -ForegroundColor Green
}
