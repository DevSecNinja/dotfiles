#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for Dev Drive detection in the DotfilesHelpers module.

.DESCRIPTION
    Tests Get-DevDrivePath and Get-ProjectsPath - detection of a Dev Drive
    (fixed ReFS volume) and resolution of the projects folder, including the
    DEV_DRIVE / PROJECTS_PATH overrides and the user profile fallback.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    $script:OriginalDevDrive = $env:DEV_DRIVE
    $script:OriginalProjectsPath = $env:PROJECTS_PATH

    $tmpRoot = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
    $script:TestRoot = (New-Item -ItemType Directory -Path (Join-Path $tmpRoot "devdrive-tests-$(Get-Random)") -Force).FullName
}

AfterAll {
    $env:DEV_DRIVE = $script:OriginalDevDrive
    $env:PROJECTS_PATH = $script:OriginalProjectsPath

    Pop-Location
    if (Test-Path $script:TestRoot) {
        Remove-Item -Recurse -Force $script:TestRoot -ErrorAction SilentlyContinue
    }
}

Describe "Get-DevDrivePath Function" -Tag "Unit" {
    BeforeEach {
        $env:DEV_DRIVE = $null
        $env:PROJECTS_PATH = $null
    }

    It "Should be available as a function" {
        Get-Command Get-DevDrivePath -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should not throw" {
        { Get-DevDrivePath } | Should -Not -Throw
    }

    It "Should return existing paths only" {
        foreach ($path in @(Get-DevDrivePath)) {
            Test-Path -LiteralPath $path | Should -BeTrue
        }
    }

    It "Should honour DEV_DRIVE when the path exists" {
        $env:DEV_DRIVE = $script:TestRoot

        @(Get-DevDrivePath) | Should -Be @($script:TestRoot)
    }

    It "Should ignore DEV_DRIVE when the path does not exist" {
        $env:DEV_DRIVE = Join-Path $script:TestRoot "does-not-exist"

        @(Get-DevDrivePath) | Should -Not -Contain $env:DEV_DRIVE
    }
}

Describe "Get-ProjectsPath Function" -Tag "Unit" {
    BeforeEach {
        $env:DEV_DRIVE = $null
        $env:PROJECTS_PATH = $null
    }

    It "Should be available as a function" {
        Get-Command Get-ProjectsPath -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should honour PROJECTS_PATH above everything else" {
        $env:DEV_DRIVE = $script:TestRoot
        $env:PROJECTS_PATH = Join-Path $script:TestRoot "explicit"

        Get-ProjectsPath | Should -Be $env:PROJECTS_PATH
    }

    It "Should return the Dev Drive projects folder when it exists" {
        $env:DEV_DRIVE = $script:TestRoot
        $expected = Join-Path $script:TestRoot "projects"
        New-Item -ItemType Directory -Path $expected -Force | Out-Null

        try {
            Get-ProjectsPath | Should -Be $expected
        }
        finally {
            Remove-Item -Recurse -Force $expected -ErrorAction SilentlyContinue
        }
    }

    It "Should fall back to the user profile when the Dev Drive has no projects folder" {
        $env:DEV_DRIVE = $script:TestRoot
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }

        Get-ProjectsPath | Should -Be (Join-Path $userHome "projects")
    }

    It "Should not create anything without -CreateIfMissing" {
        $env:DEV_DRIVE = $script:TestRoot

        Get-ProjectsPath | Out-Null

        Test-Path -LiteralPath (Join-Path $script:TestRoot "projects") | Should -BeFalse
    }

    It "Should create the Dev Drive projects folder with -CreateIfMissing" {
        $env:DEV_DRIVE = $script:TestRoot
        $expected = Join-Path $script:TestRoot "projects"

        try {
            Get-ProjectsPath -CreateIfMissing | Should -Be $expected
            Test-Path -LiteralPath $expected | Should -BeTrue
        }
        finally {
            Remove-Item -Recurse -Force $expected -ErrorAction SilentlyContinue
        }
    }
}

Describe "DevDrive module exports" -Tag "Unit" {
    BeforeAll {
        $script:ManifestPath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/DotfilesHelpers.psd1"
        $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    }

    It "Should export <_> from the module manifest" -ForEach @('Test-DevDriveSupported', 'Get-DevDrivePath', 'Get-ProjectsPath') {
        $script:Manifest.FunctionsToExport | Should -Contain $_
    }

    It "Should not contain non-ASCII characters" {
        $content = Get-Content (Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers/Public/DevDrive.ps1") -Raw
        $content | Should -Not -Match '[^\x00-\x7F]'
    }
}
