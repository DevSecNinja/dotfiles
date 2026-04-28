#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for ChezmoiUtilities functions in DotfilesHelpers module.

.DESCRIPTION
    Tests Reset-ChezmoiScripts, Reset-ChezmoiEntries, and Invoke-ChezmoiSigning.
    Mocks the external 'chezmoi' command to validate function behaviour without
    requiring chezmoi to be installed.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking
}

AfterAll {
    Pop-Location
}

Describe "Reset-ChezmoiScripts" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Reset-ChezmoiScripts -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should call 'chezmoi state delete-bucket --bucket=scriptState'" {
        $body = (Get-Command Reset-ChezmoiScripts).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+state\s+delete-bucket'
        $body | Should -Match 'scriptState'
    }
}

Describe "Reset-ChezmoiEntries" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Reset-ChezmoiEntries -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function body should call 'chezmoi state delete-bucket --bucket=entryState'" {
        $body = (Get-Command Reset-ChezmoiEntries).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+state\s+delete-bucket'
        $body | Should -Match 'entryState'
    }

    It "Function body should warn user about reprocessing all files" {
        $body = (Get-Command Reset-ChezmoiEntries).ScriptBlock.ToString()
        $body | Should -Match 'Warning'
        $body | Should -Match 'dry-run'
    }
}

Describe "Invoke-ChezmoiSigning" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Invoke-ChezmoiSigning -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should accept CertificateThumbprint parameter with a default value" {
        $cmd = Get-Command Invoke-ChezmoiSigning
        $cmd.Parameters.ContainsKey('CertificateThumbprint') | Should -Be $true
    }

    It "Should call 'chezmoi source-path' to determine source directory" {
        $body = (Get-Command Invoke-ChezmoiSigning).ScriptBlock.ToString()
        $body | Should -Match 'chezmoi\s+source-path'
    }

    It "Should reference Sign-PowerShellScripts.ps1 signing helper" {
        $body = (Get-Command Invoke-ChezmoiSigning).ScriptBlock.ToString()
        $body | Should -Match 'Sign-PowerShellScripts\.ps1'
    }
}
