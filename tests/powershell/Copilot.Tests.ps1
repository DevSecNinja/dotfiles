#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the Invoke-Copilot function in the DotfilesHelpers module.

.DESCRIPTION
    Tests the `copilot` wrapper that pre-approves safe file writes via
    `--allow-tool`. The real `copilot` CLI is replaced with a PATH stub
    (Windows .cmd / non-Windows shell script) that records its arguments, so
    the behaviour is validated without a real Copilot CLI installation.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:StubDir = (New-Item -ItemType Directory -Path (Join-Path $tmpRoot "copilot-tests-$(Get-Random)") -Force).FullName
    $script:OrigPath = $env:PATH
    $script:OrigAllowTools = $env:COPILOT_ALLOW_TOOLS

    # Writes a stub `copilot` executable that records the arguments it was
    # called with into a file, so tests can assert on them.
    function script:New-CopilotStub {
        $outFile = Join-Path $script:StubDir 'copilot-args.txt'
        if ($IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')) {
            $stubPath = Join-Path $script:StubDir 'copilot.cmd'
            @"
@echo off
> "$outFile" (
    for %%a in (%*) do echo %%a
)
"@ | Set-Content -Path $stubPath -Encoding ASCII
        }
        else {
            $stubPath = Join-Path $script:StubDir 'copilot'
            @"
#!/bin/sh
: > "$outFile"
for arg in "`$@"; do
    echo "`$arg" >> "$outFile"
done
"@ | Set-Content -Path $stubPath -Encoding ASCII -NoNewline
            & chmod +x $stubPath
        }
        $env:PATH = "$script:StubDir$([IO.Path]::PathSeparator)$script:OrigPath"
        return $outFile
    }
}

AfterAll {
    Pop-Location
    $env:PATH = $script:OrigPath
    if ($null -eq $script:OrigAllowTools) { Remove-Item Env:COPILOT_ALLOW_TOOLS -ErrorAction SilentlyContinue }
    else { $env:COPILOT_ALLOW_TOOLS = $script:OrigAllowTools }
    if (Test-Path $script:StubDir) {
        Remove-Item -Recurse -Force $script:StubDir -ErrorAction SilentlyContinue
    }
}

Describe "Invoke-Copilot availability" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Invoke-Copilot -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should be aliased as 'copilot' via aliases.ps1" {
        $aliasesPath = Join-Path $script:RepoRoot "home/dot_config/powershell/aliases.ps1"
        $content = Get-Content -Raw -Path $aliasesPath
        $content | Should -Match "Set-Alias\s+-Name\s+copilot\s+-Value\s+Invoke-Copilot"
    }

    It "Should throw a clear error when the copilot CLI is not on PATH" {
        try {
            $env:PATH = $script:StubDir
            { Invoke-Copilot } | Should -Throw -ExpectedMessage "*not found on PATH*"
        }
        finally {
            $env:PATH = $script:OrigPath
        }
    }
}

Describe "Invoke-Copilot behaviour" -Tag "Unit" {
    BeforeEach {
        Remove-Item Env:COPILOT_ALLOW_TOOLS -ErrorAction SilentlyContinue
    }

    It "Passes --allow-tool=write by default" {
        $outFile = New-CopilotStub
        Invoke-Copilot
        (Get-Content -Path $outFile -Raw).Contains('--allow-tool=write') | Should -BeTrue
    }

    It "Respects `$env:COPILOT_ALLOW_TOOLS when set" {
        $outFile = New-CopilotStub
        $env:COPILOT_ALLOW_TOOLS = 'write,shell(git status),shell(git diff)'
        Invoke-Copilot
        (Get-Content -Path $outFile -Raw).Contains('--allow-tool=write,shell(git status),shell(git diff)') | Should -BeTrue
    }

    It "Forwards extra arguments after --allow-tool" {
        $outFile = New-CopilotStub
        Invoke-Copilot --help
        $content = Get-Content -Path $outFile
        $content | Should -Contain '--help'
    }

    It "Does not pass --allow-tool when -Raw is used" {
        $outFile = New-CopilotStub
        Invoke-Copilot -Raw --help
        $content = Get-Content -Raw -Path $outFile
        $content.Contains('--allow-tool') | Should -BeFalse
        $content | Should -Match '--help'
    }
}
