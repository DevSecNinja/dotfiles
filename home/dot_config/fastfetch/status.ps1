<#
.SYNOPSIS
    Cached system status lines for fastfetch on Windows.

.DESCRIPTION
    Windows counterpart of dot_config/fastfetch/status.sh. It emits short,
    self-hiding status lines that fastfetch renders as extra modules; today that
    is the number of available winget package updates.

    Speed is the priority: checking winget for updates takes tens of seconds, so
    it must never happen on the login path. The script therefore uses the same
    stale-while-revalidate strategy as the Unix version:

      * 'refresh' does the expensive work and writes a tiny cache file.
      * The cache file is printed on login. On Windows fastfetch reads it
        directly with `cmd /c type` (see config.jsonc.tmpl) so no PowerShell
        process is started at all; the 'updates' command here does the same
        thing and exists for scripting and tests.
      * The PowerShell profile spawns a detached 'refresh' when the cache is
        older than the TTL, so the next login shows fresh numbers.

    Each section is stored twice: '<name>.src' keeps relative times as absolute
    epoch tokens (@ago:<epoch>@), and '<name>' is the rendered copy fastfetch
    reads. Baking "checked 5m ago" straight into the rendered file would freeze
    it until the next refresh an hour later, so the tokens are expanded on every
    shell start by Update-FastfetchStatusCache (DotfilesHelpers), which the
    profile already imports. This script calls the same function after a refresh
    so a manual 'refresh' also leaves a correctly rendered cache behind.

    fastfetch hides a `command` module entirely when it prints nothing, so a
    host with no pending updates simply does not get an "Updates" line.

.PARAMETER Command
    updates   Print the cached "updates available" line (may be empty).
    refresh   Recompute the cache (respects a single-runner lock).
    clear     Remove the cache.
    help      Show this help.

.PARAMETER Force
    With 'refresh': take over a refresh lock held by another run.

.EXAMPLE
    status.ps1 updates

.EXAMPLE
    status.ps1 refresh -Force

.NOTES
    Environment:
      FASTFETCH_STATUS_TTL         Cache lifetime in seconds (default 3600)
      FASTFETCH_STATUS_DISABLE     When set to 1, all sections print nothing
      FASTFETCH_STATUS_CACHE_DIR   Cache directory (default %LOCALAPPDATA%\fastfetch-status)

    Never requires elevation. 'refresh' does reach the network (winget queries
    its sources); the emit path never does.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('updates', 'refresh', 'clear', 'help')]
    [string]$Command = 'help',

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# U+1F4E6 PACKAGE and U+00B7 MIDDLE DOT. Built from their code points because
# .ps1 files in this repo must stay ASCII (see .github/copilot-instructions.md):
# PowerShell 5.1 reads unsigned scripts without a BOM as ANSI, which corrupts
# literal non-ASCII characters.
$script:PackageIcon = [char]::ConvertFromUtf32(0x1F4E6)
$script:MiddleDot = [char]::ConvertFromUtf32(0x00B7)

function Get-StatusCacheDir {
    if ($env:FASTFETCH_STATUS_CACHE_DIR) { return $env:FASTFETCH_STATUS_CACHE_DIR }
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.cache' }
    return (Join-Path $base 'fastfetch-status')
}

function Get-StatusTtl {
    $ttl = 3600
    $parsed = 0
    if ($env:FASTFETCH_STATUS_TTL -and
        [int]::TryParse($env:FASTFETCH_STATUS_TTL, [ref]$parsed) -and
        $parsed -gt 0) {
        $ttl = $parsed
    }
    return $ttl
}

function Test-StatusCacheStale {
    <#
    .SYNOPSIS
    True when the cache is missing or older than the TTL.
    #>
    [CmdletBinding()]
    param()

    $stamp = Join-Path (Get-StatusCacheDir) '.refreshed-at'
    if (-not (Test-Path -LiteralPath $stamp)) { return $true }

    $age = (Get-Date) - (Get-Item -LiteralPath $stamp).LastWriteTime
    return ($age.TotalSeconds -ge (Get-StatusTtl))
}

function Get-WingetUpdateCount {
    <#
    .SYNOPSIS
    Number of packages with an available winget upgrade, or $null when winget
    is not usable on this host.
    #>
    [CmdletBinding()]
    param()

    # Preferred path: the WinGet PowerShell module returns objects, so no
    # locale-dependent table parsing is involved.
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            $outdated = @(Get-WinGetPackage -ErrorAction Stop |
                    Where-Object { $_.IsUpdateAvailable })
            return $outdated.Count
        }
        catch {
            Write-Verbose "Microsoft.WinGet.Client failed, falling back to winget.exe: $($_.Exception.Message)"
        }
    }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return $null }

    try {
        $output = & winget upgrade --include-unknown --accept-source-agreements 2>&1 | Out-String
    }
    catch {
        return $null
    }

    return (Measure-WingetTableRow -Output $output)
}

