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

    # Detect repository root robustly:
    # Prefer 'git rev-parse --show-toplevel' so the repo is found wherever it lives
    # (e.g. ~/.local/share/chezmoi, ~/projects/dotfiles, etc.), regardless of the
    # chezmoi source layout. Fall back to the parent of the source dir (which
    # matches the default 'home/' subdirectory layout used by this repo).
    $repoRoot = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Push-Location $chezmoiSourceDir
        try {
            $gitTopLevel = git rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $gitTopLevel) {
                # git returns forward slashes on Windows; normalise to native separators
                $repoRoot = (Resolve-Path -LiteralPath $gitTopLevel.Trim()).Path
            }
        }
        finally {
            Pop-Location
        }
    }

    if (-not $repoRoot) {
        $repoRoot = Split-Path -Parent $chezmoiSourceDir
    }

    $signingScript = Join-Path -Path $chezmoiSourceDir -ChildPath "dot_config\powershell\scripts\Sign-PowerShellScripts.ps1"

    if (-not (Test-Path $signingScript)) {
        Write-Host "Error: Sign-PowerShellScripts.ps1 not found at $signingScript" -ForegroundColor Red
        return
    }

    # Sign all PowerShell scripts in the repository (includes tests/, .github/, etc.)
    & $signingScript -CertificateThumbprint $CertificateThumbprint -Path $repoRoot
}

function Get-ChezmoiConfigTemplate {
    <#
    .SYNOPSIS
    Returns the path of the chezmoi config template, or $null when there is none.
    .DESCRIPTION
    Usually <source-path>/.chezmoi.yaml.tmpl. Private helper for Update-Chezmoi.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    # Guard and catch: with $ErrorActionPreference = 'Stop' (as under GitHub
    # Actions' `shell: pwsh`) a missing chezmoi would otherwise throw.
    if (-not (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue)) { return $null }

    $sourceDir = $null
    try { $sourceDir = & chezmoi source-path 2>$null }
    catch { return $null }
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($sourceDir)) { return $null }

    foreach ($ext in @('yaml', 'toml', 'json', 'jsonc', 'yml')) {
        $candidate = Join-Path $sourceDir ".chezmoi.$ext.tmpl"
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Test-ChezmoiConfigChanged {
    <#
    .SYNOPSIS
    Returns $true when `chezmoi init` should run.
    .DESCRIPTION
    Compares the SHA256 chezmoi recorded for the config template (its
    configState bucket, the same data behind its "config file template has
    changed" warning) with the template on disk. When either side cannot be
    determined this returns $true and lets init run: a redundant init is
    harmless, a skipped one is not.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $template = Get-ChezmoiConfigTemplate
    if (-not $template) { return $true }

    $state = $null
    try { $state = & chezmoi state get --bucket=configState --key=configState 2>$null }
    catch { return $true }
    if ($LASTEXITCODE -ne 0 -or -not $state) { return $true }

    $stored = $null
    try {
        $stored = ($state | ConvertFrom-Json).configTemplateContentsSHA256
    }
    catch {
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($stored)) { return $true }

    $actual = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash
    if ([string]::IsNullOrWhiteSpace($actual)) { return $true }

    return ($stored -ne $actual)
}

function Get-ChezmoiExpectedBranch {
    <#
    .SYNOPSIS
    The branch the chezmoi source repository should be on.

    .DESCRIPTION
    Honours CHEZMOI_UP_BRANCH, else asks git which branch origin's HEAD points
    at (so a repository that renames its default branch keeps working), else
    falls back to main. Private helper for Update-Chezmoi.

    .PARAMETER SourceDir
    The chezmoi source directory.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$SourceDir)

    if (-not [string]::IsNullOrWhiteSpace($env:CHEZMOI_UP_BRANCH)) {
        return $env:CHEZMOI_UP_BRANCH
    }

    $head = (& git -C $SourceDir symbolic-ref --short -q refs/remotes/origin/HEAD 2>$null | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($head)) {
        return ($head -replace '^origin/', '')
    }

    return 'main'
}

function Get-ChezmoiBranchConfirmation {
    <#
    .SYNOPSIS
    Ask a yes/no question, defaulting to "no" when nobody can answer.

    .DESCRIPTION
    Non-interactive sessions always answer "no" so an automated run is warned
    but never blocked. CHEZMOI_UP_ASSUME_YES=1 answers yes,
    CHEZMOI_UP_ASSUME_NO=1 answers no. Private helper for Update-Chezmoi.

    .PARAMETER Message
    The question to ask.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter(Mandatory = $true)][string]$Message)

    if ($env:CHEZMOI_UP_ASSUME_YES -eq '1') { return $true }
    if ($env:CHEZMOI_UP_ASSUME_NO -eq '1') { return $false }
    if (-not [Environment]::UserInteractive) { return $false }
    if ([Console]::IsInputRedirected) { return $false }

    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^\s*(y|yes)\s*$')
}

