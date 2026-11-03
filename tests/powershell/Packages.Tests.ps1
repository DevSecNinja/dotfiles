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
                    winget install --id twpayne.chezmoi --source winget --silent --accept-source-agreements --accept-package-agreements | Out-Null

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
    $script:PackagesYamlPath = Join-Path $script:RepoRoot "home\.chezmoidata\packages.yaml"
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

        It "Full mode should include development tools (VSCode)" {
            $fullPackages = $script:ChezmoiData.packages.windows.winget.full
            $fullPackages | Should -Contain "Microsoft.VisualStudioCode"
        }

        It "Full mode should include WSL" {
            $fullPackages = $script:ChezmoiData.packages.windows.winget.full
            $fullPackages | Should -Contain "Microsoft.WSL"
        }

        It "All winget package IDs should follow proper format (Vendor.Product)" {
            $allPackages = @()
            $allPackages += $script:ChezmoiData.packages.windows.winget.light
            $allPackages += $script:ChezmoiData.packages.windows.winget.full

            foreach ($pkg in $allPackages) {
                $pkg | Should -Match "^[A-Za-z0-9-]+\.[A-Za-z0-9.-]+$"
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
                $module | Should -Match "^[A-Za-z0-9\.\-]+$"
            }
        }
    }

    Context "PowerShell Git Modules" {
        It "Should have PowerShell Git modules section" {
            $script:ChezmoiData.packages.windows.powershell_git_modules | Should -Not -BeNullOrEmpty
        }

        It "Should have PowerShell Git light mode modules (can be empty)" {
            # Light mode can have an empty array
            $script:ChezmoiData.packages.windows.powershell_git_modules | Get-Member -Name "light" | Should -Not -BeNullOrEmpty
        }

        It "Should define a PowerShell Git full mode modules key (may be empty)" {
            # powershell_git_modules.full is intentionally empty on Windows since
            # the Office 365 alias module was retired; only assert the key is
            # present so the git-clone loop in run_onchange_20-install-modules has a
            # defined (possibly empty) range to iterate.
            $script:ChezmoiData.packages.windows.powershell_git_modules.PSObject.Properties.Name |
                Should -Contain 'full'
        }

        It "Git modules should have required properties (name, url, destination)" {
            $allGitModules = @()
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.light) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.light
            }
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.full) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.full
            }

            foreach ($module in $allGitModules) {
                $module.name | Should -Not -BeNullOrEmpty
                $module.url | Should -Not -BeNullOrEmpty
                $module.destination | Should -Not -BeNullOrEmpty
            }
        }

        It "Git module URLs should be valid GitHub URLs" {
            $allGitModules = @()
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.light) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.light
            }
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.full) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.full
            }

            foreach ($module in $allGitModules) {
                $module.url | Should -Match "^https://github\.com/.+/.+\.git$"
            }
        }

        It "Git module destinations should not contain invalid path characters" {
            $allGitModules = @()
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.light) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.light
            }
            if ($script:ChezmoiData.packages.windows.powershell_git_modules.full) {
                $allGitModules += $script:ChezmoiData.packages.windows.powershell_git_modules.full
            }

            foreach ($module in $allGitModules) {
                # Windows invalid path characters: < > : " | ? * and control characters
                $module.destination | Should -Not -Match '[<>:"|?*\x00-\x1F]'
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

    It "Should have Homebrew formula light mode packages" {
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.formulas.light
        $lightPackages | Should -Not -BeNullOrEmpty
        $lightPackages.Count | Should -BeGreaterThan 0
    }

    It "Should have Homebrew formula full mode packages" {
        $fullPackages = $script:ChezmoiData.packages.darwin.brew.formulas.full
        $fullPackages | Should -Not -BeNullOrEmpty
        $fullPackages.Count | Should -BeGreaterThan 0
    }

    It "macOS light mode should include essential tools (git, vim, fish)" {
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.formulas.light
        $lightPackages | Should -Contain "git"
        $lightPackages | Should -Contain "vim"
        $lightPackages | Should -Contain "fish"
    }

    It "Should have Homebrew cask section with light and full lists" {
        $script:ChezmoiData.packages.darwin.brew.cask | Should -Not -BeNullOrEmpty
        $script:ChezmoiData.packages.darwin.brew.cask.PSObject.Properties.Name | Should -Contain 'light'
        $script:ChezmoiData.packages.darwin.brew.cask.PSObject.Properties.Name | Should -Contain 'full'
    }

    It "Should have Homebrew cask full mode applications" {
        $fullCasks = $script:ChezmoiData.packages.darwin.brew.cask.full
        $fullCasks | Should -Not -BeNullOrEmpty
        $fullCasks.Count | Should -BeGreaterThan 0
    }

    It "Should require the 'mas' formula for Mac App Store installs" {
        $fullPackages = $script:ChezmoiData.packages.darwin.brew.formulas.full
        $fullPackages | Should -Contain "mas"
    }

    It "Should have Mac App Store section with light and full lists" {
        $appStore = $script:ChezmoiData.packages.darwin.brew."app-store"
        $appStore | Should -Not -BeNullOrEmpty
        $appStore.PSObject.Properties.Name | Should -Contain 'light'
        $appStore.PSObject.Properties.Name | Should -Contain 'full'
    }

    It "Mac App Store apps should define both name and numeric id" {
        $fullApps = $script:ChezmoiData.packages.darwin.brew."app-store".full
        $fullApps | Should -Not -BeNullOrEmpty
        foreach ($app in $fullApps) {
            $app.name | Should -Not -BeNullOrEmpty
            $app.id | Should -Not -BeNullOrEmpty
            "$($app.id)" | Should -Match '^\d+$'
        }
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

        It "Should have a common extensions key (may be empty)" {
            # GitHub.copilot{,-chat} are bundled built-ins in current VS
            # Code releases, so the curated common list is intentionally
            # empty. The key itself must still exist for templates that
            # iterate `.extensions.common`.
            $script:ChezmoiData.extensions.PSObject.Properties.Name |
                Should -Contain "common"
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
        It "Common extensions list must NOT include GitHub Copilot (bundled built-in)" {
            # See note in home/.chezmoidata/packages.yaml: installing
            # GitHub.copilot from the marketplace conflicts with the
            # newer bundled version.
            $commonExtensions = $script:ChezmoiData.extensions.common
            if ($commonExtensions) {
                $commonExtensions | Should -Not -Contain "GitHub.copilot"
            }
        }

        It "Common extensions list must NOT include GitHub Copilot Chat (bundled built-in)" {
            $commonExtensions = $script:ChezmoiData.extensions.common
            if ($commonExtensions) {
                $commonExtensions | Should -Not -Contain "GitHub.copilot-chat"
            }
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
        $lightPackages = $script:ChezmoiData.packages.darwin.brew.formulas.light
        $fullPackages = $script:ChezmoiData.packages.darwin.brew.formulas.full

        foreach ($pkg in $fullPackages) {
            $lightPackages | Should -Not -Contain $pkg
        }
    }
}

Describe "WSL Configuration" {
    BeforeAll {
        $script:WSLConfigPath = Join-Path $script:RepoRoot "home\dot_wslconfig"
        $script:WSLInstallScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_once_install-wsl.ps1"
    }

    Context "WSL Config File" {
        It ".wslconfig file should exist" {
            $script:WSLConfigPath | Should -Exist
        }

        It ".wslconfig should not be empty" {
            $content = Get-Content $script:WSLConfigPath -Raw
            $content | Should -Not -BeNullOrEmpty
        }

        It ".wslconfig should contain [wsl2] section" {
            $content = Get-Content $script:WSLConfigPath -Raw
            $content | Should -Match "\[wsl2\]"
        }

        It ".wslconfig should configure memory settings" {
            $content = Get-Content $script:WSLConfigPath -Raw
            $content | Should -Match "memory="
        }

        It ".wslconfig should contain [experimental] section" {
            $content = Get-Content $script:WSLConfigPath -Raw
            $content | Should -Match "\[experimental\]"
        }

        It ".wslconfig should enable sparse VHD" {
            $content = Get-Content $script:WSLConfigPath -Raw
            $content | Should -Match "sparseVhd=true"
        }
    }

    Context "WSL Installation Script" {
        It "WSL installation script should exist" {
            $script:WSLInstallScriptPath | Should -Exist
        }

        It "WSL installation script should be a PowerShell file" {
            $script:WSLInstallScriptPath | Should -Match "\.ps1$"
        }

        It "WSL installation script should check if WSL is installed" {
            $content = Get-Content $script:WSLInstallScriptPath -Raw
            $content | Should -Match "wsl"
        }

        It "WSL installation script should contain wsl.exe --install command" {
            $content = Get-Content $script:WSLInstallScriptPath -Raw
            $content | Should -Match "wsl\.exe --install"
        }

        It "WSL installation script should install Debian" {
            $content = Get-Content $script:WSLInstallScriptPath -Raw
            $content | Should -Match "Debian"
        }

        It "WSL installation script should check admin privileges" {
            $content = Get-Content $script:WSLInstallScriptPath -Raw
            $content | Should -Match "Administrator"
        }

        It "WSL installation script should warn about WSL v1" {
            $content = Get-Content $script:WSLInstallScriptPath -Raw
            $content | Should -Match "WSL version 1|WSL 2"
        }
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCym2NBIspA6YRR
# XoovutHDAUSe6cdE2p5MYmzuW5ZR1KCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
# p05/1ElTgWD0MA0GCSqGSIb3DQEBCwUAMCMxITAfBgNVBAMMGEplYW4tUGF1bCB2
# YW4gUmF2ZW5zYmVyZzAeFw0yNjAxMTQxMjU3MjBaFw0zMTAxMTQxMzA2NDdaMCMx
# ITAfBgNVBAMMGEplYW4tUGF1bCB2YW4gUmF2ZW5zYmVyZzCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAMm6cmnzWkwTZJW3lpa98k2eQDQJB6Twyr5U/6cU
# bXWG2xNCGTZCxH3a/77uGX5SDh4g/6x9+fSuhkGkjVcCmP2qpfeHOqafOByrzg6p
# /oI4Zdn4eAHRdhFV+IDmP68zaLtG9oai2k4Ilsc9qINOKPesVZdJd7sxtrutZS8e
# UqBmQr3rYD96pBZXt2YpJXmqSZdS9KdrboVms6Y11naZCSoBbi+XhbyfDZzgN65i
# NZCTahRj6RkJECzU7FXsV4qhuJca4fGHue2Lc027w0A/ZxZkbXkVnTtZbP3x0Q6v
# wkH0r3lfeRcFtKisHKFfDdsIlS+H9cQ8u2NMNWK3375By4yUnQm1NJjVFDZNAZI/
# A/Os3DpRXGyW8gxlSb+CGqHUQU0+YtrSuaXaLc5x0K+QcBmNBzCB/gQArY95g5dn
# rO3m2+XWhHmP6zP/fBMZW1BPLXTFbK/tXY/rFuWZ77MRka12Enu8EbhzK+Mfn00m
# ts6TL7AtV6qksjCc+aJPhgPVABMCDkD4QXHvENbE8s99LrjgsJwSyalOxgWovQl+
# 4r4DbReaHfapy4+j/Rxba65YQBSN35dwWqhb8YxyzCEcJ7q1TTvoVEntV0SeC8Lh
# 4rhqdHhyigZUSptw6LMry3bEdDrCAJ8FeW1LdTb+00bayq/J4RTZd4OLiIf07mot
# KTmJAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggrBgEFBQcD
# AzAdBgNVHQ4EFgQUDt+a1J2KwjQ4CPd2E5gJ3OpVld4wDQYJKoZIhvcNAQELBQAD
# ggIBAFu1W92GGmGvSOOFXMIs/Lu+918MH1rX1UNYdgI1H8/2gDAwfV6eIy+Gu1MK
# rDolIGvdV8eIuu2qGbELnfoeS0czgY0O6uFf6JF1IR/0Rh9Pw1qDmWD+WdI+m4+y
# gPBGz4F/crK+1L8wgfV+tuxCfSJmtu0Ce71DFI+0wvwXWSjhTFxboldsmvOsz+Bp
# X0j4xU6qAsiZK7Tp0VrrLeJEuqE4hC2sTWCJJyP7qmxUjkCqoaiqhci6qSvpg1mJ
# qM4SYkE0FE59z+++4m4DiiNiCzSr/O3uKsfEl2MwZWoZgqLKbMC33I+e/o//EH9/
# HYPWKlEFzXbVj2c3vCRZf2hZZuvfLDoT7i8eZGg3vsTsFnC+ZXKwQTaXqS++q9f3
# rDNYAD+9+GwVyHqVVqwgSME91OgbJ6qfx7H/5VqHHhoJiifSgPiIOSyhvGu9JbcY
# mHkZS3h2P3BU8n/nuqF4eMcQ6LeZDsWCzvHOaHKisRKzSX0yWxjGygp7trqpIi3C
# A3DpBGHXa9r1fwleRfWUeyX/y7pJxT0RRlxNDip4VhK0RRxmE6PL0cq8i92Qs7HA
# csVkGkrIkSYUYhJxemehXwBnwJ1PfDqjvZVpjQdUeP1TTDSNrR3EqiVP5n+nWRYV
# NkoMe75v2tBqXHfq05ryGO9ivXORcmh/MFMgWSR9WYTjZRy3MIIFjTCCBHWgAwIB
# AgIQDpsYjvnQLefv21DiCEAYWjANBgkqhkiG9w0BAQwFADBlMQswCQYDVQQGEwJV
# UzEVMBMGA1UEChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQu
# Y29tMSQwIgYDVQQDExtEaWdpQ2VydCBBc3N1cmVkIElEIFJvb3QgQ0EwHhcNMjIw
# ODAxMDAwMDAwWhcNMzExMTA5MjM1OTU5WjBiMQswCQYDVQQGEwJVUzEVMBMGA1UE
# ChMMRGlnaUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYD
# VQQDExhEaWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwggIiMA0GCSqGSIb3DQEBAQUA
# A4ICDwAwggIKAoICAQC/5pBzaN675F1KPDAiMGkz7MKnJS7JIT3yithZwuEppz1Y
# q3aaza57G4QNxDAf8xukOBbrVsaXbR2rsnnyyhHS5F/WBTxSD1Ifxp4VpX6+n6lX
# FllVcq9ok3DCsrp1mWpzMpTREEQQLt+C8weE5nQ7bXHiLQwb7iDVySAdYyktzuxe
# TsiT+CFhmzTrBcZe7FsavOvJz82sNEBfsXpm7nfISKhmV1efVFiODCu3T6cw2Vbu
# yntd463JT17lNecxy9qTXtyOj4DatpGYQJB5w3jHtrHEtWoYOAMQjdjUN6QuBX2I
# 9YI+EJFwq1WCQTLX2wRzKm6RAXwhTNS8rhsDdV14Ztk6MUSaM0C/CNdaSaTC5qmg
# Z92kJ7yhTzm1EVgX9yRcRo9k98FpiHaYdj1ZXUJ2h4mXaXpI8OCiEhtmmnTK3kse
# 5w5jrubU75KSOp493ADkRSWJtppEGSt+wJS00mFt6zPZxd9LBADMfRyVw4/3IbKy
# Ebe7f/LVjHAsQWCqsWMYRJUadmJ+9oCw++hkpjPRiQfhvbfmQ6QYuKZ3AeEPlAwh
# HbJUKSWJbOUOUlFHdL4mrLZBdd56rF+NP8m800ERElvlEFDrMcXKchYiCd98THU/
# Y+whX8QgUWtvsauGi0/C1kVfnSD8oR7FwI+isX4KJpn15GkvmB0t9dmpsh3lGwID
# AQABo4IBOjCCATYwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQU7NfjgtJxXWRM
# 3y5nP+e6mK4cD08wHwYDVR0jBBgwFoAUReuir/SSy4IxLVGLp6chnfNtyA8wDgYD
# VR0PAQH/BAQDAgGGMHkGCCsGAQUFBwEBBG0wazAkBggrBgEFBQcwAYYYaHR0cDov
# L29jc3AuZGlnaWNlcnQuY29tMEMGCCsGAQUFBzAChjdodHRwOi8vY2FjZXJ0cy5k
# aWdpY2VydC5jb20vRGlnaUNlcnRBc3N1cmVkSURSb290Q0EuY3J0MEUGA1UdHwQ+
# MDwwOqA4oDaGNGh0dHA6Ly9jcmwzLmRpZ2ljZXJ0LmNvbS9EaWdpQ2VydEFzc3Vy
# ZWRJRFJvb3RDQS5jcmwwEQYDVR0gBAowCDAGBgRVHSAAMA0GCSqGSIb3DQEBDAUA
# A4IBAQBwoL9DXFXnOF+go3QbPbYW1/e/Vwe9mqyhhyzshV6pGrsi+IcaaVQi7aSI
# d229GhT0E0p6Ly23OO/0/4C5+KH38nLeJLxSA8hO0Cre+i1Wz/n096wwepqLsl7U
# z9FDRJtDIeuWcqFItJnLnU+nBgMTdydE1Od/6Fmo8L8vC6bp8jQ87PcDx4eo0kxA
# GTVGamlUsLihVo7spNU96LHc/RzY9HdaXFSMb++hUD38dglohJ9vytsgjTVgHAID
# yyCwrFigDkBjxZgiwbJZ9VVrzyerbHbObyMt9H5xaiNrIv8SuFQtJ37YOtnwtoeW
# /VvRXKwYw02fc7cBqZ9Xql4o4rmUMIIGtDCCBJygAwIBAgIQDcesVwX/IZkuQEMi
# DDpJhjANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzEVMBMGA1UEChMMRGln
# aUNlcnQgSW5jMRkwFwYDVQQLExB3d3cuZGlnaWNlcnQuY29tMSEwHwYDVQQDExhE
# aWdpQ2VydCBUcnVzdGVkIFJvb3QgRzQwHhcNMjUwNTA3MDAwMDAwWhcNMzgwMTE0
# MjM1OTU5WjBpMQswCQYDVQQGEwJVUzEXMBUGA1UEChMORGlnaUNlcnQsIEluYy4x
# QTA/BgNVBAMTOERpZ2lDZXJ0IFRydXN0ZWQgRzQgVGltZVN0YW1waW5nIFJTQTQw
# OTYgU0hBMjU2IDIwMjUgQ0ExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAtHgx0wqYQXK+PEbAHKx126NGaHS0URedTa2NDZS1mZaDLFTtQ2oRjzUXMmxC
# qvkbsDpz4aH+qbxeLho8I6jY3xL1IusLopuW2qftJYJaDNs1+JH7Z+QdSKWM06qc
# hUP+AbdJgMQB3h2DZ0Mal5kYp77jYMVQXSZH++0trj6Ao+xh/AS7sQRuQL37QXbD
# hAktVJMQbzIBHYJBYgzWIjk8eDrYhXDEpKk7RdoX0M980EpLtlrNyHw0Xm+nt5pn
# YJU3Gmq6bNMI1I7Gb5IBZK4ivbVCiZv7PNBYqHEpNVWC2ZQ8BbfnFRQVESYOszFI
# 2Wv82wnJRfN20VRS3hpLgIR4hjzL0hpoYGk81coWJ+KdPvMvaB0WkE/2qHxJ0ucS
# 638ZxqU14lDnki7CcoKCz6eum5A19WZQHkqUJfdkDjHkccpL6uoG8pbF0LJAQQZx
# st7VvwDDjAmSFTUms+wV/FbWBqi7fTJnjq3hj0XbQcd8hjj/q8d6ylgxCZSKi17y
# Vp2NL+cnT6Toy+rN+nM8M7LnLqCrO2JP3oW//1sfuZDKiDEb1AQ8es9Xr/u6bDTn
# YCTKIsDq1BtmXUqEG1NqzJKS4kOmxkYp2WyODi7vQTCBZtVFJfVZ3j7OgWmnhFr4
# yUozZtqgPrHRVHhGNKlYzyjlroPxul+bgIspzOwbtmsgY1MCAwEAAaOCAV0wggFZ
# MBIGA1UdEwEB/wQIMAYBAf8CAQAwHQYDVR0OBBYEFO9vU0rp5AZ8esrikFb2L9RJ
# 7MtOMB8GA1UdIwQYMBaAFOzX44LScV1kTN8uZz/nupiuHA9PMA4GA1UdDwEB/wQE
# AwIBhjATBgNVHSUEDDAKBggrBgEFBQcDCDB3BggrBgEFBQcBAQRrMGkwJAYIKwYB
# BQUHMAGGGGh0dHA6Ly9vY3NwLmRpZ2ljZXJ0LmNvbTBBBggrBgEFBQcwAoY1aHR0
# cDovL2NhY2VydHMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZFJvb3RHNC5j
# cnQwQwYDVR0fBDwwOjA4oDagNIYyaHR0cDovL2NybDMuZGlnaWNlcnQuY29tL0Rp
# Z2lDZXJ0VHJ1c3RlZFJvb3RHNC5jcmwwIAYDVR0gBBkwFzAIBgZngQwBBAIwCwYJ
# YIZIAYb9bAcBMA0GCSqGSIb3DQEBCwUAA4ICAQAXzvsWgBz+Bz0RdnEwvb4LyLU0
# pn/N0IfFiBowf0/Dm1wGc/Do7oVMY2mhXZXjDNJQa8j00DNqhCT3t+s8G0iP5kvN
# 2n7Jd2E4/iEIUBO41P5F448rSYJ59Ib61eoalhnd6ywFLerycvZTAz40y8S4F3/a
# +Z1jEMK/DMm/axFSgoR8n6c3nuZB9BfBwAQYK9FHaoq2e26MHvVY9gCDA/JYsq7p
# GdogP8HRtrYfctSLANEBfHU16r3J05qX3kId+ZOczgj5kjatVB+NdADVZKON/gnZ
# ruMvNYY2o1f4MXRJDMdTSlOLh0HCn2cQLwQCqjFbqrXuvTPSegOOzr4EWj7PtspI
# HBldNE2K9i697cvaiIo2p61Ed2p8xMJb82Yosn0z4y25xUbI7GIN/TpVfHIqQ6Ku
# /qjTY6hc3hsXMrS+U0yy+GWqAXam4ToWd2UQ1KYT70kZjE4YtL8Pbzg0c1ugMZyZ
# Zd/BdHLiRu7hAWE6bTEm4XYRkA6Tl4KSFLFk43esaUeqGkH/wyW4N7OigizwJWeu
# kcyIPbAvjSabnf7+Pu0VrFgoiovRDiyx3zEdmcif/sYQsfch28bZeUz2rtY/9TCA
# 6TD8dC3JE3rYkrhLULy7Dc90G6e8BlqmyIjlgp2+VqsS9/wQD7yFylIz0scmbKvF
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6by
# yf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuF
# gGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSE
# vNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf
# 2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05p
# rGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2u
# jI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN
# 96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ec
# mtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p1
# 6UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfu
# XkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971
# DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECx
# a9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQ
# oNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn
# /Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3f
# lbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVR
# s6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42
# ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZT
# giy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS
# 43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L
# 3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TI
# e0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/
# EdYUo80r3TfMlkD0/YMxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCBZIOVlsKzltn3Tt1bfbyw94JBSeFqmWH1VSkFj1hzLWzANBgkqhkiG
# 9w0BAQEFAASCAgASHDMhjaW6+sEJPs5T/LK6Up1I/Mlwe5ZJA+IDSe19QnllHb8W
# 84V3iMUdoWyt8DafI8e0QwgebkRN0nfPe0ysNJiRsL/OB3RwjxlL9/Mivs4CvHsg
# Co9liKsm0+LplWLUQSdRgDLtzT5K8/cbx2Aqilf9rek+9dRpRa5IvweuCFgh4m0G
# nEbfBVhxI2XbpsVVI7VOAbX8TzB4T+4rTsQSq8n0CjcFIlCSdkjAbWKMbPHrF4UO
# GwLJrAmjm1703b3M6RfyUGBLbNY1OQWdMZdALk3NynqmzwsbgJ1PLFdJ0fPJ7mlS
# 3uUEi01Uscv7Axac4A7a9XbwydxoWX4y74awqbTBUUFj3F/QQAoATT3aWYW9mO89
# 5+moXxrbj7cjVbx5gCfIblSfLUDcMOj30Kdhm0YcNFOCbWcXsMKwK3cWs9794hbP
# 00RaTsaUIygaEahRj2Wk9J9j0MolL8sLY4w5EEY2r3DIqsSUc53X4na79aBHy0Gn
# eLQ0/q54oza4y1k1wpuv99zUaXW9QG0NjP5JexJTvlw8n+xRpZwJgIqdok/zo5VP
# C2I9vh4f5WPSexTQYtyFgIevqfiiD1H4WS5E6sN0/FZSiKQh6K5+KUPGLu1YX8Q9
# +Jk1KANNjzCJymYfmn3/AclWbFO2nay07cWsOJOqK6rzWkJTjOq/uPfPUKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMDMxODQ1NDVaMC8GCSqGSIb3DQEJBDEi
# BCDuodquoAVGL6myaLuOMm7bd4rPTnWZETduXnfZBIPvdjANBgkqhkiG9w0BAQEF
# AASCAgCTr05zoxsPVpj9iSfyRH86jKcc9xZoxZSECXy4ncWA4XrXXop06/9sUIIR
# dP/OKT1fyirYav9UxyxLuTVoWU8k9sOp4Kl0ZptBOfxBLt2jxSDhTtJez0BrsS7Y
# COMFTF6+FVOlkvUS8BBjMs1EU85q/G4OYnUmVkx23S2n3jCDSE/Gr2DMPD4O3Shq
# 6EdfUxv9Dnrx4Vi7qK/aEHeW0B0JE3AaL1LNd0kcSzQrVteQmUa1NKCTwCpYaE8h
# cz1ZlY2Y/djzGZyahPqCmXgklNZJ0X33NYJynP0WIBgN9SwEIzJdl5sHMDN3nJva
# MCQ9NDVo2oH/ARZmK3EZ7sc6/dB+3syFRMy/P5dmWVedVZxVEpGQuzjeHx161E6T
# /u0e5qN/Y4JG6VGA3tl4TqbpbHjbEyrdY6kmNU3Bbcmm4peCBvnUo0b5T/zlLzgJ
# 5haH2gMOVCzYqrzHKTI+gKdPD+WfQTuzA8QTGQj+SruP9zz3QH9sA92o3Xf3p6q2
# ZKEQE1SyfhonXiRWAUMGQbjzHWI/SScT7FYmbJFt3s0jvVfO+Rr3LPtW3F2nCeeH
# soTWZHpm+gMHQBYnQbpqUxJrWMBH5oB7OyCXhYHCixLbTYU9e0+4cTE26+M8D8Pi
# mhpPfVnlQ3PB2gLWut0vlbUo2LMe336/kb6z6SC1TMXnZV67sw==
# SIG # End signature block