function Measure-WingetTableRow {
    <#
    .SYNOPSIS
    Count package rows in `winget upgrade` table output.

    .DESCRIPTION
    Best-effort fallback used only when the WinGet PowerShell module is
    unavailable. Rows come after the dashed header separator and are padded
    into columns, so they always contain a run of two or more spaces; the
    localized summary and warning sentences that follow the table do not.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Output
    )

    $lines = $Output -split "`r?`n"
    $separator = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^-{5,}\s*$') { $separator = $i; break }
    }
    if ($separator -lt 0) { return 0 }

    $rows = 0
    for ($i = $separator + 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line -match '^-{5,}\s*$') { continue }
        if ($line -notmatch '\S {2,}\S') { continue }
        $rows++
    }
    return $rows
}

function Get-UpdatesLine {
    <#
    .SYNOPSIS
    The "N update(s) available (winget)" line, or an empty string.

    .DESCRIPTION
    The "checked" suffix is emitted as an absolute epoch token rather than a
    formatted duration, so it keeps counting up on every shell start instead of
    freezing at the value it had when the cache was written.
    #>
    [CmdletBinding()]
    param()

    $count = Get-WingetUpdateCount
    if ($null -eq $count -or $count -le 0) { return '' }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    return ('{0} {1} update(s) available (winget) {2} checked @ago:{3}@' -f
        $script:PackageIcon, $count, $script:MiddleDot, $now)
}

function Write-StatusSection {
    <#
    .SYNOPSIS
    Atomically write a cache section source, or remove it when the value is empty.

    .DESCRIPTION
    Writes '<name>.src' (with relative-time tokens intact). The rendered
    '<name>' file that fastfetch reads is produced from it by
    Update-FastfetchStatusCache.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $cacheDir = Get-StatusCacheDir
    $file = Join-Path $cacheDir "$Name.src"
    if (-not $PSCmdlet.ShouldProcess($file, 'Write status section')) { return }

    if ([string]::IsNullOrEmpty($Value)) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $cacheDir $Name) -Force -ErrorAction SilentlyContinue
        return
    }

    # UTF-8 without BOM: `cmd /c type` copies the bytes straight through to
    # fastfetch, so a BOM would show up as stray characters in the banner.
    # The temp name is unique so a concurrent writer cannot claim it.
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $tmp = '{0}.{1}.tmp' -f $file, [System.IO.Path]::GetRandomFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, ($Value + "`r`n"), $encoding)
        Move-Item -LiteralPath $tmp -Destination $file -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-StatusRender {
    <#
    .SYNOPSIS
    Expand the cached tokens into the rendered files fastfetch reads.

    .DESCRIPTION
    Rendering lives in the DotfilesHelpers module because the PowerShell profile
    imports it anyway, so expanding tokens on every shell start is free there
    (dot-sourcing this script instead would add ~60ms to profile load). This
    script imports the module so a manual 'refresh' also leaves a correctly
    rendered cache behind; when the module is missing the rendered files are
    simply left to the next shell start.
    #>
    [CmdletBinding()]
    param()

    try {
        if (-not (Get-Command Update-FastfetchStatusCache -ErrorAction SilentlyContinue)) {
            $modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'powershell\modules\DotfilesHelpers'
            if (-not (Test-Path -LiteralPath $modulePath)) {
                Write-Verbose "DotfilesHelpers not found at '$modulePath'; skipping render."
                return
            }
            Import-Module $modulePath -DisableNameChecking -ErrorAction Stop
        }
        Update-FastfetchStatusCache -SkipRefresh
    }
    catch {
        Write-Verbose "Could not render the status cache: $($_.Exception.Message)"
    }
}

function Invoke-StatusEmit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)

    if ($env:FASTFETCH_STATUS_DISABLE -eq '1') { return }

    $file = Join-Path (Get-StatusCacheDir) $Name
    if (-not (Test-Path -LiteralPath $file)) { return }

    Get-Content -LiteralPath $file -Encoding UTF8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_ }
}

