# Windows Terminal settings utilities
#
# Windows Terminal owns settings.json (it rewrites the file at runtime), and the
# config differs from machine to machine. Rather than managing the whole file in
# git - which overwrites local changes and breaks per-machine setups - these
# helpers parse the existing settings.json and surgically patch only the single
# value being changed, leaving everything else untouched.

function Remove-JsonComment {
    <#
    .SYNOPSIS
    Strips // and /* */ comments from a JSONC string in a string-aware way.

    .DESCRIPTION
    Windows PowerShell 5.1's ConvertFrom-Json cannot parse JSONC (comments /
    trailing commas), which Windows Terminal allows. This helper removes
    comments while preserving content inside string literals (so URLs such as
    "https://example.com" are not mangled) and drops trailing commas before
    closing braces/brackets.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $i = 0
    $len = $Text.Length

    while ($i -lt $len) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $len) { $Text[$i + 1] } else { [char]0 }

        if ($inString) {
            [void]$sb.Append($c)
            if ($escaped) { $escaped = $false }
            elseif ($c -eq '\') { $escaped = $true }
            elseif ($c -eq '"') { $inString = $false }
            $i++
            continue
        }

        if ($c -eq '"') {
            $inString = $true
            [void]$sb.Append($c)
            $i++
            continue
        }

        if ($c -eq '/' -and $next -eq '/') {
            while ($i -lt $len -and $Text[$i] -ne "`n") { $i++ }
            continue
        }

        if ($c -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i + 1 -lt $len -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2
            continue
        }

        [void]$sb.Append($c)
        $i++
    }

    # Remove trailing commas (",}" / ",]") that JSONC allows but JSON rejects.
    return [regex]::Replace($sb.ToString(), ',(\s*[}\]])', '$1')
}

function Get-WindowsTerminalSettingsPath {
    <#
    .SYNOPSIS
    Returns the well-known Windows Terminal settings.json locations.

    .DESCRIPTION
    Covers the Store (stable), Store Preview, and unpackaged installs. Paths are
    returned whether or not they exist; callers are expected to skip missing
    files.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
}

function Read-WindowsTerminalSettings {
    <#
    .SYNOPSIS
    Reads and parses a Windows Terminal settings.json (JSON or JSONC).

    .DESCRIPTION
    Reads the file as raw text and parses it as JSON, retrying as JSONC
    (comments / trailing commas stripped via Remove-JsonComment) so that
    comment-annotated user configs still parse under Windows PowerShell 5.1.
    Throws on unreadable / unparseable files so callers can report an error.
    #>
    [CmdletBinding()]
    [OutputType([psobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop

    try {
        return $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        # Retry assuming JSONC (comments / trailing commas).
        return (Remove-JsonComment -Text $raw) | ConvertFrom-Json -ErrorAction Stop
    }
}

function Save-WindowsTerminalSettings {
    <#
    .SYNOPSIS
    Serializes a settings object back to a Windows Terminal settings.json.

    .DESCRIPTION
    Writes UTF-8 without a BOM (Windows Terminal does not emit one) and uses a
    deep serialization depth so nested actions/profiles are preserved.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [psobject]$Settings
    )

    $out = $Settings | ConvertTo-Json -Depth 32
    [System.IO.File]::WriteAllText($Path, $out, (New-Object System.Text.UTF8Encoding($false)))
}

function Set-WindowsTerminalFont {
    <#
    .SYNOPSIS
    Sets the Windows Terminal default font face by surgically patching settings.json.

    .DESCRIPTION
    Updates only profiles.defaults.font.face in each existing Windows Terminal
    settings.json, leaving everything else untouched. Windows Terminal keeps
    owning the file, so this avoids the conflicts that come from managing the
    whole config in git. Files that do not exist are skipped (initial creation
    is handled by run_once_setup-windows-terminal.ps1).

    .PARAMETER FontFace
    The font face name to set, e.g. 'FiraCode Nerd Font'.

    .PARAMETER SettingsPath
    One or more settings.json paths. Defaults to the known Windows Terminal
    locations (Store, Preview, and unpackaged).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$FontFace,

        [Parameter()]
        [string[]]$SettingsPath
    )

    if (-not $SettingsPath) {
        $SettingsPath = Get-WindowsTerminalSettingsPath
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $json = Read-WindowsTerminalSettings -Path $path

            if ($null -eq $json.profiles) {
                $json | Add-Member -NotePropertyName profiles -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if ($null -eq $json.profiles.defaults) {
                $json.profiles | Add-Member -NotePropertyName defaults -NotePropertyValue ([pscustomobject]@{}) -Force
            }
            if ($null -eq $json.profiles.defaults.font) {
                $json.profiles.defaults | Add-Member -NotePropertyName font -NotePropertyValue ([pscustomobject]@{}) -Force
            }

            if ($json.profiles.defaults.font.face -eq $FontFace) {
                Write-Verbose "Font already set to '$FontFace' at: $path"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'AlreadySet' }
                continue
            }

            if ($null -eq $json.profiles.defaults.font.PSObject.Properties['face']) {
                $json.profiles.defaults.font | Add-Member -NotePropertyName face -NotePropertyValue $FontFace -Force
            }
            else {
                $json.profiles.defaults.font.face = $FontFace
            }

            if ($PSCmdlet.ShouldProcess($path, "Set default font face to '$FontFace'")) {
                Save-WindowsTerminalSettings -Path $path -Settings $json
                Write-Host "[OK] Set Windows Terminal font to '$FontFace' at: $path" -ForegroundColor Green
                $results += [pscustomobject]@{ Path = $path; Changed = $true; Status = 'Updated' }
            }
            else {
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'WhatIf' }
            }
        }
        catch {
            Write-Warning "Could not update Windows Terminal settings at '$path': $_"
            $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'Error' }
        }
    }

    return $results
}

