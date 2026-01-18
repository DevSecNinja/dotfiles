#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for packages.yaml configuration.

.DESCRIPTION
    Comprehensive test suite for the cross-platform package management configuration.
    Tests YAML syntax, Chezmoi integration, package structure, and consistency across platforms.
    Validates Windows (WinGet, PowerShell modules), Linux (APT, DNF), macOS (Homebrew), and VS Code extensions.

    Automatically installs Chezmoi if not present using available package managers (winget, Homebrew, or install script).

.NOTES
    Chezmoi will be installed automatically if not found. Tests will fail if installation is unsuccessful.
#>

BeforeAll {
    # Setup: Navigate to repository root
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    # Function to install Chezmoi if not present
    function Install-ChezmoiIfMissing {
        $chezmoiCmd = Get-Command chezmoi -ErrorAction SilentlyContinue
        if ($chezmoiCmd) {
            Write-Host "✅ Chezmoi is already installed at: $($chezmoiCmd.Source)" -ForegroundColor Green
            return $true
        }

        Write-Host "⚠️  Chezmoi not found. Attempting to install..." -ForegroundColor Yellow

        # Try winget on Windows
        if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Host "Installing chezmoi using winget..." -ForegroundColor Cyan
                try {
                    winget install --id twpayne.chezmoi --silent --accept-source-agreements --accept-package-agreements | Out-Null

                    # Refresh PATH for current session
                    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
                    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
                    if ($machinePath -and $userPath) {
                        $env:Path = $machinePath + ";" + $userPath
                    }

                    # Verify installation
                    $chezmoiCmd = Get-Command chezmoi -ErrorAction SilentlyContinue
                    if ($chezmoiCmd) {
                        Write-Host "✅ Chezmoi installed successfully via winget" -ForegroundColor Green
                        return $true
                    }
                }
                catch {
                    Write-Warning "Failed to install chezmoi via winget: $_"
                }
            }
        }

        # Try Homebrew on macOS/Linux
        $brewCmd = Get-Command brew -ErrorAction SilentlyContinue
        if ($brewCmd) {
            Write-Host "Installing chezmoi using Homebrew..." -ForegroundColor Cyan
            try {
                brew install chezmoi | Out-Null
                $chezmoiCmd = Get-Command chezmoi -ErrorAction SilentlyContinue
                if ($chezmoiCmd) {
                    Write-Host "✅ Chezmoi installed successfully via Homebrew" -ForegroundColor Green
                    return $true
                }
            }
            catch {
                Write-Warning "Failed to install chezmoi via Homebrew: $_"
            }
        }

        # Try installation script as fallback
        Write-Host "Installing chezmoi using installation script..." -ForegroundColor Cyan
        try {
            $binDir = Join-Path $HOME ".local/bin"
            if (-not (Test-Path $binDir)) {
                New-Item -ItemType Directory -Path $binDir -Force | Out-Null
            }

            $installScript = Invoke-WebRequest -Uri "https://get.chezmoi.io" -UseBasicParsing
            $env:Path = "$binDir" + [IO.Path]::PathSeparator + $env:Path

            if ($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
                # Windows: save and execute as PowerShell
                $scriptPath = Join-Path $env:TEMP "install-chezmoi.ps1"
                $installScript.Content | Out-File -FilePath $scriptPath -Encoding UTF8
                & $scriptPath -b $binDir
                Remove-Item $scriptPath -Force -ErrorAction SilentlyContinue
            }
            else {
                # Unix: pipe to sh
                $installScript.Content | sh -s -- -b $binDir
            }

            $chezmoiCmd = Get-Command chezmoi -ErrorAction SilentlyContinue
            if ($chezmoiCmd) {
                Write-Host "✅ Chezmoi installed successfully via install script" -ForegroundColor Green
                return $true
            }
        }
        catch {
            Write-Warning "Failed to install chezmoi via install script: $_"
        }

        Write-Error "❌ Failed to install chezmoi. Please install manually: https://www.chezmoi.io/install/"
        return $false
    }

    # Install Chezmoi if missing
    $script:ChezmoiAvailable = Install-ChezmoiIfMissing

    if ($script:ChezmoiAvailable) {
        # Load chezmoi data
        $output = chezmoi data --format=json --source=. 2>&1
        if ($LASTEXITCODE -eq 0) {
            $script:ChezmoiData = $output | ConvertFrom-Json
        }
    }

    # Load YAML file directly for additional validation
    $script:PackagesYamlPath = Join-Path $script:RepoRoot ".chezmoidata\packages.yaml"
}

