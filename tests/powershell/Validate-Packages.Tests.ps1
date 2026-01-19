#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for packages.yaml validation.

.DESCRIPTION
    Tests YAML syntax and structure of the packages.yaml configuration file.
    Validates that required sections exist and platform-specific packages are defined.

.NOTES
    This replaces the bash script scripts/validate-packages.sh with Pester tests.
#>

BeforeAll {
    # Setup: Navigate to repository root
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:PackagesFile = Join-Path $script:RepoRoot "home\.chezmoidata\packages.yaml"
}

Describe "Packages YAML Validation" -Tag "Validation", "YAML" {

    Context "File Existence" {
        It "packages.yaml file should exist" {
            Test-Path $script:PackagesFile | Should -Be $true
        }

        It "packages.yaml should not be empty" {
            if (Test-Path $script:PackagesFile) {
                (Get-Content $script:PackagesFile -Raw).Trim() | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "YAML Syntax" {
        It "packages.yaml should have valid YAML syntax" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Try to parse YAML using PowerShell-Yaml if available, otherwise use basic checks
            $yamlModule = Get-Module -Name powershell-yaml -ListAvailable

            if ($yamlModule) {
                Import-Module powershell-yaml -ErrorAction Stop
                {
                    $content = Get-Content $script:PackagesFile -Raw
                    $null = ConvertFrom-Yaml $content
                } | Should -Not -Throw
            }
            else {
                # Basic YAML validation - check it can be read
                { Get-Content $script:PackagesFile -ErrorAction Stop } | Should -Not -Throw

                # Check for basic YAML structure
                $content = Get-Content $script:PackagesFile -Raw
                $content | Should -Not -BeNullOrEmpty

                # YAML files should not have tabs (spaces only)
                $content | Should -Not -Match "`t"
            }
        }
    }

    Context "Required Sections" {
        BeforeAll {
            if (Test-Path $script:PackagesFile) {
                $script:PackagesContent = Get-Content $script:PackagesFile -Raw
            }
        }

        It "should contain 'packages' section" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            $script:PackagesContent | Should -Match '(?m)^packages:'
        }
    }

    Context "Platform Definitions" {
        BeforeAll {
            if (Test-Path $script:PackagesFile) {
                $script:PackagesContent = Get-Content $script:PackagesFile -Raw
            }
        }

        It "should contain Linux platform definition" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Check if linux is mentioned in the file
            $script:PackagesContent | Should -Match 'linux:'
        }

        It "should contain macOS/Darwin platform definition" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Check if darwin is mentioned in the file
            $script:PackagesContent | Should -Match 'darwin:'
        }

        It "should contain Windows platform definition" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Check if windows is mentioned in the file
            $script:PackagesContent | Should -Match 'windows:'
        }
    }

    Context "YAML Structure" {
        BeforeAll {
            if (Test-Path $script:PackagesFile) {
                $script:PackagesContent = Get-Content $script:PackagesFile -Raw
            }
        }

        It "should use consistent indentation" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Check that indentation uses spaces, not tabs
            $script:PackagesContent | Should -Not -Match "`t"
        }

        It "should not have trailing whitespace" {
            if (-not (Test-Path $script:PackagesFile)) {
                Set-ItResult -Skipped -Because "packages.yaml not found"
                return
            }

            # Check each line for trailing whitespace
            $lines = $script:PackagesContent -split "`n"
            $linesWithTrailing = $lines | Where-Object { $_ -match ' $' }

            $linesWithTrailing.Count | Should -Be 0 -Because "YAML should not have trailing whitespace"
        }
    }
}
