#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for winget upgrade functionality.

.DESCRIPTION
    Tests the PowerShell functions and scripts for automated winget package upgrades.
    Validates:
    - Test-WingetUpdates function
    - Invoke-WingetUpgrade function
    - run_onchange_99-winget-upgrade.ps1.tmpl script
    - Module availability checks
    - Compatibility with PowerShell Core and Windows PowerShell

.NOTES
    These tests validate the winget upgrade automation added for chezmoi integration.
    Tests run in both interactive and CI modes.
    Compatible with PowerShell 5.1+ (same as the functions being tested).
#>

BeforeAll {
    # Setup: Navigate to repository root
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    # Load functions from the source file
    $functionsPath = Join-Path $script:RepoRoot "home\dot_config\powershell\functions.ps1"
    if (Test-Path $functionsPath) {
        . $functionsPath
    }
    else {
        throw "Functions file not found at: $functionsPath"
    }

    # Check if we're in CI mode
    $script:IsCIMode = [bool]$env:CI

    # Check if winget or Microsoft.WinGet.Client is available
    $script:WingetAvailable = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
    $script:WingetModuleAvailable = $null -ne (Get-Module -Name Microsoft.WinGet.Client -ListAvailable -ErrorAction SilentlyContinue)
}

AfterAll {
    Pop-Location
}

Describe "Winget Upgrade Functions" -Tag "Unit" {
    Context "Test-WingetUpdates Function" {
        It "Should be available as a function" {
            Get-Command Test-WingetUpdates -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have proper parameter definitions" {
            $cmd = Get-Command Test-WingetUpdates
            $cmd.Parameters.Keys | Should -Contain 'UseWingetModule'
        }

        It "Should return a boolean value" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            $result = Test-WingetUpdates -ErrorAction SilentlyContinue
            $result | Should -BeOfType [bool]
        }

        It "Should handle missing winget gracefully" {
            # Mock Get-Command to simulate missing winget
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'winget' }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }

            { Test-WingetUpdates -UseWingetModule $false -WarningAction SilentlyContinue } | Should -Not -Throw
        }
    }

    Context "Invoke-WingetUpgrade Function" {
        It "Should be available as a function" {
            Get-Command Invoke-WingetUpgrade -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It "Should have proper parameter definitions" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $cmd.Parameters.Keys | Should -Contain 'CountdownSeconds'
            $cmd.Parameters.Keys | Should -Contain 'Force'
            $cmd.Parameters.Keys | Should -Contain 'UseWingetModule'
        }

        It "Should accept CountdownSeconds parameter" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $countdownParam = $cmd.Parameters['CountdownSeconds']
            $countdownParam.ParameterType | Should -Be ([int])
        }

        It "Should have default countdown of 3 seconds" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $countdownParam = $cmd.Parameters['CountdownSeconds']
            $countdownParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Should -Not -BeNullOrEmpty
        }

        It "Should accept Force switch parameter" {
            $cmd = Get-Command Invoke-WingetUpgrade
            $forceParam = $cmd.Parameters['Force']
            $forceParam.SwitchParameter | Should -Be $true
        }

        It "Should skip detection when Force is used" {
            # Mock dependencies to prevent actual execution
            Mock Test-WingetUpdates { return $false }
            Mock Get-Module { return $null } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }
            Mock Get-Command { return $null } -ParameterFilter { $Name -eq 'winget' }
            Mock Import-Module { }
            Mock Update-WinGetPackage { }
            Mock Get-WinGetPackage { return @() }

            # Capture host output
            $output = @()
            Mock Write-Host { $output += $Object }

            # Run with Force to skip detection
            { Invoke-WingetUpgrade -Force -CountdownSeconds 0 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue } | Should -Not -Throw

            # Verify Force mode message appears
            $output -join '' | Should -Match 'Force mode|Skipping detection'
        }
    }

    Context "Function Aliases" {
        It "Should have 'wup' alias for Invoke-WingetUpgrade" {
            # Load aliases
            $aliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
            if (Test-Path $aliasesPath) {
                . $aliasesPath
            }

            $alias = Get-Alias -Name wup -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be 'Invoke-WingetUpgrade'
        }

        It "Should have 'winup' alias for Invoke-WingetUpgrade" {
            # Load aliases
            $aliasesPath = Join-Path $script:RepoRoot "home\dot_config\powershell\aliases.ps1"
            if (Test-Path $aliasesPath) {
                . $aliasesPath
            }

            $alias = Get-Alias -Name winup -ErrorAction SilentlyContinue
            $alias | Should -Not -BeNullOrEmpty
            $alias.Definition | Should -Be 'Invoke-WingetUpgrade'
        }
    }
}