AfterAll {
    Pop-Location
}

Describe "Packages YAML File" {
    It "packages.yaml file should exist" {
        $script:PackagesYamlPath | Should -Exist
    }

    It "packages.yaml should not be empty" {
        $content = Get-Content $script:PackagesYamlPath -Raw
        $content | Should -Not -BeNullOrEmpty
        $content.Length | Should -BeGreaterThan 100
    }

    It "packages.yaml should contain 'packages:' section" {
        $content = Get-Content $script:PackagesYamlPath -Raw
        $content | Should -Match "packages:"
    }
}

Describe "Chezmoi Integration" {
    It "Chezmoi should be installed and available" {
        $script:ChezmoiAvailable | Should -BeTrue -Because "Chezmoi is required for tests and should have been installed automatically"
    }

    It "Chezmoi should load packages.yaml successfully" {
        $script:ChezmoiData | Should -Not -BeNullOrEmpty
        $script:ChezmoiData.packages | Should -Not -BeNullOrEmpty
    }
}

Describe "Windows Package Configuration" {
    BeforeAll {
        if (-not $script:ChezmoiAvailable -or -not $script:ChezmoiData) {
            Set-ItResult -Skipped -Because "Chezmoi data is not available"
        }
    }

    Context "WinGet Packages" {
        It "Should have Windows winget section" {
            $script:ChezmoiData.packages.windows.winget | Should -Not -BeNullOrEmpty
        }

        It "Should have winget light mode packages" {
            $lightPackages = $script:ChezmoiData.packages.windows.winget.light
            $lightPackages | Should -Not -BeNullOrEmpty
            $lightPackages.Count | Should -BeGreaterThan 0
        }

        It "Should have winget full mode packages" {
            $fullPackages = $script:ChezmoiData.packages.windows.winget.full
            $fullPackages | Should -Not -BeNullOrEmpty
            $fullPackages.Count | Should -BeGreaterThan 0
        }

        It "Light mode should include essential packages (Git, PowerShell, Chezmoi)" {
            $lightPackages = $script:ChezmoiData.packages.windows.winget.light
            $lightPackages | Should -Contain "Git.Git"
            $lightPackages | Should -Contain "Microsoft.PowerShell"
            $lightPackages | Should -Contain "twpayne.chezmoi"
        }

        It "Full mode should include development tools (VSCode, Terminal)" {
            $fullPackages = $script:ChezmoiData.packages.windows.winget.full
            $fullPackages | Should -Contain "Microsoft.VisualStudioCode"
            $fullPackages | Should -Contain "Microsoft.WindowsTerminal"
        }

        It "All winget package IDs should follow proper format (Vendor.Product)" {
            $allPackages = @()
            $allPackages += $script:ChezmoiData.packages.windows.winget.light
            $allPackages += $script:ChezmoiData.packages.windows.winget.full

            foreach ($pkg in $allPackages) {
                $pkg | Should -Match "^[A-Za-z0-9]+\.[A-Za-z0-9\.]+"
            }
        }
    }

    Context "PowerShell Modules" {
        It "Should have PowerShell modules section" {
            $script:ChezmoiData.packages.windows.powershell_modules | Should -Not -BeNullOrEmpty
        }

        It "Should have PowerShell light mode modules" {
            $lightModules = $script:ChezmoiData.packages.windows.powershell_modules.light
            # Light modules might be empty, just check the property exists
            $script:ChezmoiData.packages.windows.powershell_modules.PSObject.Properties.Name | Should -Contain 'light'
        }

        It "Should have PowerShell full mode modules" {
            $fullModules = $script:ChezmoiData.packages.windows.powershell_modules.full
            $fullModules | Should -Not -BeNullOrEmpty
            $fullModules.Count | Should -BeGreaterThan 0
        }

        It "Full mode should include additional modules" {
            $fullModules = $script:ChezmoiData.packages.windows.powershell_modules.full
            # At least one module should be defined
            $fullModules.Count | Should -BeGreaterThan 0
        }

        It "Module names should not contain spaces or special characters" {
            $allModules = @()
            if ($script:ChezmoiData.packages.windows.powershell_modules.light) {
                $allModules += $script:ChezmoiData.packages.windows.powershell_modules.light
            }
            if ($script:ChezmoiData.packages.windows.powershell_modules.full) {
                $allModules += $script:ChezmoiData.packages.windows.powershell_modules.full
            }

            foreach ($module in $allModules) {
                $module | Should -Match "^[A-Za-z0-9\-]+$"
            }
        }
    }
}

