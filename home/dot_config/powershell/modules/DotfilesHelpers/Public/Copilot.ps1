# GitHub Copilot CLI interactive wrapper
#
# Invoke-Copilot (aliased 'copilot') - runs the real Copilot CLI with
# non-shell file-modifying tools pre-approved, so trusted, git-tracked repos
# stop prompting on every create/edit. Shell commands and MCP tools are left
# gated, so this stays least-privilege. See docs/copilot-cli.md.

function Invoke-Copilot {
    <#
    .SYNOPSIS
        Runs the GitHub Copilot CLI with safe file-write tools pre-approved.
    .DESCRIPTION
        Resolves the real `copilot` executable on PATH (never itself, to
        avoid infinite recursion when this function is aliased to `copilot`)
        and runs it with `--allow-tool=<list>` prepended. The allow-list
        defaults to `write` (file create/edit only) and is configurable via
        $env:COPILOT_ALLOW_TOOLS, so it can be widened (e.g. to also
        pre-approve read-only `git status`/`git diff`) or narrowed without
        editing this function. Shell/bash tools and MCP tools stay gated
        unless explicitly added to the allow-list.

        Use -Raw (or call the resolved executable directly, e.g.
        `copilot.exe ...`) to run the unwrapped CLI when every prompt should
        be shown.
    .PARAMETER Raw
        Skip the --allow-tool pre-approval and run the real CLI unmodified.
    .PARAMETER Arguments
        Arguments passed through to the Copilot CLI.
    .EXAMPLE
        copilot
        Runs Copilot CLI with file writes pre-approved.
    .EXAMPLE
        copilot -Raw
        Runs the unwrapped CLI; every tool call prompts as usual.
    .EXAMPLE
        $env:COPILOT_ALLOW_TOOLS = 'write,shell(git status),shell(git diff)'
        copilot
        Widens the pre-approved tools to include read-only git commands.
    #>
    [CmdletBinding()]
    param(
        [switch]$Raw,

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $cli = Get-Command -Name copilot -CommandType Application -All -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $cli) {
        throw "GitHub Copilot CLI ('copilot') was not found on PATH. Install it before using this wrapper."
    }

    if ($Raw) {
        & $cli.Source @Arguments
        return
    }

    $allowTools = if ($env:COPILOT_ALLOW_TOOLS) { $env:COPILOT_ALLOW_TOOLS } else { 'write' }
    & $cli.Source "--allow-tool=$allowTools" @Arguments
}
