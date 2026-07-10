#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for the Connect-CopilotSsh function in the DotfilesHelpers module.

.DESCRIPTION
    Tests the PowerShell port of the copilot-ssh / copilot_ssh helper: reading
    GitHub tokens from a 1Password Environment via `op run` and forwarding them
    to a remote host with SSH SendEnv. External `op` and `ssh` are replaced with
    PATH stubs (Windows .cmd) so the behaviour is validated without 1Password or
    a real SSH connection. Behavioural tests are Windows-only (they rely on .cmd
    stubs); static/body tests run everywhere.
#>

BeforeDiscovery {
    $script:IsWindowsHost = $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop')
}

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:StubDir = (New-Item -ItemType Directory -Path (Join-Path $tmpRoot "copilot-ssh-tests-$(Get-Random)") -Force).FullName
    $script:OrigPath = $env:PATH
    $script:OrigEnvId = $env:OP_COPILOT_ENVIRONMENT_ID
    $script:Tab = [char]9

    # Writes a stub `ssh.cmd` that reports its args and the forwarded tokens.
    function script:New-SshStub {
        $sshPath = Join-Path $script:StubDir 'ssh.cmd'
        @"
@echo off
echo SSH_ARGS: %*
echo FWD_COPILOT=%COPILOT_GITHUB_TOKEN%
echo FWD_GH=%GH_TOKEN%
"@ | Set-Content -Path $sshPath -Encoding ASCII
    }

    # Writes a stub `op.cmd`. -Stdout is emitted verbatim; -ExitCode controls the
    # exit status. The stub ignores its arguments (the real child command is an
    # implementation detail); it only reproduces op's stdout/exit contract.
    function script:New-OpStub {
        param([string]$Stdout = '', [int]$ExitCode = 0)
        $opPath = Join-Path $script:StubDir 'op.cmd'
        $lines = @('@echo off')
        if ($ExitCode -ne 0) {
            $lines += "exit /b $ExitCode"
        }
        elseif ($Stdout -eq '') {
            $lines += 'echo.'
        }
        else {
            $lines += "echo $Stdout"
        }
        ($lines -join "`r`n") | Set-Content -Path $opPath -Encoding ASCII
    }

    function script:Remove-OpStub {
        Remove-Item (Join-Path $script:StubDir 'op.cmd') -Force -ErrorAction SilentlyContinue
    }
}

AfterAll {
    Pop-Location
    $env:PATH = $script:OrigPath
    if ($null -eq $script:OrigEnvId) { Remove-Item Env:OP_COPILOT_ENVIRONMENT_ID -ErrorAction SilentlyContinue }
    else { $env:OP_COPILOT_ENVIRONMENT_ID = $script:OrigEnvId }
    if (Test-Path $script:StubDir) {
        Remove-Item -Recurse -Force $script:StubDir -ErrorAction SilentlyContinue
    }
}

Describe "Connect-CopilotSsh availability" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Connect-CopilotSsh -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should be exported by the module manifest" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        $manifest = Import-PowerShellDataFile -Path $manifestPath
        $manifest.FunctionsToExport | Should -Contain 'Connect-CopilotSsh'
    }

    It "Should be aliased as copilot-ssh and copilot_ssh in aliases.ps1" {
        $aliasesPath = Join-Path $script:RepoRoot "home/dot_config/powershell/aliases.ps1"
        $content = Get-Content $aliasesPath -Raw
        $content | Should -Match 'Set-Alias\s+-Name\s+copilot-ssh\s+-Value\s+Connect-CopilotSsh'
        $content | Should -Match 'Set-Alias\s+-Name\s+copilot_ssh\s+-Value\s+Connect-CopilotSsh'
    }
}

Describe "Connect-CopilotSsh body" -Tag "Unit" {
    BeforeAll {
        $script:Body = (Get-Command Connect-CopilotSsh).ScriptBlock.ToString()
    }

    It "Should read tokens via 'op run --no-masking'" {
        $script:Body | Should -Match 'op\s+run'
        $script:Body | Should -Match '--no-masking'
    }

    It "Should forward COPILOT_GITHUB_TOKEN via SendEnv" {
        $script:Body | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
    }

    It "Should conditionally forward GH_TOKEN via SendEnv" {
        $script:Body | Should -Match 'SendEnv=GH_TOKEN'
    }

    It "Should point users to 1Password Developer settings when op is missing" {
        $script:Body | Should -Match 'Settings\s*->\s*Developer'
    }

    It "HostName parameter should have an argument completer" {
        $cmd = Get-Command Connect-CopilotSsh
        $attrs = $cmd.Parameters['HostName'].Attributes
        ($attrs | Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }) |
            Should -Not -BeNullOrEmpty
    }

    It "Should collect extra ssh options via ValueFromRemainingArguments" {
        $cmd = Get-Command Connect-CopilotSsh
        $paramAttr = $cmd.Parameters['SshArgument'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            Select-Object -First 1
        $paramAttr.ValueFromRemainingArguments | Should -Be $true
    }
}

Describe "Connect-CopilotSsh help" -Tag "Unit" {
    It "Should display usage for --help" {
        $out = (Connect-CopilotSsh --help *>&1) | Out-String
        $out | Should -Match 'Usage: copilot-ssh'
        $out | Should -Match 'tab-completes'
    }

    It "Should display usage for -h" {
        $out = (Connect-CopilotSsh -h *>&1) | Out-String
        $out | Should -Match 'Usage: copilot-ssh'
    }

    It "Should provide comment-based help with a synopsis" {
        (Get-Help Connect-CopilotSsh).Synopsis | Should -Match '1Password'
    }
}