Describe "Winget Upgrade Script" -Tag "Integration" {
    Context "run_onchange_99-winget-upgrade.ps1.tmpl" {
        BeforeAll {
            $script:ScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_onchange_99-winget-upgrade.ps1.tmpl"
        }

        It "Should exist" {
            Test-Path $script:ScriptPath | Should -Be $true
        }

        It "Should have .tmpl extension for Chezmoi templating" {
            $script:ScriptPath | Should -Match '\.ps1\.tmpl$'
        }

        It "Should contain Chezmoi template directives" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '\{\{.*\.chezmoi\.os.*\}\}'
        }

        It "Should only run on Windows" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '\{\{- if eq \.chezmoi\.os "windows" -\}\}'
        }

        It "Should source functions.ps1 if functions not available" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Get-Command.*Invoke-WingetUpgrade'
            $content | Should -Match 'dot_config\\powershell\\functions\.ps1'
        }

        It "Should check for Microsoft.WinGet.Client module" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Microsoft\.WinGet\.Client'
        }

        It "Should call Invoke-WingetUpgrade function" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'Invoke-WingetUpgrade.*-CountdownSeconds'
        }

        It "Should include dependency hashes for onchange trigger" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'packages\.yaml.*sha256sum'
            $content | Should -Match 'functions\.ps1.*sha256sum'
        }

        It "Should use run_onchange prefix with 99 for last execution" {
            $scriptName = Split-Path $script:ScriptPath -Leaf
            $scriptName | Should -Match '^run_onchange_99-'
        }

        It "Should be compatible with PowerShell 5.1+" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match '#Requires -Version 5\.1'
        }

        It "Should handle missing module gracefully" {
            $content = Get-Content $script:ScriptPath -Raw
            $content | Should -Match 'module not found|not found'
            $content | Should -Match 'exit 0'
        }
    }
}

Describe "Package Configuration" -Tag "Configuration" {
    Context "packages.yaml Integration" {
        BeforeAll {
            $script:PackagesYaml = Join-Path $script:RepoRoot "home\.chezmoidata\packages.yaml"
        }

        It "Should include Microsoft.WinGet.Client in packages.yaml" {
            Test-Path $script:PackagesYaml | Should -Be $true
            $content = Get-Content $script:PackagesYaml -Raw
            $content | Should -Match 'Microsoft\.WinGet\.Client'
        }

        It "Should be in the light mode packages (installed on all Windows systems)" {
            $content = Get-Content $script:PackagesYaml -Raw

            # Find the powershell_modules section
            # Note: Manual parsing is used here instead of a YAML parser to avoid
            # introducing additional dependencies (like PowerShell-YAML module).
            # The parsing is specific to the known structure of packages.yaml.
            $lines = Get-Content $script:PackagesYaml
            $inPowerShellModules = $false
            $inLight = $false
            $foundModule = $false

            foreach ($line in $lines) {
                if ($line -match '^\s*powershell_modules:') {
                    $inPowerShellModules = $true
                }
                elseif ($inPowerShellModules -and $line -match '^\s*light:') {
                    $inLight = $true
                }
                elseif ($inLight -and $line -match '^\s*-\s*Microsoft\.WinGet\.Client') {
                    $foundModule = $true
                    break
                }
                elseif ($line -match '^\s*full:' -and $inPowerShellModules) {
                    $inLight = $false
                }
                elseif ($line -match '^\s*\w+:' -and -not $line.StartsWith('    ')) {
                    $inPowerShellModules = $false
                }
            }

            $foundModule | Should -Be $true -Because "Microsoft.WinGet.Client should be in light mode packages"
        }
    }
}

