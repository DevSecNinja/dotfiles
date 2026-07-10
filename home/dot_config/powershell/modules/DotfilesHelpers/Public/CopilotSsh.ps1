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

        Pre-flight checks are fatal: if `ssh` or `op` is missing, or
        OP_COPILOT_ENVIRONMENT_ID is unset, the command aborts without
        connecting (rather than silently opening a token-less session that
        would leave copilot/gh unauthenticated on the server).
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

    # Pre-flight checks. Each is fatal: the whole purpose of this helper is to
    # forward GitHub tokens, so if we cannot, we stop rather than silently
    # opening a token-less ssh session (which would leave copilot/gh
    # unauthenticated on the server in a confusing way).
    if (-not (Get-Command ssh -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Error "copilot-ssh: 'ssh' (OpenSSH client) was not found on PATH. Install the OpenSSH client and try again."
        return
    }

    if (-not (Get-Command op -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Error ("copilot-ssh: '1Password CLI' (op) was not found on PATH; aborting (tokens cannot be forwarded).`n" +
            "            1. Install it: https://developer.1password.com/docs/cli/get-started/ (>= 2.33.0-beta.02).`n" +
            "            2. Enable the desktop-app integration: 1Password -> Settings -> Developer ->`n" +
            "               'Integrate with 1Password CLI', then restart your terminal.`n" +
            "            See docs/copilot-cli.md for details.")
        return
    }

    $envId = $env:OP_COPILOT_ENVIRONMENT_ID
    if ([string]::IsNullOrEmpty($envId)) {
        Write-Error ("copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set; aborting (tokens cannot be forwarded).`n" +
            "            Set the chezmoi 'opCopilotEnvironmentId' variable (see docs/copilot-cli.md).")
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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCT8Rz3X/zEG488
# NXGMqtymSecZPbYqH+tuwWSTQy2D06CCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBmbRR76szuS/HJdZUsIqfsF6lrbI8MC40kU6a6vLrcQzANBgkqhkiG
# 9w0BAQEFAASCAgA/NhwM5OVf34O23+XSZW7OjJD6OhCYqcSiM/UuWQ4RZarS7Qz4
# ue9LDQ/kXb4TCtSjQzDPYk8RMmzkWMAO0Qwcsd29s0HSGjgQ/ElEsvmh0g81687l
# 7rTgOVyuFm2aPzAMlMWYUyPP3d3zOeMNVrL7XbDKmwQb8fnMUGeWOq0xWyfRH3qm
# 4Xo0tU/LAOEIsqGX1TdCL1EEtYMC+94LnTEK/TmbtvDq81FfjUi+N6kta3h4JK3P
# 4htzC7FTgXldR4EEitb+1SkoguSScFk+U7AMRqmf19JqtDTnd0V/5jFBRqzu2/Ai
# dnlfqsZ3zWsHWGv7qIgJuJDW2IMmvLRP8orSlmgSQdSZGF/zD6KtnbT8EQwbp4kk
# jmzzLzjKgoxWlUoP5k3JxJ9BSMcNUJsf7MlCueGbpfiWE5MZ7FmCfGt2S9osr0t+
# 8encbM1eRlofFwag6TP9GI/W7KqerewSUdkCxqn3g2Fwam5cXaZ3kbQhbm47fPjh
# 2hKJenpC3cRwLmthBbLVRiT2XJLg5ULzWh4q+mXKaL98FnvPeR48vdpE93vWfzHA
# KL0yVbdEBuCHTVYZuxL6gRQwazTLDoIOxXkcfJVgtYJiplu7BUbKAVjWpswNLOIW
# /weVuvQc/ztwDb5+X/gWRs7XGcVLFKn1Mdm+HA8CjT0NcgJaFDNfCqJHv6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MTAwNzM5NDNaMC8GCSqGSIb3DQEJBDEi
# BCDY+ta4wzOxXMESAOk5mfBZJRvb96rz7sNhUXoBRVsRdjANBgkqhkiG9w0BAQEF
# AASCAgCoghshTufUhK79yhEZzDNITfT/WDjv3K6mcdT6x+oudAUrqCrg1/AWf3db
# S/izScC5dXhHhm66wRn+Dw0l+iwrde336FssmIFuaU9nks8Aqgtu35LkuMNEX+Fu
# QQBYh5kkQ5KOR+YPf5EX1CWBWLkeWrZssMbZ/M3jX1OhlmggMNBhooPKcxX4RWwf
# RCrqmfazK1SfuRzse2IcJwUVPpTJOMYPe5sM48mMBWGqpHAduuK7an4wWHycG51s
# x2h4ykLTh13Cx41jkbQr/Mk4TKPIa2eIQZjCctGbVvdLU5bIZugkOAzOjQfBIMFe
# X27PEgWzxdmXuBY53d59hj4H/EEBqFQpSx20UWxPgSc2KjHKUB+OLYRQMrhWEuxn
# n2yTF5rRVEKCdzT47xkCefkE6lhjIlmk4Rd8v5AHm/XMB/XcummMUjd1sdI+BuAw
# EZF13JCJfR8hkYXRSZ3eUGBZ/8XLpvLqXXJGlDmLnPVQhfoDEM75U3cooAn52fz2
# 60YOoaiMuh6ktRC0r1aeYwdM9SZrS30MLwE1ic4q2ZDIH/wn7665Ys7DKB/EQnPZ
# f+AefbruNBmcj7L2LUkJD9lToCOr4FCEDaHwapbMmQvElBIcKwN+s0c22eDqDUDa
# uH6hKlJ2gczSJSxPjPbHPAYx7VhAfdX75gLRAfUqRG8XD36ckg==
# SIG # End signature block
