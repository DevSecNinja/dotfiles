# GitHub Copilot CLI SSH helper
#
# Connect-CopilotSsh (aliased 'copilot-ssh' / 'copilot_ssh') - SSH into a host
# with GitHub tokens forwarded from a 1Password Environment.
#
# See docs/copilot-cli.md for the full design. In short: it reads
# COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present, GH_TOKEN (for
# the GitHub CLI) from a 1Password Environment via `op run`, then forwards them
# to the remote session using SSH SendEnv so both tools can authenticate on
# headless servers that have no secure vault. Tokens are never written to disk.

function Get-DotfilesSshHost {
    <#
    .SYNOPSIS
        Return concrete host aliases defined in the user's SSH client config.
    .DESCRIPTION
        Parses ~/.ssh/config (following `Include` directives) and returns the
        literal `Host` aliases, excluding pattern entries (those containing
        wildcards '*'/'?' or negations '!'). Used to power tab-completion for
        Connect-CopilotSsh. Never throws; returns an empty array on any error.
    .PARAMETER Filter
        Optional prefix; only hosts matching "<Filter>*" (case-insensitive) are
        returned.
    .PARAMETER SshDirectory
        The SSH client directory to read (config + Include files). Defaults to
        ~/.ssh. Exposed primarily so tests can point at a fixture directory.
    #>
    [CmdletBinding()]
    param(
        [string]$Filter,
        [string]$SshDirectory = (Join-Path $HOME '.ssh')
    )

    $rootConfig = Join-Path $SshDirectory 'config'
    $sshDir = $SshDirectory
    $hosts = [System.Collections.Generic.List[string]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Read-Config {
        param([string]$Path)

        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        # Expand a possible leading ~ and make Include globs relative to ~/.ssh.
        if ($Path -like '~*') { $Path = Join-Path $HOME ($Path.Substring(1).TrimStart('/', '\')) }
        if (-not [System.IO.Path]::IsPathRooted($Path)) { $Path = Join-Path $sshDir $Path }

        $matched = @()
        try { $matched = @(Resolve-Path -Path $Path -ErrorAction SilentlyContinue) } catch { $matched = @() }

        foreach ($resolved in $matched) {
            $file = $resolved.Path
            if (-not $visited.Add($file)) { continue }
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }

            $lines = @()
            try { $lines = Get-Content -LiteralPath $file -ErrorAction SilentlyContinue } catch { $lines = @() }

            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed -eq '' -or $trimmed.StartsWith('#')) { continue }

                # Split keyword from its arguments; allow "Key value" and "Key=value".
                $tokens = $trimmed -split '[\s=]+'
                if ($tokens.Count -lt 2) { continue }
                $keyword = $tokens[0]

                if ($keyword -ieq 'Include') {
                    foreach ($inc in $tokens[1..($tokens.Count - 1)]) { Read-Config -Path $inc }
                }
                elseif ($keyword -ieq 'Host') {
                    foreach ($name in $tokens[1..($tokens.Count - 1)]) {
                        if ($name -match '[*?]' -or $name.StartsWith('!')) { continue }
                        if (-not $hosts.Contains($name)) { $hosts.Add($name) }
                    }
                }
            }
        }
    }

    Read-Config -Path $rootConfig

    $result = $hosts
    if (-not [string]::IsNullOrEmpty($Filter)) {
        $result = $hosts | Where-Object { $_ -like "$Filter*" }
    }
    return @($result | Sort-Object -Unique)
}

function Connect-CopilotSsh {
    <#
    .SYNOPSIS
        SSH into a host with GitHub tokens forwarded from a 1Password Environment.
    .DESCRIPTION
        Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present,
        GH_TOKEN (for the GitHub CLI) from a 1Password Environment via a single
        `op run`, then forwards them to the remote session with SSH SendEnv so
        both tools can authenticate on headless servers that have no secure
        vault. The tokens are never written to disk; they live only in
        1Password, transiently in this session, the encrypted SSH channel, and
        the remote session's environment.

        The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN`. Copilot
        CLI reads COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); the `gh` CLI
        reads GH_TOKEN.

        Requirements:
          - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app
            integration enabled (1Password -> Settings -> Developer ->
            "Integrate with 1Password CLI").
          - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID
            (rendered from the chezmoi `opCopilotEnvironmentId` variable). The
            Environment must contain COPILOT_GITHUB_TOKEN; GH_TOKEN is optional.

        If `op` or the Environment ID is unavailable, it falls back to a plain
        ssh so the command still connects (the tools just won't get a token).
    .PARAMETER HostName
        The SSH destination (e.g. svldev). Tab-completes from the `Host` aliases
        in your ~/.ssh/config.
    .PARAMETER SshArgument
        Extra arguments passed through to ssh. Because ssh flags such as -p / -o
        collide with PowerShell's parameter binder, pass them after a `--`
        separator, e.g. `copilot-ssh svldev -- -A -p 2222`.
    .EXAMPLE
        copilot-ssh svldev
        Connect to svldev with the tokens forwarded.
    .EXAMPLE
        copilot-ssh svldev -- -A -p 2222
        Connect with SSH agent forwarding on port 2222.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({
                param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
                $module = Get-Module DotfilesHelpers
                if (-not $module) { return }
                & $module { param($w) Get-DotfilesSshHost -Filter $w } $wordToComplete |
                    ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
            })]
        [Alias('Host', 'Destination')]
        [string]$HostName,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$SshArgument,

        [Alias('h')]
        [switch]$Help
    )

    if ($Help -or $HostName -in @('-h', '--help', '-?')) {
        Write-Host 'Usage: copilot-ssh <host> [-- ssh options...]'
        Write-Host 'SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment.'
        Write-Host 'The <host> argument tab-completes from your ~/.ssh/config Host entries.'
        Write-Host 'Pass extra ssh flags after a -- separator, e.g.: copilot-ssh svldev -- -A -p 2222'
        return
    }

    if ([string]::IsNullOrEmpty($HostName) -and -not $SshArgument) {
        Write-Host 'Usage: copilot-ssh <host> [-- ssh options...]'
        return
    }

    # ssh expects: ssh [options] destination [command]
    $passthrough = @()
    if ($SshArgument) { $passthrough += $SshArgument }
    if (-not [string]::IsNullOrEmpty($HostName)) { $passthrough += $HostName }

    if (-not (Get-Command op -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Warning "copilot-ssh: '1Password CLI' (op) not found; using plain ssh (no token forwarded)."
        Write-Warning "            Enable it in 1Password -> Settings -> Developer -> 'Integrate with 1Password CLI',"
        Write-Warning "            then restart your terminal. See docs/copilot-cli.md for details."
        & ssh @passthrough
        return
    }

    $envId = $env:OP_COPILOT_ENVIRONMENT_ID
    if ([string]::IsNullOrEmpty($envId)) {
        Write-Warning "copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh."
        & ssh @passthrough
        return
    }

    # Read both tokens in a single `op run` (one 1Password unlock) so the
    # interactive ssh below is not wrapped by op run, whose stdout/stderr masking
    # can disturb a TTY. `--no-masking` is required because Environment values
    # are hidden by default. A short child PowerShell prints the two values
    # tab-separated (GitHub tokens never contain a tab) from the injected env.
    $psExe = (Get-Process -Id $PID -ErrorAction SilentlyContinue).Path
    if (-not $psExe) {
        $psExe = if ($PSVersionTable.PSVersion.Major -ge 6) { 'pwsh' } else { 'powershell' }
    }
    $childCmd = '[Console]::Out.Write(([string]$env:COPILOT_GITHUB_TOKEN) + [char]9 + ([string]$env:GH_TOKEN))'
    $creds = & op run --environment $envId --no-masking -- $psExe -NoProfile -NonInteractive -Command $childCmd 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "copilot-ssh: failed to read tokens from 1Password Environment '$envId'. Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled (1Password -> Settings -> Developer), and the Environment ID is correct."
        return
    }

    $parts = ([string]$creds) -split "`t", 2
    $copilotToken = $parts[0]
    $ghToken = if ($parts.Count -ge 2) { $parts[1] } else { '' }

    if ([string]::IsNullOrEmpty($copilotToken)) {
        Write-Error "copilot-ssh: COPILOT_GITHUB_TOKEN not found in Environment '$envId'."
        return
    }

    # Forward COPILOT_GITHUB_TOKEN always; GH_TOKEN only when it is set.
    $sshEnvOpts = @('-o', 'SendEnv=COPILOT_GITHUB_TOKEN')
    if (-not [string]::IsNullOrEmpty($ghToken)) {
        $sshEnvOpts += @('-o', 'SendEnv=GH_TOKEN')
    }

    # Export the tokens for the ssh child process, then restore the previous
    # environment afterwards so they don't linger in this interactive session.
    $prevCopilot = $env:COPILOT_GITHUB_TOKEN
    $prevGh = $env:GH_TOKEN
    try {
        $env:COPILOT_GITHUB_TOKEN = $copilotToken
        if (-not [string]::IsNullOrEmpty($ghToken)) {
            $env:GH_TOKEN = $ghToken
        }
        & ssh @sshEnvOpts @passthrough
    }
    finally {
        if ($null -eq $prevCopilot) { Remove-Item Env:COPILOT_GITHUB_TOKEN -ErrorAction SilentlyContinue }
        else { $env:COPILOT_GITHUB_TOKEN = $prevCopilot }
        if ($null -eq $prevGh) { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
        else { $env:GH_TOKEN = $prevGh }
    }
}
