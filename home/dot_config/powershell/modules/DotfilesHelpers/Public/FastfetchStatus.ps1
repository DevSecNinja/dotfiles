# fastfetch status cache helpers (Windows)
#
# The fastfetch banner carries extra status lines (currently the winget update
# count) that are far too slow to compute while a shell starts, so they are
# served from a small cache under %LOCALAPPDATA%\fastfetch-status:
#
#   updates.src     the line as written by status.ps1, with relative-time
#                   tokens still in it (@ago:<epoch>@ / @in:<epoch>@)
#   updates         the rendered line, which fastfetch reads with `cmd /c type`
#   .refreshed-at   marker file whose mtime dates the cache
#
# Relative times are deliberately NOT baked into the rendered file by the
# refresh: that would freeze "checked 5m ago" until the next refresh an hour
# later. Instead the tokens are expanded on every shell start, just before
# fastfetch runs. That is what Update-FastfetchStatusCache does, and it is why
# it lives in this module (which the profile imports anyway) rather than in
# status.ps1 (dot-sourcing that script costs ~60ms of profile load).
#
# This mirrors home/dot_config/fastfetch/executable_status.sh, which expands
# the same token syntax inline because its emit path is already a shell script.

function Get-FastfetchStatusCacheDir {
    <#
    .SYNOPSIS
    Path of the fastfetch status cache directory.

    .DESCRIPTION
    Honours FASTFETCH_STATUS_CACHE_DIR (used by tests and by anyone who wants
    the cache somewhere else), then %LOCALAPPDATA%, then ~/.cache as a last
    resort. Kept in sync with the same lookup in status.ps1.

    .EXAMPLE
    Get-FastfetchStatusCacheDir
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($env:FASTFETCH_STATUS_CACHE_DIR) { return $env:FASTFETCH_STATUS_CACHE_DIR }
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $HOME '.cache' }
    return (Join-Path $base 'fastfetch-status')
}

function Format-FastfetchStatusDuration {
    <#
    .SYNOPSIS
    Formats a number of seconds as a compact duration (45s, 12m, 3h, 2d).

    .PARAMETER Seconds
    Seconds to format. Negative values are treated as zero, which happens when
    a clock change leaves a cache timestamp slightly in the future.

    .EXAMPLE
    Format-FastfetchStatusDuration -Seconds 3600
    Returns '1h'.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [double]$Seconds
    )

    $s = [int][math]::Floor($Seconds)
    if ($s -lt 0) { $s = 0 }

    if ($s -lt 60) { return "${s}s" }
    if ($s -lt 3600) { return "$([int][math]::Floor($s / 60))m" }
    if ($s -lt 86400) { return "$([int][math]::Floor($s / 3600))h" }
    return "$([int][math]::Floor($s / 86400))d"
}

function Expand-FastfetchStatusToken {
    <#
    .SYNOPSIS
    Expands relative-time tokens in a cached status line.

    .DESCRIPTION
    Replaces the absolute epoch tokens written by the collectors with a bare
    duration phrase, so the surrounding wording stays in the collector:

      @ago:<epoch>@  ->  '5m ago'
      @in:<epoch>@   ->  'in 20m', or 'due' once the moment has passed

    Malformed tokens are left untouched rather than throwing, so a corrupt
    cache degrades to a slightly ugly line instead of breaking the banner.

    .PARAMETER Line
    The cached line to expand.

    .PARAMETER Now
    Current time as Unix epoch seconds. Defaults to the current clock.

    .EXAMPLE
    Expand-FastfetchStatusToken -Line 'checked @ago:1700000000@'
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Now', Justification = 'Captured by the regex MatchEvaluator closure below, which the analyzer cannot see into.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line,

        [Parameter()]
        [long]$Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    )

    $evaluator = {
        param($match)

        $kind = $match.Groups[1].Value
        $epoch = [long]$match.Groups[2].Value

        if ($kind -eq 'ago') {
            return ('{0} ago' -f (Format-FastfetchStatusDuration -Seconds ($Now - $epoch)))
        }
        if ($epoch -gt $Now) {
            return ('in {0}' -f (Format-FastfetchStatusDuration -Seconds ($epoch - $Now)))
        }
        return 'due'
    }

    return [regex]::Replace($Line, '@(ago|in):(\d+)@', $evaluator)
}

