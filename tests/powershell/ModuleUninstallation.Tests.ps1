#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:RepoRoot 'home\dot_config\powershell\modules\DotfilesHelpers\Public\ModuleInstallation.ps1')
    Import-Module PowerShellGet -ErrorAction Stop

    function Invoke-TestModuleHost {
        param(
            [switch]$NoProfile,
            [switch]$NonInteractive,
            [string]$OutputFormat,
            [string]$ExecutionPolicy,
            [string]$EncodedCommand
        )
    }
}

Describe "Uninstall-PowerShellModule" -Tag "Unit" {
    BeforeEach {
        $script:OriginalOS = $env:OS
        $script:OriginalExitCode = $global:LASTEXITCODE
        $env:OS = 'Windows_NT'
        $script:ModulePresent = $true

        Mock Get-Module {
            if ($ListAvailable -and $script:ModulePresent) {
                [pscustomobject]@{ Name = 'oh-my-posh'; Version = '2.0.0' }
                [pscustomobject]@{ Name = 'oh-my-posh'; Version = '3.0.0' }
            }
        } -ParameterFilter { $Name -eq 'oh-my-posh' }
        Mock Uninstall-Module { $script:ModulePresent = $false }
        Mock Remove-Module {}
        Mock Write-Host {}
        Mock Get-Command { $null } -ParameterFilter { $Name -in 'pwsh.exe', 'powershell.exe' }
        Mock Invoke-TestModuleHost { $global:LASTEXITCODE = 0 }
    }

    AfterEach {
        $env:OS = $script:OriginalOS
        $global:LASTEXITCODE = $script:OriginalExitCode
    }

    It "Is exported by DotfilesHelpers" {
        $manifest = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'home\dot_config\powershell\modules\DotfilesHelpers\DotfilesHelpers.psd1')
        $manifest.FunctionsToExport | Should -Contain 'Uninstall-PowerShellModule'
    }

    It "Uninstalls all versions of exactly the requested module" {
        Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

        Should -Invoke Uninstall-Module -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'oh-my-posh' -and $AllVersions -and $Force -and $ErrorAction -eq 'Stop'
        }
    }

    It "Skips an absent module" {
        $script:ModulePresent = $false

        Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

        Should -Invoke Uninstall-Module -Times 0 -Exactly
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like '[[]SKIP[]] Module*' }
    }

    It "Does not uninstall again on a second run" {
        Uninstall-PowerShellModule -ModuleName 'oh-my-posh'
        Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

        Should -Invoke Uninstall-Module -Times 1 -Exactly
    }

    It "Unloads the module before uninstalling" {
        Mock Get-Module { New-Module -Name 'oh-my-posh' -ScriptBlock {} } -ParameterFilter {
            $Name -eq 'oh-my-posh' -and -not $ListAvailable
        }
        Mock Uninstall-Module {
            Should -Invoke Remove-Module -Times 1 -Exactly
            $script:ModulePresent = $false
        }

        Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

        Should -Invoke Remove-Module -Times 1 -Exactly -ParameterFilter { $Force -and $ErrorAction -eq 'Stop' }
    }

    It "Propagates uninstall errors" {
        Mock Uninstall-Module { throw 'Access denied' }

        { Uninstall-PowerShellModule -ModuleName 'oh-my-posh' } | Should -Throw '*Access denied*'
    }

    It "Rejects a successful command that leaves the module installed" {
        Mock Uninstall-Module {}

        { Uninstall-PowerShellModule -ModuleName 'oh-my-posh' } | Should -Throw '*still available*'
    }

    It "Propagates discovery errors instead of treating them as absence" {
        Mock Get-Module { throw 'Cannot read module directory' } -ParameterFilter { $Name -eq 'oh-my-posh' }

        { Uninstall-PowerShellModule -ModuleName 'oh-my-posh' } | Should -Throw '*Cannot read module directory*'
        Should -Invoke Uninstall-Module -Times 0 -Exactly
    }

    It "Does not make changes or start another host with WhatIf" {
        Uninstall-PowerShellModule -ModuleName 'oh-my-posh' -WhatIf

        Should -Invoke Uninstall-Module -Times 0 -Exactly
        Should -Invoke Remove-Module -Times 0 -Exactly
        Should -Invoke Invoke-TestModuleHost -Times 0 -Exactly
    }

    It "Rejects unsafe module name '<Name>'" -TestCases @(
        @{ Name = '*' }
        @{ Name = 'oh-my-*' }
        @{ Name = "../oh-my-posh" }
        @{ Name = "oh-my-posh'; throw 'injected" }
    ) {
        param($Name)

        { Uninstall-PowerShellModule -ModuleName $Name } | Should -Throw
        Should -Invoke Uninstall-Module -Times 0 -Exactly
        Should -Invoke Invoke-TestModuleHost -Times 0 -Exactly
    }

    Context "Other PowerShell host" {
        BeforeEach {
            Mock Get-Command { [pscustomobject]@{ Source = 'Invoke-TestModuleHost' } } -ParameterFilter {
                $Name -in 'pwsh.exe', 'powershell.exe'
            }
        }

        It "Runs the same uninstall logic in a clean process for the other host" {
            Mock Invoke-TestModuleHost {
                $script:ModulePresent = $true
                $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($EncodedCommand))
                & ([scriptblock]::Create($command))
                $global:LASTEXITCODE = 0
            }

            Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

            Should -Invoke Uninstall-Module -Times 2 -Exactly
            Should -Invoke Invoke-TestModuleHost -Times 1 -Exactly -ParameterFilter {
                $NoProfile -and $NonInteractive -and $OutputFormat -eq 'Text' -and $ExecutionPolicy -eq 'Bypass'
            }
            $expectedHost = if ($PSVersionTable.PSVersion.Major -lt 7) { 'pwsh.exe' } else { 'powershell.exe' }
            Should -Invoke Get-Command -Times 1 -Exactly -ParameterFilter {
                $Name -eq $expectedHost -and $CommandType -eq 'Application'
            }
        }

        It "Still checks the other host when the module is absent in the current host" {
            $script:ModulePresent = $false

            Uninstall-PowerShellModule -ModuleName 'oh-my-posh'

            Should -Invoke Invoke-TestModuleHost -Times 1 -Exactly
        }

        It "Reports the other host's failure" {
            Mock Invoke-TestModuleHost { $global:LASTEXITCODE = 1 }

            { Uninstall-PowerShellModule -ModuleName 'oh-my-posh' } | Should -Throw '*exit code 1*'
        }
    }
}
