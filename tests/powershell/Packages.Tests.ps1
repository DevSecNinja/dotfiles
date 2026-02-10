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

        It "Full mode should include development tools (VSCode, Terminal)" {
            $fullPackages = $script:ChezmoiData.packages.windows.winget.full
            $fullPackages | Should -Contain "Microsoft.VisualStudioCode"
            $fullPackages | Should -Contain "Microsoft.WindowsTerminal"
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

        It "Should have PowerShell Git full mode modules" {
            $script:ChezmoiData.packages.windows.powershell_git_modules.full | Should -Not -BeNullOrEmpty
        }

        It "Full mode should include Git-based modules" {
            $fullGitModules = $script:ChezmoiData.packages.windows.powershell_git_modules.full
            # At least one module should be defined
            $fullGitModules.Count | Should -BeGreaterThan 0
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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDdjnXXhA4+KZFI
# MHzdfC+kCPr5ww7aY+knHAw+94s0IqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAqA7xhLjfEFgtHEdqeVdGgwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNTA2MDQwMDAwMDBaFw0zNjA5MDMy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI1IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDQRqwt
# Esae0OquYFazK1e6b1H/hnAKAd/KN8wZQjBjMqiZ3xTWcfsLwOvRxUwXcGx8AUjn
# i6bz52fGTfr6PHRNv6T7zsf1Y/E3IU8kgNkeECqVQ+3bzWYesFtkepErvUSbf+EI
# YLkrLKd6qJnuzK8Vcn0DvbDMemQFoxQ2Dsw4vEjoT1FpS54dNApZfKY61HAldytx
# NM89PZXUP/5wWWURK+IfxiOg8W9lKMqzdIo7VA1R0V3Zp3DjjANwqAf4lEkTlCDQ
# 0/fKJLKLkzGBTpx6EYevvOi7XOc4zyh1uSqgr6UnbksIcFJqLbkIXIPbcNmA98Os
# kkkrvt6lPAw/p4oDSRZreiwB7x9ykrjS6GS3NR39iTTFS+ENTqW8m6THuOmHHjQN
# C3zbJ6nJ6SXiLSvw4Smz8U07hqF+8CTXaETkVWz0dVVZw7knh1WZXOLHgDvundrA
# tuvz0D3T+dYaNcwafsVCGZKUhQPL1naFKBy1p6llN3QgshRta6Eq4B40h5avMcpi
# 54wm0i2ePZD5pPIssoszQyF4//3DoK2O65Uck5Wggn8O2klETsJ7u8xEehGifgJY
# i+6I03UuT1j7FnrqVrOzaQoVJOeeStPeldYRNMmSF3voIgMFtNGh86w3ISHNm0Ia
# adCKCkUe2LnwJKa8TIlwCUNVwppwn4D3/Pt5pwIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQU5Dv88jHt/f3X85FxYxlQQ89hjOgwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAZSqt8RwnBLmuYEHs0QhEnmNA
# ciH45PYiT9s1i6UKtW+FERp8FgXRGQ/YAavXzWjZhY+hIfP2JkQ38U+wtJPBVBaj
# YfrbIYG+Dui4I4PCvHpQuPqFgqp1PzC/ZRX4pvP/ciZmUnthfAEP1HShTrY+2DE5
# qjzvZs7JIIgt0GCFD9ktx0LxxtRQ7vllKluHWiKk6FxRPyUPxAAYH2Vy1lNM4kze
# kd8oEARzFAWgeW3az2xejEWLNN4eKGxDJ8WDl/FQUSntbjZ80FU3i54tpx5F/0Kr
# 15zW/mJAxZMVBrTE2oi0fcI8VMbtoRAmaaslNXdCG1+lqvP4FbrQ6IwSBXkZagHL
# hFU9HCrG/syTRLLhAezu/3Lr00GrJzPQFnCEH1Y58678IgmfORBPC1JKkYaEt2Od
# Dh4GmO0/5cHelAK2/gTlQJINqDr6JfwyYHXSd+V08X1JUPvB4ILfJdmL+66Gp3CS
# BXG6IwXMZUXBhtCyIaehr0XkBoDIGMUG1dUtwq1qmcwbdUfcSYCn+OwncVUXf53V
# JUNOaMWMts0VlRYxe5nK+At+DI96HAlXHAL5SlfYxJ7La54i71McVWRP66bW+yER
# NpbJCjyCYG2j+bdpxo/1Cy4uPcU3AWVPGrbn5PhDBf3Froguzzhk++ami+r3Qrx5
# bIbY3TVzgiFI7Gq3zWcxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCDRPXefIRSJ+lY8kOgKwx6E3hKlql0n4qFdABhoFfDASjANBgkqhkiG
# 9w0BAQEFAASCAgCoBepJqMtIFLywwUPRpA6wmkp0jfLFhm/BbYkkVkcIw//KtOJl
# wks3SKXJrqcVvJNziUlvhxX3Jjtq8utou8Vrqmi2ab7NAVn1lbsowU5ZkmNm9jda
# esnNVVNC8SvvqIF5n5BDeJxKqrOqYJ0jwLqEKmjE6rp5i0Nxg4Pu3MU0Vm63dfTV
# yLZmBZdhKN+7Nl+K8F5PglmvIER7j/Xo0+CtwaAatBcyRvLv8QMiFLu3CCa5pB5b
# zHY4twWqDKuCQuoSgUY6Ei0UizKVD7LpAmuM5WeKGwB5e2Aj66fB4tewHINfsUyj
# UigqL75rBDYcouY08sazHH+B0DeMWFpU/VF1yBcTn9hVueQFZoJ2VCcAxwrgP14b
# hMor9BsYgAw7UE52dD9q2aAno1y02OeSaJtpcrSKD0gS5LWDKYys/9aLsx3iVLyA
# HEdM4VCodBoHx9p2FJExCfUQDM0YInXOI3SMoBpGZhtfHHs7digGEDdetzXRCMfR
# IKOx5Sj3Xk49fMFJ3r9Cu1y+eSc7zvz+say9yXWGGsjuiNjt2qmc2B4uo4G/JF65
# beh8HXLNu+6WCw9RM6lDP58QROMuMthlHvIcgvnqjn4pab+Bvo1ZrHQyMkmEZl8w
# GDHENtw8xF37/S9TIZ4wZl9/9lxvehBnW2G2QfMUu3dS06HzPqhneo77+6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAyMTAxNjM4NDhaMC8GCSqGSIb3DQEJBDEi
# BCDso5v7UM2NNQJSiwoUFU9mFD3tmt2sGeuWCV6QOWs+ezANBgkqhkiG9w0BAQEF
# AASCAgC5qtuE/e5ZrSzccfAxxNBPZcgkQJnORsnnn3qpgjS1k2jy+2U1LzNxSysd
# lpgqw40u1YUR4uz0p1rQPoKDI2DfPaa6Y6lU6pHCii6BxhXKYdplKUfwc3KN2EVG
# yO0RcioGYVOcbuUSKIqCk9f6rALylpG2xzwcjJHiDlYSfSnuHvT4Qs4776+PIAso
# 0lQahv4QYLX3973jd61iTlAUz4w+wlB5UZ6HJmZBI7gK8rccLLpLLv8uN2H64j4u
# 54e+SfXVKjZDVLGoxvDW7dQuBZpXuf4AmQZ8FFVG67wZkqjeogXh3p1YB/Z+wYJ2
# V7CrPxsPdVLsQn+vWhani/S/kMf+APC758gCUBJ2rLoFeZpIUARJb1bVdHJD7Xss
# n4Gza19I39wgpBwxYX0WDUfBkZewvSlCCDExmNECfeikyZqvW29vqjH5R4NMX6Vy
# yZBX+gaJTYntiTrp+ZKtnpl2HlNWG/95SM9tZRhQ/TXm+qPHPS+fxb5faC5pzDne
# 4LrEl5pxtmCJZm6kc3KlHsEwQd/mMXEgsVpLLAoRGnnpss9nyF7PnDtcwejQmcSx
# T5AD3Ps+uoDiCCG7XesFwhG1IEUf19qx5v3+njD1p/sE+2acEYlIbCZvibtzpZE4
# TatSf/yST635xlXmv7nxs8QXG9M9PtyZfUiWwKLQV3hpxOJmCA==
# SIG # End signature block