function Update-FastfetchStatusCache {
    <#
    .SYNOPSIS
    Renders the fastfetch status cache and refreshes it in the background when stale.

    .DESCRIPTION
    Call this from an interactive profile just before running fastfetch. It does
    two cheap things and never blocks:

      1. Expands every '<section>.src' in the cache into its rendered
         '<section>' sibling, so relative times are correct as of right now.
      2. When the cache is older than the TTL, starts a detached
         'status.ps1 refresh' so the NEXT shell sees fresh numbers. The current
         shell deliberately keeps showing the stale-but-instant values
         (stale-while-revalidate); a winget query takes tens of seconds and must
         never sit on the login path.

    Rendered files whose '.src' has disappeared are removed, which is how a
    section stops being displayed once it has nothing to report (fastfetch hides
    a 'command' module entirely when it prints nothing).

    Failures are swallowed: a missing status line is never a reason to break a
    shell.

    .PARAMETER SkipRefresh
    Only render; never spawn a background refresh. Used by status.ps1 itself
    after a refresh it has just completed.

    .PARAMETER CacheDir
    Cache directory. Defaults to Get-FastfetchStatusCacheDir.

    .PARAMETER StatusScript
    Path to status.ps1. Defaults to the copy next to this module in the chezmoi
    tree (~/.config/fastfetch/status.ps1).

    .EXAMPLE
    Update-FastfetchStatusCache
    Renders the cache and kicks off a background refresh when it is stale.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [switch]$SkipRefresh,

        [Parameter()]
        [string]$CacheDir,

        [Parameter()]
        [string]$StatusScript
    )

    if ($env:FASTFETCH_STATUS_DISABLE -eq '1') { return }

    if (-not $CacheDir) { $CacheDir = Get-FastfetchStatusCacheDir }
    if (-not (Test-Path -LiteralPath $CacheDir)) {
        # Nothing cached yet. Still worth spawning the first refresh.
        if (-not $SkipRefresh) { Start-FastfetchStatusRefresh -StatusScript $StatusScript }
        return
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    foreach ($src in @(Get-ChildItem -LiteralPath $CacheDir -Filter '*.src' -File -ErrorAction SilentlyContinue)) {
        $rendered = Join-Path $CacheDir ([System.IO.Path]::GetFileNameWithoutExtension($src.Name))
        try {
            $lines = @(Get-Content -LiteralPath $src.FullName -Encoding UTF8 -ErrorAction Stop |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { Expand-FastfetchStatusToken -Line $_ -Now $now })

            if (-not $PSCmdlet.ShouldProcess($rendered, 'Render fastfetch status section')) { continue }

            if ($lines.Count -eq 0) {
                Remove-Item -LiteralPath $rendered -Force -ErrorAction SilentlyContinue
                continue
            }

            Write-FastfetchStatusFile -Path $rendered -Lines $lines
        }
        catch {
            Write-Verbose "Could not render fastfetch status section '$rendered': $($_.Exception.Message)"
        }
    }

    # Drop rendered files whose source is gone (section no longer applies).
    # Scoped deliberately narrowly: '.tmp' files belong to an in-flight write in
    # this or another shell, and deleting one would break its Move-Item.
    foreach ($stale in @(Get-ChildItem -LiteralPath $CacheDir -File -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -notlike '*.src' -and
                    $_.Name -notlike '*.tmp' -and
                    $_.Name -notlike '.*'
                })) {
        if (-not (Test-Path -LiteralPath "$($stale.FullName).src")) {
            if ($PSCmdlet.ShouldProcess($stale.FullName, 'Remove orphaned fastfetch status section')) {
                Remove-Item -LiteralPath $stale.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if (-not $SkipRefresh -and (Test-FastfetchStatusStale -CacheDir $CacheDir)) {
        Start-FastfetchStatusRefresh -StatusScript $StatusScript
    }
}

function Test-FastfetchStatusStale {
    <#
    .SYNOPSIS
    True when the fastfetch status cache is missing or older than the TTL.

    .PARAMETER CacheDir
    Cache directory. Defaults to Get-FastfetchStatusCacheDir.

    .EXAMPLE
    Test-FastfetchStatusStale
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [string]$CacheDir
    )

    if (-not $CacheDir) { $CacheDir = Get-FastfetchStatusCacheDir }
    $stamp = Join-Path $CacheDir '.refreshed-at'
    if (-not (Test-Path -LiteralPath $stamp)) { return $true }

    $ttl = 3600
    $parsed = 0
    if ($env:FASTFETCH_STATUS_TTL -and
        [int]::TryParse($env:FASTFETCH_STATUS_TTL, [ref]$parsed) -and
        $parsed -gt 0) {
        $ttl = $parsed
    }

    $age = (Get-Date) - (Get-Item -LiteralPath $stamp).LastWriteTime
    return ($age.TotalSeconds -ge $ttl)
}

function Start-FastfetchStatusRefresh {
    <#
    .SYNOPSIS
    Starts a detached 'status.ps1 refresh' without blocking the caller.

    .DESCRIPTION
    The refresh queries winget, which takes tens of seconds, so it runs in a
    separate hidden process that nobody waits on. Its output is silenced inside
    the child as well as redirected, because no one drains those pipes: a chatty
    child would otherwise block once the pipe buffer filled.

    .PARAMETER StatusScript
    Path to status.ps1. Defaults to ~/.config/fastfetch/status.ps1.

    .EXAMPLE
    Start-FastfetchStatusRefresh
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [string]$StatusScript
    )

    if (-not $StatusScript) {
        $StatusScript = Join-Path $HOME '.config\fastfetch\status.ps1'
    }
    if (-not (Test-Path -LiteralPath $StatusScript)) {
        Write-Verbose "fastfetch status script not found at: $StatusScript"
        return
    }

    $psHost = (Get-Process -Id $PID).Path
    if (-not $psHost) {
        Write-Verbose 'Could not resolve the current PowerShell host executable.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($StatusScript, 'Start background fastfetch status refresh')) { return }

    try {
        $command = "& '{0}' refresh *>`$null" -f $StatusScript.Replace("'", "''")
        $info = [System.Diagnostics.ProcessStartInfo]::new($psHost)
        $info.Arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "{0}"' -f $command
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        [System.Diagnostics.Process]::Start($info) | Out-Null
    }
    catch {
        Write-Verbose "Could not start fastfetch status refresh: $($_.Exception.Message)"
    }
}

function Write-FastfetchStatusFile {
    <#
    .SYNOPSIS
    Atomically writes cache lines as UTF-8 without a BOM.

    .DESCRIPTION
    fastfetch reads the rendered file with `cmd /c type`, which copies bytes
    straight through, so a BOM would surface as stray characters in the banner.
    The write goes to a temporary file first so a reader never sees a half
    written line.

    .PARAMETER Path
    Destination file.

    .PARAMETER Lines
    Lines to write.

    .EXAMPLE
    Write-FastfetchStatusFile -Path $cache -Lines '6 update(s) available'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write fastfetch status file')) { return }

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $content = ($Lines -join "`r`n") + "`r`n"
    # Unique temp name: two shells starting at the same moment both render the
    # same section, and a shared '<name>.tmp' would let one process's Move-Item
    # pull the file out from under the other's.
    $tmp = '{0}.{1}.tmp' -f $Path, [System.IO.Path]::GetRandomFileName()
    try {
        [System.IO.File]::WriteAllText($tmp, $content, $encoding)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    }
    finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDB3snnCT1hmq7N
# mFVTpcohLN7IKnZ3KSAykR3b8WBz5qCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCALVjIrODxNwOIGZuWgsh4oG1OCmt8q13JiBMgiW2vBRTANBgkqhkiG
# 9w0BAQEFAASCAgCtt+vbYG77q4gtngna9dUWm5kWauK2ruqebzzgHa/FbiqS7h70
# RvLS8AML3J1xDb/Eg8l2gALNYOAeXJzUAPCIbrcbFjYvD9nu1tGZnwzC7kiVK6xq
# UvFwNWMuX0xcP/MeYEVG9DmK/neqy2XYLk27Zw815AAST+IIUNUWP4ScDQw+KZYT
# 45Ekrcc2Ow44CtNKXY5kbT2bUEpE53Jq4dTSb+FqyvIiX1N8tynh2pP3/ew4xvkd
# BhXq3wFoDGTH/wVIITxzGWJ+K8xhhc604FjZc85fHdwvpaouDSQCwsK50Okh2QxX
# zp7JAQ4/utgGyUPUcu+N+JKckeoBCaMuF6YnlBRGSPOb5Wdz/Bl0BJKxE5cRnouL
# zFjBLu+WynlO/o740Ms4OclrmGxRCZFOQ2/DQrPixW4ttcZUbiZVfgQEkeyRKUgZ
# Tg+UOER74eAhYhE5itMmjwKMfC6SZDusNnhQQgbqxXSnuC9m7HhEDYAymHqpNIjq
# cu+lfjR/clGr+wWoI0Ke5Qvpu6Z7MGoRXVQYO51AUqU2xjxrSQr1UzwbNJ1IBXAX
# R3JdLi1ezlIP8d/61q/CfjBApj7ozL3j5bVAHO/DXmiBME6keyIZ/P4D5FChfhNs
# IUrPKdSrvNBGPmxd2qpH7r7TFoz3O72l+kEMxM7OWa95enza+euATKi2+aGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MzAxNjM0NDRaMC8GCSqGSIb3DQEJBDEi
# BCAjg4qemmQpjiuLoxk1nJTT1T5uIQPd5SB5lIDNTSr91zANBgkqhkiG9w0BAQEF
# AASCAgBXOjWNPczw2jCl0KMJ6PdNEzcGjlp6EjAZ7qgiqEmI5HWD0K98/24+LFZv
# AIA34RAT8npfzwZkXhB4uc7GPWbdcGJG2TGT9mIoM/r0VQLMr8yrN73K611cZr0R
# 8kbyoIi2rnwWTaAzmlAxBs8nY8Ic3Q9ksz0g4PLjS0fq9lnuge0AVMm7bKOMrRTB
# 03o3qvqAxmJBE8S1bp4p6lYjuWZnE6tl0Hzp3dGz3mKNb+EBVMsawY+bfO1QC6LA
# bJLYZExXnj9md78qx5TF4DbaN5gr4Iha0wjzypndj6XiXGiWK+wQpfRgGPHBgZ5r
# LJeRCiWzUhZDYWLpwRfDS5SBhUBOjEHxisIgxHK7aqUinv+3rqYcHUXYCMMoPbkV
# Ot3FfEHQho51v++RSNs9q7EG1+0pPUIt/DQurQInN0NYdOcbHr8eZI+CdSM7XOI3
# s2Z0652IzdldsttfgJJxOKrP+RtP6OPR4sx3IDEv6PfQrNK9xlJkbUA7cFyV48GU
# FDhxKsDpz8rhenVx9f5NttFqKvZaZbN7U1lkjkp6pr5uC1eSKgew5t3ggJUk45IT
# LKwV+Wkd96acb2SsMco1TutM9o0ckOwDZVmcKmLX0hR3L4onamLgb//M63DsJ/42
# Td5Oqx0pNm3pZ411mwoZ/YHOMF8szsYWGFLvFdLw2zoi9dCtLA==
# SIG # End signature block
