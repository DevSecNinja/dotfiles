#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Navigation functions in the DotfilesHelpers module.

.DESCRIPTION
    Tests Set-LocationUp and Set-LocationUpUp - they should change the current
    working directory up one or two levels respectively.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:TestRoot = New-Item -ItemType Directory -Path (Join-Path $tmpRoot "navigation-tests-$(Get-Random)") -Force
    $script:TestNested = New-Item -ItemType Directory -Path (Join-Path $script:TestRoot.FullName "level1/level2") -Force
}

AfterAll {
    Pop-Location
    if (Test-Path $script:TestRoot) {
        Remove-Item -Recurse -Force $script:TestRoot.FullName -ErrorAction SilentlyContinue
    }
}

Describe "Set-LocationUp Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Set-LocationUp -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should change to the parent directory" {
        $start = $script:TestNested.FullName
        $expected = (Resolve-Path (Join-Path $start '..')).Path

        $original = Get-Location
        try {
            Set-Location $start
            Set-LocationUp
            (Get-Location).Path | Should -Be $expected
        }
        finally {
            Set-Location $original
        }
    }
}

Describe "Set-LocationUpUp Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Set-LocationUpUp -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should change two directories up" {
        $start = $script:TestNested.FullName
        $expected = (Resolve-Path (Join-Path $start '../..')).Path

        $original = Get-Location
        try {
            Set-Location $start
            Set-LocationUpUp
            (Get-Location).Path | Should -Be $expected
        }
        finally {
            Set-Location $original
        }
    }
}