function Set-WindowsTerminalDefaultProfile {
    <#
    .SYNOPSIS
    Points Windows Terminal's defaultProfile at a profile resolved from settings.json.

    .DESCRIPTION
    Parses each existing Windows Terminal settings.json, finds the matching
    profile in profiles.list (by source, e.g. 'Windows.Terminal.PowershellCore',
    or by display name), and surgically sets the top-level defaultProfile to that
    profile's guid. Only defaultProfile is touched; the rest of the config is
    left exactly as Windows Terminal wrote it, so this is safe to run against a
    different, hand-tuned config on every machine.

    When no matching profile exists (e.g. PowerShell Core is not installed on
    that machine) the file is left unchanged and the result is reported as
    'ProfileNotFound' rather than raising an error, so callers can skip cleanly.

    .PARAMETER Source
    The profile 'source' to match, e.g. 'Windows.Terminal.PowershellCore'
    (default). Used when -ProfileName is not supplied.

    .PARAMETER ProfileName
    Match a profile by its display 'name' instead of its 'source'.

    .PARAMETER SettingsPath
    One or more settings.json paths. Defaults to the known Windows Terminal
    locations (Store, Preview, and unpackaged).

    .EXAMPLE
    Set-WindowsTerminalDefaultProfile
    Sets the default profile to the PowerShell Core profile, if present.

    .EXAMPLE
    Set-WindowsTerminalDefaultProfile -ProfileName 'Debian'
    Sets the default profile to the profile named 'Debian', if present.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'BySource')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(ParameterSetName = 'BySource')]
        [ValidateNotNullOrEmpty()]
        [string]$Source = 'Windows.Terminal.PowershellCore',

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$ProfileName,

        [Parameter()]
        [string[]]$SettingsPath
    )

    if (-not $SettingsPath) {
        $SettingsPath = Get-WindowsTerminalSettingsPath
    }

    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        $criteria = "name '$ProfileName'"
    }
    else {
        $criteria = "source '$Source'"
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $json = Read-WindowsTerminalSettings -Path $path

            $list = $null
            if ($json.PSObject.Properties['profiles'] -and $json.profiles.PSObject.Properties['list']) {
                $list = @($json.profiles.list)
            }

            if (-not $list) {
                Write-Verbose "No profiles.list found in: $path (skipping)"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'ProfileNotFound'; Guid = $null; MatchedProfile = $null }
                continue
            }

            if ($PSCmdlet.ParameterSetName -eq 'ByName') {
                $match = $list | Where-Object { $_.PSObject.Properties['name'] -and $_.name -eq $ProfileName } | Select-Object -First 1
            }
            else {
                $match = $list | Where-Object { $_.PSObject.Properties['source'] -and $_.source -eq $Source } | Select-Object -First 1
            }

            if (-not $match -or -not $match.PSObject.Properties['guid'] -or [string]::IsNullOrWhiteSpace([string]$match.guid)) {
                Write-Verbose "No profile matching $criteria (with a guid) found in: $path (skipping)"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'ProfileNotFound'; Guid = $null; MatchedProfile = $null }
                continue
            }

            $guid = [string]$match.guid
            $name = if ($match.PSObject.Properties['name']) { [string]$match.name } else { $guid }

            $currentDefault = if ($json.PSObject.Properties['defaultProfile']) { [string]$json.defaultProfile } else { $null }
            if ($currentDefault -eq $guid) {
                Write-Verbose "defaultProfile already set to $guid ($name) at: $path"
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'AlreadySet'; Guid = $guid; MatchedProfile = $name }
                continue
            }

            if ($null -eq $json.PSObject.Properties['defaultProfile']) {
                $json | Add-Member -NotePropertyName defaultProfile -NotePropertyValue $guid -Force
            }
            else {
                $json.defaultProfile = $guid
            }

            if ($PSCmdlet.ShouldProcess($path, "Set defaultProfile to $guid ($name)")) {
                Save-WindowsTerminalSettings -Path $path -Settings $json
                Write-Host "[OK] Set Windows Terminal default profile to '$name' ($guid) at: $path" -ForegroundColor Green
                $results += [pscustomobject]@{ Path = $path; Changed = $true; Status = 'Updated'; Guid = $guid; MatchedProfile = $name }
            }
            else {
                $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'WhatIf'; Guid = $guid; MatchedProfile = $name }
            }
        }
        catch {
            Write-Warning "Could not update Windows Terminal default profile at '$path': $_"
            $results += [pscustomobject]@{ Path = $path; Changed = $false; Status = 'Error'; Guid = $null; MatchedProfile = $null }
        }
    }

    return $results
}
