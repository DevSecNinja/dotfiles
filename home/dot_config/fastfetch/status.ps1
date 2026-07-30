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

# U+1F4E6 PACKAGE. Built from its code point because .ps1 files in this repo
# must stay ASCII (see .github/copilot-instructions.md): PowerShell 5.1 reads
# unsigned scripts without a BOM as ANSI, which corrupts literal emoji.
$script:PackageIcon = [char]::ConvertFromUtf32(0x1F4E6)

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
    #>
    [CmdletBinding()]
    param()

    $count = Get-WingetUpdateCount
    if ($null -eq $count -or $count -le 0) { return '' }
    return ('{0} {1} update(s) available (winget)' -f $script:PackageIcon, $count)
}

function Write-StatusSection {
    <#
    .SYNOPSIS
    Atomically write a cache section, or remove it when the value is empty.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Value
    )

    $file = Join-Path (Get-StatusCacheDir) $Name
    if (-not $PSCmdlet.ShouldProcess($file, 'Write status section')) { return }

    if ([string]::IsNullOrEmpty($Value)) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        return
    }

    # UTF-8 without BOM: `cmd /c type` copies the bytes straight through to
    # fastfetch, so a BOM would show up as stray characters in the banner.
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $tmp = "$file.tmp"
    [System.IO.File]::WriteAllText($tmp, ($Value + "`r`n"), $encoding)
    Move-Item -LiteralPath $tmp -Destination $file -Force
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
