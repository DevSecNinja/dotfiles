# GitHub Copilot CLI SSH helper
#
# Connect-CopilotSsh (aliased 'copilot-ssh' / 'copilot_ssh') - SSH into a host
# with GitHub tokens forwarded from a 1Password Environment.
#
# Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present, GH_TOKEN
# (for the GitHub CLI) from a 1Password Environment on this (workstation)
# machine via `op run`, then forwards them to the remote session using SSH
# SendEnv, so both tools can authenticate on headless servers that have no
# secure vault. The tokens are never written to disk; they live only in
# 1Password, transiently in this session, the encrypted SSH channel, and the
# remote session's environment.
#
# The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` (handled by the
# docker repo's system_setup Ansible role). Copilot CLI reads
# COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); the `gh` CLI reads GH_TOKEN.
#
# Requirements:
#   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration.
#   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (rendered
#     from the chezmoi `opCopilotEnvironmentId` variable). The Environment must
#     contain COPILOT_GITHUB_TOKEN; GH_TOKEN is optional (forwarded if present).
#
# Usage: copilot-ssh [ssh options...] <host>   (e.g. copilot-ssh svldev)
#
# If `op` or the Environment ID is unavailable, it falls back to a plain ssh so
# the command still connects (the tools just won't receive a token).

function Connect-CopilotSsh {
    if ($Args.Count -ge 1 -and ($Args[0] -eq '-h' -or $Args[0] -eq '--help')) {
        Write-Host 'Usage: copilot-ssh [ssh options...] <host>'
        Write-Host 'SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment.'
        return
    }

    $sshArgs = @($Args)

    if (-not (Get-Command op -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Warning "copilot-ssh: 'op' (1Password CLI) not found; using plain ssh (no token forwarded)."
        & ssh @sshArgs
        return
    }

    $envId = $env:OP_COPILOT_ENVIRONMENT_ID
    if ([string]::IsNullOrEmpty($envId)) {
        Write-Warning "copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh."
        & ssh @sshArgs
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
        Write-Error "copilot-ssh: failed to read tokens from 1Password Environment '$envId'. Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled, and the Environment ID is correct."
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
        & ssh @sshEnvOpts @sshArgs
    }
    finally {
        if ($null -eq $prevCopilot) { Remove-Item Env:COPILOT_GITHUB_TOKEN -ErrorAction SilentlyContinue }
        else { $env:COPILOT_GITHUB_TOKEN = $prevCopilot }
        if ($null -eq $prevGh) { Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue }
        else { $env:GH_TOKEN = $prevGh }
    }
}
