#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for SystemUtilities functions in the DotfilesHelpers module.

.DESCRIPTION
    Tests Unix-style helper functions: which, touch, mkcd.
    Each function is exercised against a temporary working directory.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:TestDir = New-Item -ItemType Directory -Path (Join-Path $tmpRoot "system-utils-tests-$(Get-Random)") -Force
}

AfterAll {
    Pop-Location
    if (Test-Path $script:TestDir) {
        Remove-Item -Recurse -Force $script:TestDir.FullName -ErrorAction SilentlyContinue
    }
}

Describe "which Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command which -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should return the source path for an existing command" {
        # 'pwsh' is guaranteed to exist (we are running under it)
        $result = which pwsh
        $result | Should -Not -BeNullOrEmpty
        $result | Should -Match 'pwsh'
    }

    It "Should return nothing (empty) for a non-existent command" {
        $result = which "this-command-definitely-does-not-exist-$(Get-Random)"
        # Should be null or empty (Select-Object -ExpandProperty on empty pipeline)
        ($null -eq $result) -or ($result -eq '') | Should -Be $true
    }
}

Describe "touch Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command touch -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should create a new file when it does not exist" {
        $newFile = Join-Path $script:TestDir.FullName "new-file-$(Get-Random).txt"
        (Test-Path $newFile) | Should -Be $false
        touch $newFile
        (Test-Path $newFile) | Should -Be $true
    }

    It "Should update LastWriteTime when file already exists" {
        $existingFile = Join-Path $script:TestDir.FullName "existing-file-$(Get-Random).txt"
        New-Item -ItemType File -Path $existingFile | Out-Null
        # Set LastWriteTime to the past
        (Get-Item $existingFile).LastWriteTime = (Get-Date).AddDays(-1)
        $before = (Get-Item $existingFile).LastWriteTime

        Start-Sleep -Milliseconds 50
        touch $existingFile

        $after = (Get-Item $existingFile).LastWriteTime
        $after | Should -BeGreaterThan $before
    }
}

Describe "mkcd Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command mkcd -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should create the directory and change into it" {
        $newDir = Join-Path $script:TestDir.FullName "mkcd-$(Get-Random)"
        (Test-Path $newDir) | Should -Be $false

        $originalLocation = Get-Location
        try {
            mkcd $newDir
            (Test-Path $newDir) | Should -Be $true
            # Resolve current location and target to compare on the same form.
            $current = (Get-Location).Path
            $expected = (Resolve-Path $newDir).Path
            $current | Should -Be $expected
        }
        finally {
            Set-Location $originalLocation
        }
    }

    It "Should not throw when directory already exists (idempotent)" {
        $existingDir = Join-Path $script:TestDir.FullName "mkcd-existing-$(Get-Random)"
        New-Item -ItemType Directory -Path $existingDir -Force | Out-Null

        $originalLocation = Get-Location
        try {
            { mkcd $existingDir } | Should -Not -Throw
        }
        finally {
            Set-Location $originalLocation
        }
    }
}
