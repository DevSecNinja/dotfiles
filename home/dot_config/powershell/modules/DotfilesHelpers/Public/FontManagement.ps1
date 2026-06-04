# Font management utilities
#
# Functions for installing Nerd Fonts and for pointing Windows Terminal at an
# installed font without managing (and fighting git-sync on) the whole
# settings.json file.

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

function Test-NerdFontInstalled {
    <#
    .SYNOPSIS
    Returns $true if a Nerd Font matching the given name is registered.

    .PARAMETER Name
    The Nerd Font family name (as passed to Install-NerdFont), e.g. 'FiraCode'.
    Matching ignores spaces, so 'FiraCode' matches the registered
    'FiraCodeNerdFont-Regular (TrueType)' value.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9._ -]+$')]
        [string]$Name = 'FiraCode'
    )

    $needle = ($Name -replace '\s', '')
    $keys = @(
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )

    foreach ($key in $keys) {
        if (-not (Test-Path -Path $key)) { continue }
        $props = (Get-ItemProperty -Path $key).PSObject.Properties
        foreach ($prop in $props) {
            if ($prop.Name -like 'PS*') { continue }
            $normalized = ($prop.Name -replace '\s', '')
            if ($normalized -like "*${needle}NerdFont*") { return $true }
        }
    }

    return $false
}

function Invoke-NerdFontInstaller {
    <#
    .SYNOPSIS
    Performs the actual Nerd Font install via the (PowerShell 7) NerdFonts module.

    .DESCRIPTION
    chezmoi runs scripts under Windows PowerShell 5.1, but the NerdFonts module
    is PowerShell 7 only, so the install is delegated to pwsh. Kept private so
    Install-DotfilesNerdFont can be unit-tested by mocking this function.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope
    )

    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd) {
        Write-Warning "pwsh (PowerShell 7) not found; cannot install Nerd Font '$Name'. Install PowerShell 7 first."
        return $false
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Install Nerd Font')) { return $false }

    # $Name and $Scope are constrained by ValidatePattern/ValidateSet above, so
    # interpolating them into the command string is safe from injection.
    $inner = "Install-PSResource -Name NerdFonts -Scope CurrentUser -TrustRepository -Quiet -ErrorAction Stop; " +
    "Install-NerdFont -Name $Name -Scope $Scope -Confirm:`$false -ErrorAction Stop"

    & $pwshCmd.Source -ExecutionPolicy Bypass -NoProfile -NonInteractive -Command $inner 2>&1 |
        ForEach-Object { Write-Verbose ([string]$_) }

    return ($LASTEXITCODE -eq 0)
}

function Install-DotfilesNerdFont {
    <#
    .SYNOPSIS
    Idempotently installs a Nerd Font and verifies it registered.

    .PARAMETER Name
    Nerd Font family name (default 'FiraCode').

    .PARAMETER Scope
    Install scope: CurrentUser (default) or AllUsers.

    .PARAMETER Force
    Reinstall even if the font already appears to be installed.

    .EXAMPLE
    Install-DotfilesNerdFont -Name FiraCode -Scope CurrentUser
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([pscustomobject])]
    param(
        [Parameter()]
        [ValidatePattern('^[A-Za-z0-9._-]+$')]
        [string]$Name = 'FiraCode',

        [Parameter()]
        [ValidateSet('CurrentUser', 'AllUsers')]
        [string]$Scope = 'CurrentUser',

        [switch]$Force
    )

    if ((Test-NerdFontInstalled -Name $Name) -and -not $Force) {
        Write-Host "[OK] $Name Nerd Font already installed" -ForegroundColor Green
        return [pscustomobject]@{ Name = $Name; Installed = $true; Action = 'AlreadyInstalled' }
    }

    if (-not $PSCmdlet.ShouldProcess($Name, 'Install Nerd Font')) {
        return [pscustomobject]@{ Name = $Name; Installed = (Test-NerdFontInstalled -Name $Name); Action = 'Skipped' }
    }

    Write-Host "Installing $Name Nerd Font..." -ForegroundColor Cyan
    $ok = Invoke-NerdFontInstaller -Name $Name -Scope $Scope
    $installed = Test-NerdFontInstalled -Name $Name

    if ($ok -and $installed) {
        Write-Host "[OK] $Name Nerd Font installed" -ForegroundColor Green
        return [pscustomobject]@{ Name = $Name; Installed = $true; Action = 'Installed' }
    }

    Write-Warning "Failed to install $Name Nerd Font. Install manually with: pwsh -Command 'Install-NerdFont -Name $Name -Scope $Scope'"
    return [pscustomobject]@{ Name = $Name; Installed = $false; Action = 'Failed' }
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
        $SettingsPath = @(
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
            (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
        )
    }

    $results = @()

    foreach ($path in $SettingsPath) {
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Verbose "Windows Terminal settings not found at: $path (skipping)"
            continue
        }

        try {
            $raw = Get-Content -LiteralPath $path -Raw -ErrorAction Stop

            $json = $null
            try {
                $json = $raw | ConvertFrom-Json -ErrorAction Stop
            }
            catch {
                # Retry assuming JSONC (comments / trailing commas).
                $json = (Remove-JsonComment -Text $raw) | ConvertFrom-Json -ErrorAction Stop
            }

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
                $out = $json | ConvertTo-Json -Depth 32
                [System.IO.File]::WriteAllText($path, $out, (New-Object System.Text.UTF8Encoding($false)))
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