function Test-ChezmoiSourceBranch {
    <#
    .SYNOPSIS
    Warn when the chezmoi source repository is off its default branch, and
    offer to switch and pull.

    .DESCRIPTION
    `chezmoi update` pulls whichever branch is checked out, so a forgotten
    feature branch would otherwise be applied to the machine silently.

    Always returns without failing: working on a feature branch is a legitimate
    way to test dotfiles changes, so this warns and offers rather than blocking
    the run. Private helper for Update-Chezmoi.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive helper; progress output is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Prompts for the branch switch itself; -WhatIf would be redundant.')]
    [CmdletBinding()]
    param()

    if ($env:CHEZMOI_UP_SKIP_BRANCH_CHECK -eq '1') { return }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return }

    try { $sourceDir = (& chezmoi source-path 2>$null | Out-String).Trim() }
    catch { return }
    if ([string]::IsNullOrWhiteSpace($sourceDir) -or -not (Test-Path -LiteralPath $sourceDir)) { return }

    # A source directory that is not a git checkout has no branch to be wrong.
    $null = & git -C $sourceDir rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) { return }

    $expected = Get-ChezmoiExpectedBranch -SourceDir $sourceDir
    $current = (& git -C $sourceDir symbolic-ref --short -q HEAD 2>$null | Out-String).Trim()

    if ($current -eq $expected) { return }

    $where = if ([string]::IsNullOrWhiteSpace($current)) { 'detached HEAD' } else { "'$current'" }
    if ([string]::IsNullOrWhiteSpace($current)) {
        Write-Host "[WARN] Source repository is in detached HEAD state, not on '$expected'." -ForegroundColor Yellow
    }
    else {
        Write-Host "[WARN] Source repository is on '$current', not '$expected'." -ForegroundColor Yellow
    }
    Write-Host '[WARN] chezmoi update pulls whichever branch is checked out.' -ForegroundColor Yellow

    if (-not (Get-ChezmoiBranchConfirmation -Message "Switch to '$expected' and pull?")) {
        Write-Host "==> Staying on $where."
        return
    }

    # Switching with uncommitted changes would either fail or drag the changes
    # onto the default branch; neither is something to do behind the user's back.
    $dirty = (& git -C $sourceDir status --porcelain 2>$null | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($dirty)) {
        Write-Error 'Source repository has uncommitted changes; commit or stash them first.' -ErrorAction Continue
        Write-Host "==> Continuing on $where."
        return
    }

    Write-Host "==> Switching to '$expected'" -ForegroundColor Blue
    & git -C $sourceDir checkout $expected
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not check out '$expected'; continuing on $where." -ErrorAction Continue
        return
    }

    # --ff-only: never create a merge commit in the dotfiles source behind the
    # user's back. A diverged branch is reported instead.
    & git -C $sourceDir pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Could not fast-forward '$expected'; resolve it manually." -ErrorAction Continue
        return
    }
}