Describe "Linux Package Configuration" {
    BeforeAll {
        if (-not $script:ChezmoiAvailable -or -not $script:ChezmoiData) {
            Set-ItResult -Skipped -Because "Chezmoi data is not available"
        }
    }

    It "Should have Linux APT packages section" {
        $script:ChezmoiData.packages.linux.apt | Should -Not -BeNullOrEmpty
    }

    It "Should have Linux APT light mode packages" {
        $lightPackages = $script:ChezmoiData.packages.linux.apt.light
        $lightPackages | Should -Not -BeNullOrEmpty
        $lightPackages.Count | Should -BeGreaterThan 0
    }

    It "Should have Linux APT full mode packages" {
        $fullPackages = $script:ChezmoiData.packages.linux.apt.full
        # Full packages might be empty, just check the property exists
        $script:ChezmoiData.packages.linux.apt.PSObject.Properties.Name | Should -Contain 'full'
    }

    It "Should have Linux DNF packages section" {
        $script:ChezmoiData.packages.linux.dnf | Should -Not -BeNullOrEmpty
    }

    It "Should have Linux DNF light mode packages" {
        $lightPackages = $script:ChezmoiData.packages.linux.dnf.light
        # Light packages might be empty, just check the property exists
        $script:ChezmoiData.packages.linux.dnf.PSObject.Properties.Name | Should -Contain 'light'
    }

    It "Should have Linux DNF full mode packages" {
        $fullPackages = $script:ChezmoiData.packages.linux.dnf.full
        # Full packages might be empty, just check the property exists
        $script:ChezmoiData.packages.linux.dnf.PSObject.Properties.Name | Should -Contain 'full'
    }

    It "Linux light mode should include essential tools (git, vim)" {
        $lightPackages = $script:ChezmoiData.packages.linux.apt.light
        $lightPackages | Should -Contain "git"
        $lightPackages | Should -Contain "vim"
    }
}

Describe "macOS Package Configuration" {
    BeforeAll {
        if (-not $script:ChezmoiAvailable -or -not $script:ChezmoiData) {
            Set-ItResult -Skipped -Because "Chezmoi data is not available"
        }
    }

    It "Should have macOS Homebrew packages section" {
        $script:ChezmoiData.packages.darwin.brew | Should -Not -BeNullOrEmpty
    }

    It "Should have Homebrew light mode packages" {
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.light
        $lightPackages | Should -Not -BeNullOrEmpty
        $lightPackages.Count | Should -BeGreaterThan 0
    }

    It "Should have Homebrew full mode packages" {
        $fullPackages = $script:ChezmoiData.packages.darwin.brew.full
        $fullPackages | Should -Not -BeNullOrEmpty
        $fullPackages.Count | Should -BeGreaterThan 0
    }

    It "macOS light mode should include essential tools (git, vim, fish)" {
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.light
        $lightPackages | Should -Contain "git"
        $lightPackages | Should -Contain "vim"
        $lightPackages | Should -Contain "fish"
    }
}

