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
    foreach ($stale in @(Get-ChildItem -LiteralPath $CacheDir -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike '*.src' -and $_.Name -notlike '.*' })) {
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
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, $content, $encoding)
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}