function Update-Chezmoi {
    <#
    .SYNOPSIS
    Pull, re-init when the config template changed, then apply, stopping on the
    first failure.

    .DESCRIPTION
    Replaces the usual `chezmoi update; chezmoi init; chezmoi apply` dance.
    Each step is a gate: if one fails the run stops there, so a failed pull can
    never be followed by an apply of half-updated source.

    The steps are:
      0. Branch guard - warn when the source repo is not on its default branch
         (usually main) and offer to switch and pull.
      1. `chezmoi update --apply=false` - pull the source repo only. Applying
         here would use the OLD config, which breaks when the pull introduces a
         template variable the current config does not have yet.
      2. `chezmoi init` - only when the config template actually changed.
         Skipping is logged.
      3. `chezmoi apply` - apply with the freshly generated config.

    .PARAMETER ForceInit
    Run `chezmoi init` even when the config template is unchanged.

    .EXAMPLE
    Update-Chezmoi
    Pull, conditionally re-init, and apply.

    .EXAMPLE
    czu -ForceInit
    Same, but always regenerate the config file.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Interactive helper; progress output is the point.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Thin wrapper around chezmoi, which owns its own --dry-run/--force flags.')]
    [CmdletBinding()]
    param(
        [Alias('f')]
        [switch]$ForceInit
    )

    if (-not (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Error 'chezmoi is not installed or not in PATH' -ErrorAction Continue
        return
    }

    Test-ChezmoiSourceBranch

    Write-Host '==> Pulling the source repository' -ForegroundColor Blue
    & chezmoi update --apply=false
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'chezmoi update failed; not continuing to init/apply' -ErrorAction Continue
        return
    }

    $runInit = $false
    $reason = ''
    if ($ForceInit) {
        $runInit = $true
        $reason = 'forced'
    }
    elseif (Test-ChezmoiConfigChanged) {
        $runInit = $true
        $reason = 'config template changed'
    }

    if ($runInit) {
        Write-Host "==> Regenerating the config file ($reason)" -ForegroundColor Blue
        & chezmoi init
        if ($LASTEXITCODE -ne 0) {
            Write-Error 'chezmoi init failed; not continuing to apply' -ErrorAction Continue
            return
        }
    }
    else {
        Write-Host '==> Config template unchanged, skipping chezmoi init'
    }

    Write-Host '==> Applying' -ForegroundColor Blue
    & chezmoi apply
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'chezmoi apply failed' -ErrorAction Continue
        return
    }

    Write-Host '[OK] Dotfiles are up to date' -ForegroundColor Green
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCK2iv/V9j/qTls
# +Whaa/nCP60dwy/QkdNBccKKAkNH56CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
# p05/1ElTgWD0MA0GCSqGSIb3DQEBCwUAMCMxITAfBgNVBAMMGEplYW4tUGF1bCB2
# YW4gUmF2ZW5zYmVyZzAeFw0yNjAxMTQxMjU3MjBaFw0zMTAxMTQxMzA2NDdaMCMx
# ITAfBgNVBAMMGEplYW4tUGF1bCB2YW4gUmF2ZW5zYmVyZzCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMm6cmnzWkwTZJW3lpa98k2eQDQJB6Twyr5U/6cU
# bXWG2xNCGTZCxH3a/77uGX5SDh4g/6x9+fSuhkGkjVcCmP2qpfeHOqafOByrzg6p
# /oI4Zdn4eAHRdhFV+IDmP68zaLtG9oai2k4Ilsc9qINOKPesVZdJd7sxtrutZS8e
# UqBmQr3rYD96pBZXt2YpJXmqSZdS9KdrboVms6Y11naZCSoBbi+XhbyfDZzgN65i
# NZCTahRj6RkJECzU7FXsV4qhuJca4fGHue2Lc027w0A/ZxZkbXkVnTtZbP3x0Q6v
# wkH0r3lfeRcFtKisHKFfDdsIlS+H9cQ8u2NMNWK3375By4yUnQm1NJjVFDZNAZI/
# A/Os3DpRXGyW8gxlSb+CGqHUQU0+YtrSuaXaLc5x0K+QcBmNBzCB/gQArY95g5dn
# rO3m2+XWhHmP6zP/fBMZW1BPLXTFbK/tXY/rFuWZ77MRka12Enu8EbhzK+Mfn00m
# ts6TL7AtV6qksjCc+aJPhgPVABMCDkD4QXHvENbE8s99LrjgsJwSyalOxgWovQl+
# 4r4DbReaHfapy4+j/Rxba65YQBSN35dwWqhb8YxyzCEcJ7q1TTvoVEntV0SeC8Lh
# 4rhqdHhyigZUSptw6LMry3bEdDrCAJ8FeW1LdTb+00bayq/J4RTZd4OLiIf07mot
# KTmJAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUDt+a1J2KwjQ4CPd2E5gJ3OpVld4wDQYJKoZIhvcNAQELBQAD
# ggIBAFu1W92GGmGvSOOFXMIs/Lu+918MH1rX1UNYdgI1H8/2gDAwfV6eIy+Gu1MK
# rDolIGvdV8eIuu2qGbELnfoeS0czgY0O6uFf6JF1IR/0Rh9Pw1qDmWD+WdI+m4+y
# gPBGz4F/crK+1L8wgfV+tuxCfSJmtu0Ce71DFI+0wvwXWSjhTFxboldsmvOsz+Bp
# X0j4xU6qAsiZK7Tp0VrrLeJEuqE4hC2sTWCJJyP7qmxUjkCqoaiqhci6qSvpg1mJ
# qM4SYkE0FE59z+++4m4DiiNiCzSr/O3uKsfEl2MwZWoZgqLKbMC33I+e/o//EH9/
# HYPWKlEFzXbVj2c3vCRZf2hZZuvfLDoT7i8eZGg3vsTsFnC+ZXKwQTaXqS++q9f3
# rDNYAD+9+GwVyHqVVqwgSME91OgbJ6qfx7H/5VqHHhoJiifSgPiIOSyhvGu9JbcY
# mHkZS3h2P3BU8n/nuqF4eMcQ6LeZDsWCzvHOaHKisRKzSX0yWxjGygp7trqpIi3C
# A3DpBGHXa9r1fwleRfWUeyX/y7pJxT0RRlxNDip4VhK0RRxmE6PL0cq8i92Qs7HA
# csVkGkrIkSYUYhJxemehXwBnwJ1PfDqjvZVpjQdUeP1TTDSNrR3EqiVP5n+nWRYV
# NkoMe75v2tBqXHfq05ryGO9ivXORcmh/MFMgWSR9WYTjZRy3MIIFjTCCBHWgAwIB
# AgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJV
# UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
# Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIw
# ODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Y
# q3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lX
# FllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxe
# TsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbu
# yntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I
# 9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg
# Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse
# 5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
# Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwh
# HbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/
# Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwID
# AQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM
# 3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYD
# VR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+
# MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUA
# A4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSI
# d229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7U
# z9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxA
# GTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAID
# yyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW
# /VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMi
# DDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0
# MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxC
# qvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qc
# hUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbD
# hAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pn
# YJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI
# 2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS
# 638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZx
# st7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17y
# Vp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTn
# YCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4
# yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ
# 7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5j
# cnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0
# pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN
# 2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a
# +Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7p
# GdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZ
# ruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspI
# HBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku
# /qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZ
# Zd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeu
# kcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA
# 6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvF
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQRqwt
# Esae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjn
# i6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNkeECqVQ+3bzWYesFtkepErvUSbf+EI
# YLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4vEjoT1FpS54dNApZfKY61HAldytx
# NM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ
# 0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPbcNmA98Os
# kkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3NR39iTTFS+ENTqW8m6THuOmHHjQN
# C3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETkVWz0dVVZw7knh1WZXOLHgDvundrA
# tuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1p6llN3QgshRta6Eq4B40h5avMcpi
# 54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uck5Wggn8O2klETsJ7u8xEehGifgJY
# i+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYRNMmSF3voIgMFtNGh86w3ISHNm0Ia
# adCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNA
# ciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+wtJPBVBaj
# YfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5
# qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy1lNM4kze
# kd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr
# 15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwSBXkZagHL
# hFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCEH1Y58678IgmfORBPC1JKkYaEt2Od
# Dh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL+66Gp3CS
# BXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUtwq1qmcwbdUfcSYCn+OwncVUXf53V
# JUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5SlfYxJ7La54i71McVWRP66bW+yER
# NpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn5PhDBf3Froguzzhk++ami+r3Qrx5
# bIbY3TVzgiFI7Gq3zWcxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCBxYdmvKzjK6ePaRgi6nqQRLyM+Lyruq5ysaGSvc/x31TANBgkqhkiG
# 9w0BAQEFAASCAgA4t0Dg1Xun0n6ek/eJ1xr1dgY6eKtQ1znwpEaGpSIsg6B+30Kg
# 98GNgff1HVQDkRMZiUvB68+ic/Ft6loBhBygF05/xmLDS/R6ZTAli780C+w64etu
# bX9b0WCcirvpjehxKQokL8kTzCnaHVFp9k3Q24lyvVlza2bm4lSLUCmZM0kGC6+l
# /qAff9kdLozhMY4dmtZ4GpOK2MkZQLt+TH0Tz/PyyhA49EmpBtx8BPwOn4VVNPlK
# qXcnSEpYFFCPEwGgEwSDxUKdI6Cr+2m3JDdunepSGSvKc4AKs8fzFzSmQxK8ZJGW
# +eHkSJH63vUgv6ynFezjEBWUkdq+DaQlWb4BXC0RdeZZxz5OfD5JbPfICg8HJgSx
# B7DHTSCiY3K4Bqor4P0LJ7doCfy6qHJ0m/YSnIYjlxtsPfZadFTSEP6ZJxhbKIsY
# dKnKnTKF7edDHfq1GvD/ffl0pGMocIh3mH/RshdzzydGYZ0jQI1IxEqW4GlJ80ug
# 5VDKGT4RKwgbakq06+wf4ENFEU106tYItSZiQuohEX+73wsd8IYinQK7KjibmVLZ
# V/E7vB/WbZX5sUj24pu7cdQta3Y9Zy/gCgpqwnK8/OsYpSXafiB3rLQ50IFVxuuZ
# hDP7oXVG8NYRRrO8QUyMImkrjCqqQ3169JuivpU/XR6U+fppmcBOF88zqaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjgxNDAwNDlaMC8GCSqGSIb3DQEJBDEi
# BCCS61KEyskruSiG+0COrhIq3cBiIHIx3NmSKY+A/yJlaDANBgkqhkiG9w0BAQEF
# AASCAgB6vNXZ9M91C6H4fVtszfYKzwX4GFB1NUodYm0ZH2BIrDjcPJAipmnz25Nb
# DqKQwgkdkNJ77pW/9hjhPbAx62LjESkHN0v7SXAl17U402ZTU13bZEXvInpKEnSV
# WvLGB+8/JYvLY/sL7mqEz9t+SJCr8Str9qQkX9opNb3IvwnFe9t3DqgnVXIo2lPc
# SOYjxbz9USfAdJmTBoHm2ZWiXntQa/Y9yrWCHt4asH9vrn6MwW14nhyQojeADWOy
# haHgHSpwyVbCs/e3mZxkatLilLBtITup9TNxfMu5LuHDjCEhoDyWkjwxLTxtiQus
# XfrCbV95hG5IkXbn6Lp9zVGEOBtiE2dJlZeepCPosHL0sGQnCeXNHftfu4i1i4ly
# Hx/8rUJk7jKZwYhDNZv0n+zRGOBc0xkjhAt5NSG9RprswKErhOxmi94mfjEwFjF1
# HLHUFEZaZhtVv8OSH62/moYRMKljah1ZtGo8lhH6KIgwUlP0C+LQtc2ap/4hY6lD
# MkYVTTRyYjwUj/deUURR6GAh2w8uvtZ42y65GYderu5HjoopkCZ9ORHHDp7PM5fl
# m9MLe33Vk/7WhYrnSlHERqpnveKAuPY9agzLVFaGLOyVLou8IU3x9H6hspkFhWHV
# 18L0dWOijO1nv4xj2OI+Jv6iRTjDo5/9xrir4B7CnjreVkPfig==
# SIG # End signature block