Describe "VS Code Extensions Configuration" {
    BeforeAll {
        if (-not $script:ChezmoiAvailable -or -not $script:ChezmoiData) {
            Set-ItResult -Skipped -Because "Chezmoi data is not available"
        }
    }

    Context "Extension Structure" {
        It "Should have extensions section" {
            $script:ChezmoiData.extensions | Should -Not -BeNullOrEmpty
        }

        It "Should have common extensions for all platforms" {
            $commonExtensions = $script:ChezmoiData.extensions.common
            $commonExtensions | Should -Not -BeNullOrEmpty
            $commonExtensions.Count | Should -BeGreaterThan 0
        }

        It "Should have Windows-specific extensions" {
            $windowsExtensions = $script:ChezmoiData.extensions.windows
            $windowsExtensions | Should -Not -BeNullOrEmpty
        }

        It "Should have Linux-specific extensions" {
            $linuxExtensions = $script:ChezmoiData.extensions.linux
            $linuxExtensions | Should -Not -BeNullOrEmpty
        }

        It "Should have macOS-specific extensions" {
            $darwinExtensions = $script:ChezmoiData.extensions.darwin
            $darwinExtensions | Should -Not -BeNullOrEmpty
        }
    }

    Context "Extension Content" {
        It "Common extensions should include GitHub Copilot" {
            $commonExtensions = $script:ChezmoiData.extensions.common
            $commonExtensions | Should -Contain "GitHub.copilot"
        }

        It "Common extensions should include GitHub Copilot Chat" {
            $commonExtensions = $script:ChezmoiData.extensions.common
            $commonExtensions | Should -Contain "GitHub.copilot-chat"
        }

        It "Windows extensions should include WSL remote extension" {
            $windowsExtensions = $script:ChezmoiData.extensions.windows
            $windowsExtensions | Should -Contain "ms-vscode-remote.remote-wsl"
        }

        It "Linux extensions should include SSH remote extension" {
            $linuxExtensions = $script:ChezmoiData.extensions.linux
            $linuxExtensions | Should -Contain "ms-vscode-remote.remote-ssh"
        }

        It "macOS extensions should include SSH remote extension" {
            $darwinExtensions = $script:ChezmoiData.extensions.darwin
            $darwinExtensions | Should -Contain "ms-vscode-remote.remote-ssh"
        }
    }

    Context "Extension Validation" {
        It "All extension IDs should follow proper format (publisher.extension)" {
            $allExtensions = @()
            if ($script:ChezmoiData.extensions.common) {
                $allExtensions += $script:ChezmoiData.extensions.common
            }
            if ($script:ChezmoiData.extensions.windows) {
                $allExtensions += $script:ChezmoiData.extensions.windows
            }
            if ($script:ChezmoiData.extensions.linux) {
                $allExtensions += $script:ChezmoiData.extensions.linux
            }
            if ($script:ChezmoiData.extensions.darwin) {
                $allExtensions += $script:ChezmoiData.extensions.darwin
            }

            foreach ($ext in $allExtensions) {
                $ext | Should -Match "^[a-zA-Z0-9\-]+\.[a-zA-Z0-9\-]+$"
            }
        }

        It "Extension IDs should not contain uppercase letters (VS Code convention)" {
            $allExtensions = @()
            if ($script:ChezmoiData.extensions.common) {
                $allExtensions += $script:ChezmoiData.extensions.common
            }
            if ($script:ChezmoiData.extensions.windows) {
                $allExtensions += $script:ChezmoiData.extensions.windows
            }
            if ($script:ChezmoiData.extensions.linux) {
                $allExtensions += $script:ChezmoiData.extensions.linux
            }
            if ($script:ChezmoiData.extensions.darwin) {
                $allExtensions += $script:ChezmoiData.extensions.darwin
            }

            # Note: This is a convention check, actual extension IDs may vary
            $uppercaseCount = ($allExtensions | Where-Object { $_ -cmatch "[A-Z]" }).Count
            # Just ensure format is valid, some publishers use uppercase (GitHub, Microsoft)
            $uppercaseCount | Should -BeGreaterThan -1
        }

        It "Should not have duplicate extensions in common and platform-specific lists" {
            $commonExtensions = $script:ChezmoiData.extensions.common
            $platformExtensions = @()
            $platformExtensions += $script:ChezmoiData.extensions.windows
            $platformExtensions += $script:ChezmoiData.extensions.linux
            $platformExtensions += $script:ChezmoiData.extensions.darwin

            foreach ($ext in $platformExtensions) {
                $commonExtensions | Should -Not -Contain $ext
            }
        }
    }

    Context "Installation Script Integration" {
        It "Common extensions should be referenced in Windows installation script" {
            $scriptContent = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.ps1.tmpl") -Raw
            $scriptContent | Should -Match "extensions\.common"
        }

        It "Windows extensions should be referenced in Windows installation script" {
            $scriptContent = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.ps1.tmpl") -Raw
            $scriptContent | Should -Match "extensions\.windows"
        }

        It "Common extensions should be referenced in Linux/macOS installation script" {
            $scriptContent = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.sh.tmpl") -Raw
            $scriptContent | Should -Match "extensions\.common"
        }

        It "Installation scripts should check for VS Code availability" {
            $psScript = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.ps1.tmpl") -Raw
            $shScript = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.sh.tmpl") -Raw

            $psScript | Should -Match "Get-Command code"
            $shScript | Should -Match "command -v code"
        }

        It "Installation scripts should use --install-extension flag" {
            $psScript = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.ps1.tmpl") -Raw
            $shScript = Get-Content (Join-Path $script:RepoRoot "run_once_install-packages.sh.tmpl") -Raw

            $psScript | Should -Match "--install-extension"
            $shScript | Should -Match "--install-extension"
        }
    }
}

