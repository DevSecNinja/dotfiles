#Requires -Version 7.0
<#
.SYNOPSIS
    Tests the Surface Laptop power-button configuration.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot `
        "home\.chezmoiscripts\windows\run_onchange_disable-surface-laptop-power-button.ps1.tmpl"

    $scriptContent = Get-Content -LiteralPath $script:ScriptPath -Raw
    . ([scriptblock]::Create($scriptContent)) -SkipApply
}

Describe "Surface Laptop power button script" -Tag "Unit" {
    It "exists and has valid PowerShell syntax" {
        $script:ScriptPath | Should -Exist

        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:ScriptPath,
            [ref]$null,
            [ref]$errors
        ) | Out-Null

        $errors | Should -BeNullOrEmpty
    }

    It "is limited to the Windows full profile" {
        $content = Get-Content -LiteralPath $script:ScriptPath -Raw

        $content | Should -Match 'eq \.chezmoi\.os "windows"'
        $content | Should -Match 'eq \.installType "full"'
    }

    It "recognizes Microsoft Surface Laptop models" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Laptop 7th Edition"
            }) | Should -BeTrue
    }

    It "recognizes the Surface Laptop 7 SMBIOS model" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Microsoft Surface Laptop, 7th Edition"
            }) | Should -BeTrue
    }

    It "recognizes Surface Laptop Studio models" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Laptop Studio 2"
            }) | Should -BeTrue
    }

    It "does not match other Surface form factors" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Microsoft Corporation"
                Model        = "Surface Pro 11th Edition"
            }) | Should -BeFalse
    }

    It "requires Microsoft as the manufacturer" {
        Test-SurfaceLaptop -ComputerSystem ([pscustomobject]@{
                Manufacturer = "Contoso"
                Model        = "Surface Laptop 7"
            }) | Should -BeFalse
    }

    It "does not invoke powercfg on non-Surface hardware" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Dell Inc."
                    Model        = "XPS 13"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            }

        $result.Status | Should -Be "NotSurfaceLaptop"
        $result.Changed | Should -BeFalse
        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "disables the current plan power button action for AC and battery power" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Microsoft Corporation"
                    Model        = "Surface Laptop 7"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            }

        $result.Status | Should -Be "Disabled"
        $result.Changed | Should -BeTrue
        $script:PowerCfgCalls.Count | Should -Be 3
        $script:PowerCfgCalls[0] -join " " | Should -Be (
            "/SETACVALUEINDEX SCHEME_CURRENT " +
            "4f971e89-eebd-4455-a8de-9e59040e7347 " +
            "7648efa3-dd9c-4e3e-b566-50f929386280 0"
        )
        $script:PowerCfgCalls[1] -join " " | Should -Be (
            "/SETDCVALUEINDEX SCHEME_CURRENT " +
            "4f971e89-eebd-4455-a8de-9e59040e7347 " +
            "7648efa3-dd9c-4e3e-b566-50f929386280 0"
        )
        $script:PowerCfgCalls[2] -join " " | Should -Be "/SETACTIVE SCHEME_CURRENT"
    }

    It "does not invoke powercfg under WhatIf" {
        $script:PowerCfgCalls = @()

        $result = Disable-SurfaceLaptopPowerButton `
            -GetComputerSystem {
                [pscustomobject]@{
                    Manufacturer = "Microsoft Corporation"
                    Model        = "Surface Laptop 7"
                }
            } `
            -InvokePowerCfg {
                param([string[]]$ArgumentList)
                $script:PowerCfgCalls += , $ArgumentList
            } `
            -WhatIf

        $result.Status | Should -Be "WhatIf"
        $result.Changed | Should -BeFalse
        $script:PowerCfgCalls | Should -BeNullOrEmpty
    }

    It "propagates powercfg failures" {
        {
            Disable-SurfaceLaptopPowerButton `
                -GetComputerSystem {
                    [pscustomobject]@{
                        Manufacturer = "Microsoft Corporation"
                        Model        = "Surface Laptop 7"
                    }
                } `
                -InvokePowerCfg {
                    throw "powercfg failed"
                }
        } | Should -Throw "*powercfg failed*"
    }
}