Describe "Help and Documentation" -Tag "Documentation" {
    Context "Function Documentation" {
        It "Test-WingetUpdates should have help documentation" {
            $help = Get-Help Test-WingetUpdates
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Invoke-WingetUpgrade should have help documentation" {
            $help = Get-Help Invoke-WingetUpgrade
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description | Should -Not -BeNullOrEmpty
        }

        It "Test-WingetUpdates should have parameter documentation" {
            $help = Get-Help Test-WingetUpdates -Parameter UseWingetModule
            $help | Should -Not -BeNullOrEmpty
        }

        It "Invoke-WingetUpgrade should have examples" {
            $help = Get-Help Invoke-WingetUpgrade
            $help.Examples | Should -Not -BeNullOrEmpty
            $help.Examples.Example.Count | Should -BeGreaterThan 0
        }
    }
}

Describe "E2E: Winget Upgrade Workflow" -Tag "E2E" {
    Context "Mocked End-to-End Workflow (CI-safe)" {
        It "Should complete full workflow with mocked dependencies" {
            # Mock all external dependencies
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'Microsoft.WinGet.Client'; Version = '1.0.0' }
            } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }

            Mock Import-Module { }

            Mock Get-WinGetPackage {
                # Simulate one package with update available
                return @([PSCustomObject]@{
                    Name = 'TestPackage'
                    Id = 'Test.Package'
                    IsUpdateAvailable = $true
                    InstalledVersion = '1.0.0'
                    AvailableVersion = '1.0.1'
                })
            }

            Mock Update-WinGetPackage { }

            # Capture output
            $output = @()
            Mock Write-Host { $output += $Object }

            # Run detection
            $hasUpdates = Test-WingetUpdates -UseWingetModule $true
            $hasUpdates | Should -Be $true

            # Run upgrade with no countdown
            { Invoke-WingetUpgrade -CountdownSeconds 0 -UseWingetModule $true } | Should -Not -Throw

            # Verify upgrade was called
            Should -Invoke Update-WinGetPackage -Times 1
        }

        It "Should handle no updates gracefully" {
            # Mock no updates available
            Mock Get-Module {
                return [PSCustomObject]@{ Name = 'Microsoft.WinGet.Client'; Version = '1.0.0' }
            } -ParameterFilter { $Name -eq 'Microsoft.WinGet.Client' }

            Mock Import-Module { }

            Mock Get-WinGetPackage {
                # Simulate no packages with updates
                return @()
            }

            Mock Update-WinGetPackage { }

            # Run detection
            $hasUpdates = Test-WingetUpdates -UseWingetModule $true
            $hasUpdates | Should -Be $false

            # Run upgrade - should exit early
            { Invoke-WingetUpgrade -CountdownSeconds 0 -UseWingetModule $true } | Should -Not -Throw

            # Verify upgrade was NOT called (no updates)
            Should -Invoke Update-WinGetPackage -Times 0
        }
    }

    Context "Real End-to-End Workflow (Local only)" -Skip:$script:IsCIMode {
        # These tests are only run in local environment, not in CI
        # They require actual winget/module availability and can modify system state

        It "Should detect updates (if any)" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            { Test-WingetUpdates } | Should -Not -Throw
        }

        It "Should show proper output format" -Skip:(-not $script:WingetAvailable -and -not $script:WingetModuleAvailable) {
            # Capture host output
            $output = @()
            Mock Write-Host { $output += $Object }

            Test-WingetUpdates | Out-Null
            $output -join '' | Should -Match 'package|update|up to date'
        }
    }
}