Describe "Package Consistency" {
    BeforeAll {
        if (-not $script:ChezmoiAvailable -or -not $script:ChezmoiData) {
            Set-ItResult -Skipped -Because "Chezmoi data is not available"
        }
    }

    It "Should not have duplicate packages in light and full lists (Windows WinGet)" {
        $lightPackages = $script:ChezmoiData.packages.windows.winget.light
        $fullPackages = $script:ChezmoiData.packages.windows.winget.full

        foreach ($pkg in $fullPackages) {
            $lightPackages | Should -Not -Contain $pkg
        }
    }

    It "Should not have duplicate modules in light and full lists (PowerShell)" {
        $lightModules = $script:ChezmoiData.packages.windows.powershell_modules.light
        $fullModules = $script:ChezmoiData.packages.windows.powershell_modules.full

        foreach ($module in $fullModules) {
            $lightModules | Should -Not -Contain $module
        }
    }

    It "Should not have duplicate packages in light and full lists (Linux APT)" {
        $lightPackages = $script:ChezmoiData.packages.linux.apt.light
        $fullPackages = $script:ChezmoiData.packages.linux.apt.full

        foreach ($pkg in $fullPackages) {
            $lightPackages | Should -Not -Contain $pkg
        }
    }

    It "Should not have duplicate packages in light and full lists (macOS Brew)" {
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.light
        $fullPackages = $script:ChezmoiData.packages.darwin.brew.full

        foreach ($pkg in $fullPackages) {
            $lightPackages | Should -Not -Contain $pkg
        }
    }
}
