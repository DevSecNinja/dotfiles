#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for install.ps1 (Windows installation script).

.DESCRIPTION
    Tests the structure and behavior of the installation entry-point. Avoids
    actually running winget/chezmoi by inspecting the script content. Also
    verifies the Test-Interactive helper handles common CI environment
    variables correctly.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $script:RootInstallPath = Join-Path $script:RepoRoot "install.ps1"
    $script:HomeInstallPath = Join-Path $script:RepoRoot "home/install.ps1"
}

AfterAll {
    Pop-Location
}

Describe "install.ps1 (root wrapper)" -Tag "Unit" {
    It "Should exist" {
        $script:RootInstallPath | Should -Exist
    }

    It "Should require PowerShell 5.1" {
        $content = Get-Content $script:RootInstallPath -Raw
        $content | Should -Match '#Requires\s+-Version\s+5\.1'
    }

    It "Should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:RootInstallPath, [ref]$null, [ref]$errors
        ) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "Should delegate to home/install.ps1" {
        $content = Get-Content $script:RootInstallPath -Raw
        $content | Should -Match 'home[\\/]install\.ps1'
    }

    It "Should forward arguments via splat" {
        $content = Get-Content $script:RootInstallPath -Raw
        $content | Should -Match '@args'
    }
}

Describe "home/install.ps1" -Tag "Unit" {
    BeforeAll {
        $script:Content = Get-Content $script:HomeInstallPath -Raw
    }

    It "Should exist" {
        $script:HomeInstallPath | Should -Exist
    }

    It "Should require PowerShell 5.1" {
        $script:Content | Should -Match '#Requires\s+-Version\s+5\.1'
    }

    It "Should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:HomeInstallPath, [ref]$null, [ref]$errors
        ) | Out-Null
        $errors.Count | Should -Be 0
    }

    It "Should accept ChezmoiVersion parameter" {
        $script:Content | Should -Match '\[string\]\$ChezmoiVersion'
    }

    It "Should detect winget availability before installing" {
        $script:Content | Should -Match 'Get-Command\s+winget'
    }

    It "Should check if chezmoi is already installed (idempotency)" {
        $script:Content | Should -Match 'Get-Command\s+chezmoi'
    }

    It "Should install chezmoi via winget" {
        $script:Content | Should -Match 'winget\s+install'
        $script:Content | Should -Match 'twpayne\.chezmoi'
    }

    It "Should accept package and source agreements unattended" {
        $script:Content | Should -Match '--accept-source-agreements'
        $script:Content | Should -Match '--accept-package-agreements'
    }

    It "Should run 'chezmoi init --apply' to provision dotfiles" {
        $script:Content | Should -Match 'init'
        $script:Content | Should -Match '--apply'
    }

    It "Should detect non-interactive (CI) environments" {
        # The script should check for CI/GITHUB_ACTIONS/TF_BUILD, then add --no-tty
        $script:Content | Should -Match 'CI'
        $script:Content | Should -Match 'GITHUB_ACTIONS'
        $script:Content | Should -Match '--no-tty'
    }

    It "Should set ErrorActionPreference to Stop" {
        $script:Content | Should -Match '\$ErrorActionPreference\s*=\s*["'']Stop["'']'
    }
}

Describe "Test-Interactive helper in home/install.ps1" -Tag "Unit" {
    BeforeAll {
        # Extract and dot-source only the Test-Interactive function definition
        $content = Get-Content $script:HomeInstallPath -Raw
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $content, [ref]$null, [ref]$errors
        )
        $funcAst = $ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Test-Interactive'
            }, $true) | Select-Object -First 1

        if ($null -eq $funcAst) {
            throw "Could not find Test-Interactive function definition in $script:HomeInstallPath"
        }

        # Define the function in the test scope
        Invoke-Expression $funcAst.Extent.Text
    }

    It "Should return \$false when CI=true" {
        $original = $env:CI
        $env:CI = "true"
        try {
            Test-Interactive | Should -Be $false
        }
        finally {
            if ($null -eq $original) { Remove-Item Env:CI -ErrorAction SilentlyContinue } else { $env:CI = $original }
        }
    }

    It "Should return \$false when GITHUB_ACTIONS=true" {
        $originalCi = $env:CI
        $originalGh = $env:GITHUB_ACTIONS
        Remove-Item Env:CI -ErrorAction SilentlyContinue
        $env:GITHUB_ACTIONS = "true"
        try {
            Test-Interactive | Should -Be $false
        }
        finally {
            if ($null -eq $originalGh) { Remove-Item Env:GITHUB_ACTIONS -ErrorAction SilentlyContinue } else { $env:GITHUB_ACTIONS = $originalGh }
            if ($null -ne $originalCi) { $env:CI = $originalCi }
        }
    }

    It "Should return \$false when TF_BUILD=true" {
        $originalCi = $env:CI
        $originalTf = $env:TF_BUILD
        Remove-Item Env:CI -ErrorAction SilentlyContinue
        $env:TF_BUILD = "true"
        try {
            Test-Interactive | Should -Be $false
        }
        finally {
            if ($null -eq $originalTf) { Remove-Item Env:TF_BUILD -ErrorAction SilentlyContinue } else { $env:TF_BUILD = $originalTf }
            if ($null -ne $originalCi) { $env:CI = $originalCi }
        }
    }
}