function Invoke-StatusRefresh {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$Force)

    $cacheDir = Get-StatusCacheDir
    if (-not $PSCmdlet.ShouldProcess($cacheDir, 'Refresh fastfetch status cache')) { return }

    New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null

    # Single-runner lock. Creating the file with CreateNew is atomic at the OS
    # level, so two concurrent refreshes cannot both win. A lock older than ten
    # minutes was left behind by an interrupted refresh and is reclaimed.
    $lock = Join-Path $cacheDir '.refresh.lock'
    $handle = $null
    try {
        $handle = [System.IO.File]::Open($lock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    }
    catch {
        $handle = $null
    }

    if (-not $handle -and (Test-Path -LiteralPath $lock)) {
        $lockAge = (Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime
        if ($Force -or $lockAge.TotalSeconds -gt 600) {
            Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
            try {
                $handle = [System.IO.File]::Open($lock, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
            }
            catch {
                $handle = $null
            }
        }
    }

    if (-not $handle) {
        Write-Verbose 'Another refresh is already running; skipping.'
        return
    }

    try {
        Write-StatusSection -Name 'updates' -Value (Get-UpdatesLine)
        $stamp = Join-Path $cacheDir '.refreshed-at'
        [System.IO.File]::WriteAllText($stamp, '')
        Invoke-StatusRender
    }
    finally {
        $handle.Dispose()
        Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
    }
}

function Show-StatusUsage {
    @'
Usage: status.ps1 <command> [-Force]

Commands:
  updates          Print cached "updates available" line (may be empty)
  refresh          Recompute the cache (respects a single-runner lock)
  clear            Remove the cache
  help             Show this help

Options:
  -Force           With refresh: take over a lock held by another run

Environment:
  FASTFETCH_STATUS_TTL         Cache lifetime in seconds (default 3600)
  FASTFETCH_STATUS_DISABLE     When set to 1, all sections print nothing
  FASTFETCH_STATUS_CACHE_DIR   Cache directory (default %LOCALAPPDATA%\fastfetch-status)
'@
}

# Dot-sourcing (tests) loads the functions without running a command.
if ($MyInvocation.InvocationName -eq '.') { return }

switch ($Command) {
    'updates' { Invoke-StatusEmit -Name 'updates' }
    'refresh' { Invoke-StatusRefresh -Force:$Force }
    'clear' { Remove-Item -LiteralPath (Get-StatusCacheDir) -Recurse -Force -ErrorAction SilentlyContinue }
    default { Show-StatusUsage }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCswV346444yhF7
# 3idGoP2YAl7Xan3hjz4ZwH20r9dDcaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDgGKYOfK6RAuvDE3vr6SlgUWDI6iuaSWar1v4Xzg5qxDANBgkqhkiG
# 9w0BAQEFAASCAgCpMnjk/IldO/+mnbePs62fYfjvN+2anIdWcpkR1Ps0bQAjERui
# 68sSDWAGV233PM8V6aKYbivgguMq/sgBSxYC+sqLkolfq6URZbCgoVSEdA8NWP3f
# 0C7PQoTcJn+SR9JQv0bl8L8kZ54JqBnx21vbbH4HQ1KAXQXL/bu7F6Gg2KUXYyOA
# T3mlBwAzr3G8s1spnNzBMhAU9+gClF3NX/8SeWXo/F2EMNKmwXtQOTaPTPAKTaSU
# PoUFkvCTD1D/udkyT0trbK0OTbTnADuZ/+RRKvEbmE9eFMnT/Ph8pnSyksZkO6LQ
# 6+0HuIbOse2ulZE8tMPYAfNfBwOOejdMmC77kJKvEQAEsc4KF0hpjv2FNe9fDA9S
# h+tnNYi1yTH+sA7ePKzM7ObisHvBX3Hq2nuj/2D/ivIp3xO9nZ9Mk6ku3nZWYXPA
# 6WZwjyHe8ROTO7ZDFZrWsFPV6z59t4KNK1j6yuS0UOGMMZ4Ni+2JJ46krfGSE2Jb
# 1dUawH0DbMOpx32oL4TidBmAe+HkWM8OtKqFJPpnti8bFzJDL3Zj4L+FputMy9Vv
# tgkYLzjYlD5K8aK/VVdoCTh+WNlbrFmdhleCucX24ercFtbO1GiNBcgQComHmtCN
# kLlJPFTsvf9Z7UICoFRtWr+S/9SVa0p0T/NVzAGYDEXY1zg6ZNWzmwHplaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MzAxOTIwNDdaMC8GCSqGSIb3DQEJBDEi
# BCBS8tP5Q03FXz5NrfrZmaLxFXV7q47/S7Sh+t17PgIJJjANBgkqhkiG9w0BAQEF
# AASCAgB0Dy0FQAdQLg07xqUzZSqoL9mXo2p2Mxhny7uLLlZYInZ0DGu9mEl52ZmA
# EbRqZH+VapbxK5I2vLjltT4gGI1/F+dnVtJOCJm9zT7dSYzhrBCrWoH2vurKYFyz
# zzJ9PVV7tzHsLsxRjQu/fRhmVGp50hTXZLgL+zLA/49utbL9H9o/LPfmOZQczfkX
# kQN4r7bgE241jr9O2D9GP/w+g2wNk4akHhlNrhF2tPTPeqxOyF7u6M/vteE1Kddx
# lnVJmEpn4CvlzvIaAt4brbW5zvGF4gKuCF6NtjzTdk98yHpEPfpSva8X50qhKsKH
# hV80iLXeFU5krtzu8yMEvc821Lsr3DOCwqo2xre1Iy0iDBHqyRyIgmCAkLcAritO
# Bwkmsd8jvLAfehSWCsuvMSEJl5YQRjSs5k61SH4V7QIrg0wnuRy3KUzCJvUh14UG
# xkngEmALHcxoVuPD6cLeHBavWeYqFjFFo+kHtLFll6EcEz27e768OX6ULddA+BBz
# V3AEXPqzLESGM5rH6RmJvcCae4pBbjvn4SJs/KMna8BBmOjLShb+nzvcOKCWydkG
# YeqSENFMdaaDN79TpIKQxFVYCnJKOvKXB16nu5IWsPfpMtNkBsJX0900JAsAXQQM
# dFsZZBnUmkLyCXLFb9yhp/3LFuOctpWbhTME4ajrAV2s+rybEg==
# SIG # End signature block