Describe "Connect-CopilotSsh behaviour" -Tag "Unit" -Skip:(-not $script:IsWindowsHost) {
    BeforeEach {
        script:New-SshStub
        $env:PATH = $script:StubDir
        $env:OP_COPILOT_ENVIRONMENT_ID = 'ENV-TEST'
    }

    AfterEach {
        $env:PATH = $script:OrigPath
        Remove-Item Env:COPILOT_GITHUB_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
    }

    It "Falls back to plain ssh when op is not installed" {
        script:Remove-OpStub
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match "'1Password CLI' \(op\) not found"
        $out | Should -Match 'Settings -> Developer'
        $out | Should -Match 'SSH_ARGS: myhost'
        $out | Should -Not -Match 'SendEnv'
    }

    It "Falls back to plain ssh when the Environment ID is unset" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        Remove-Item Env:OP_COPILOT_ENVIRONMENT_ID -ErrorAction SilentlyContinue
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'OP_COPILOT_ENVIRONMENT_ID is not set'
        $out | Should -Match 'SSH_ARGS: myhost'
        $out | Should -Not -Match 'SendEnv'
    }

    It "Forwards both tokens when present" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
        $out | Should -Match 'SendEnv=GH_TOKEN'
        $out | Should -Match 'FWD_COPILOT=ctok'
        $out | Should -Match 'FWD_GH=gtok'
    }

    It "Forwards only COPILOT_GITHUB_TOKEN when GH_TOKEN is empty" {
        script:New-OpStub -Stdout 'ctok'
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'SendEnv=COPILOT_GITHUB_TOKEN'
        $out | Should -Not -Match 'SendEnv=GH_TOKEN'
        $out | Should -Match 'FWD_COPILOT=ctok'
    }

    It "Passes through extra ssh arguments after a -- separator" {
        script:New-OpStub -Stdout "ctok$($script:Tab)gtok"
        $out = (Connect-CopilotSsh myhost -- -A -p 2222 *>&1) | Out-String
        $out | Should -Match '-A -p 2222 myhost'
    }

    It "Errors when COPILOT_GITHUB_TOKEN is missing from the Environment" {
        script:New-OpStub -Stdout ''
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'COPILOT_GITHUB_TOKEN not found'
        $out | Should -Not -Match 'SSH_ARGS:'
    }

    It "Errors with a dedicated message when op run fails" {
        script:New-OpStub -ExitCode 3
        $out = (Connect-CopilotSsh myhost *>&1) | Out-String
        $out | Should -Match 'failed to read tokens'
        $out | Should -Not -Match 'SSH_ARGS:'
    }
}

Describe "Get-DotfilesSshHost (tab-completion source)" -Tag "Unit" {
    BeforeAll {
        # Build a fake ssh directory with a config, an Include, patterns and the
        # inline "Host=name" form so the parser is exercised end to end. The
        # helper is private, so we invoke it inside the module scope and point
        # it at the fixture via -SshDirectory.
        $script:FakeSshDir = (New-Item -ItemType Directory -Path (Join-Path $script:StubDir "sshconf-$(Get-Random)")).FullName
        New-Item -ItemType Directory -Path (Join-Path $script:FakeSshDir 'conf.d') -Force | Out-Null
        @(
            '# a comment'
            'Host svldev svldev-alt'
            '    HostName 10.0.0.1'
            'Host svlprod'
            '    User root'
            'Host *.internal'
            '    User admin'
            'Host bastion-*'
            '    User jump'
            'Include conf.d/*.conf'
        ) -join "`n" | Set-Content -Path (Join-Path $script:FakeSshDir 'config') -Encoding ASCII
        @(
            'Host extrahost'
            'Host=inlinehost'
        ) -join "`n" | Set-Content -Path (Join-Path $script:FakeSshDir 'conf.d/more.conf') -Encoding ASCII

        $script:Module = Get-Module DotfilesHelpers
    }

    It "Should be a private helper (not exported by the manifest)" {
        $manifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        (Import-PowerShellDataFile -Path $manifestPath).FunctionsToExport | Should -Not -Contain 'Get-DotfilesSshHost'
    }

    It "Should return concrete host aliases including multi-name and Include entries" {
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $script:FakeSshDir
        $hosts | Should -Contain 'svldev'
        $hosts | Should -Contain 'svldev-alt'
        $hosts | Should -Contain 'svlprod'
        $hosts | Should -Contain 'extrahost'
        $hosts | Should -Contain 'inlinehost'
    }

    It "Should exclude pattern entries (wildcards)" {
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $script:FakeSshDir
        $hosts | Should -Not -Contain '*.internal'
        $hosts | Should -Not -Contain 'bastion-*'
    }

    It "Should filter by prefix" {
        $hosts = & $script:Module { param($d, $f) Get-DotfilesSshHost -SshDirectory $d -Filter $f } $script:FakeSshDir 'svl'
        $hosts | Should -Contain 'svldev'
        $hosts | Should -Contain 'svlprod'
        $hosts | Should -Not -Contain 'extrahost'
    }

    It "Should return an empty result when no config exists" {
        $empty = (New-Item -ItemType Directory -Path (Join-Path $script:StubDir "nossh-$(Get-Random)")).FullName
        $hosts = & $script:Module { param($d) Get-DotfilesSshHost -SshDirectory $d } $empty
        @($hosts).Count | Should -Be 0
    }
}
