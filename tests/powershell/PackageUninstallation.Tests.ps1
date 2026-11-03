#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    . (Join-Path $script:RepoRoot 'home\.chezmoihelpers\package-uninstall.ps1')

    function winget { }
}

Describe "Uninstall-WinGetPackage" -Tag "Unit" {
    BeforeEach {
        $script:OriginalExitCode = $global:LASTEXITCODE
        $script:Calls = @()
        Mock Write-Host {}
        Mock winget {
            $script:Calls += ,$args
            $global:LASTEXITCODE = if ($args[0] -eq 'uninstall') { 0 } else { -1978335212 }
        }
    }

    AfterEach {
        $global:LASTEXITCODE = $script:OriginalExitCode
    }

    It "Uninstalls all versions of the exact ID without interactive prompts" {
        Uninstall-WinGetPackage -Id 'Vendor.Legacy'

        $script:Calls.Count | Should -Be 2
        $script:Calls[0] -join ' ' | Should -Be 'uninstall --id Vendor.Legacy --exact --all-versions --silent --accept-source-agreements --disable-interactivity'
        $script:Calls[1] -join ' ' | Should -Be 'list --id Vendor.Legacy --exact --accept-source-agreements --disable-interactivity'
    }

    It "Skips only the explicit package-not-installed exit code" {
        Mock winget { $global:LASTEXITCODE = -1978335212 }

        Uninstall-WinGetPackage -Id 'Vendor.Legacy'

        Should -Invoke winget -Times 1 -Exactly
        Should -Invoke Write-Host -Times 1 -ParameterFilter { "$Object" -like '[[]SKIP[]]*' }
    }

    It "Reports uninstall failures including native diagnostics" {
        Mock winget { $global:LASTEXITCODE = 5; 'Access denied' }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*exit code 5*Access denied*'
    }

    It "Rejects a successful uninstaller that leaves the package installed" {
        Mock winget { $global:LASTEXITCODE = 0 }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*still installed*'
    }

    It "Reports verification errors rather than treating them as absence" {
        Mock winget { $global:LASTEXITCODE = if ($args[0] -eq 'uninstall') { 0 } else { 5 } }

        { Uninstall-WinGetPackage -Id 'Vendor.Legacy' } | Should -Throw '*Could not verify*exit code 5*'
    }

    It "Does not run WinGet with WhatIf" {
        Uninstall-WinGetPackage -Id 'Vendor.Legacy' -WhatIf

        Should -Invoke winget -Times 0 -Exactly
    }

    It "Rejects unsafe selectors" {
        foreach ($id in '*', '--all', 'Vendor.*', 'Vendor.Legacy;throw') {
            { Uninstall-WinGetPackage -Id $id } | Should -Throw
        }
        Should -Invoke winget -Times 0 -Exactly
    }
}

Describe "Package uninstall template wiring" -Tag "Integration" {
    BeforeAll {
        $script:Config = Join-Path $TestDrive 'chezmoi.json'
        $script:Overrides = Join-Path $TestDrive 'overrides.json'
        Set-Content -LiteralPath $script:Config -Value '{}' -Encoding ASCII
        $script:UnixScript = Join-Path $script:RepoRoot 'home\.chezmoiscripts\linux\run_onchange_10-install-packages.sh.tmpl'
        $script:WindowsScript = Join-Path $script:RepoRoot 'home\.chezmoiscripts\windows\run_onchange_10-install-packages.ps1.tmpl'
        $script:Data = chezmoi execute-template --source $script:RepoRoot --config $script:Config '{{ .packages | toJson }}' | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) { throw 'Could not load package data' }

        function Render-PackageScript {
            param([string]$Path, [hashtable]$Overrides)
            $Overrides | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $script:Overrides -Encoding ASCII
            $output = chezmoi execute-template --source $script:RepoRoot --config $script:Config --override-data-file $script:Overrides --file $Path 2>&1
            if ($LASTEXITCODE -ne 0) { throw ($output -join "`n") }
            $output -join "`n"
        }

        function New-PackageOverrides {
            param([string]$OS, [string]$Mode)
            @{
                chezmoi = @{ os = $OS; osRelease = @{ id = 'ubuntu' } }
                installType = $Mode
                useYubiKey = $false
                codespaces = $false
                devcontainer = $false
                packages = @{
                    linux = @{
                        apt = @{ uninstall = @('retired-apt') }
                        dnf = @{ uninstall = @('retired-dnf') }
                        brew = @{ uninstall = @('retired-formula') }
                    }
                    darwin = @{ brew = @{
                        formulas = @{ uninstall = @('retired-formula') }
                        cask = @{ uninstall = @('retired-cask') }
                        'app-store' = @{ uninstall = @(@{ name = 'Retired App'; id = 123456 }) }
                    } }
                    windows = @{ winget = @{ uninstall = @('Vendor.Retired') } }
                }
            }

        }

        function Test-ShellSyntax {
            param([string]$Content)
            $path = Join-Path $TestDrive 'packages.sh'
            [IO.File]::WriteAllText($path, $Content.Replace("`r", '') + "`n", [Text.UTF8Encoding]::new($false))
            $output = bash -n $path 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        }

        function Test-PackageDryRun {
            param([string]$Path, [string]$Expected)
            $destination = Join-Path $TestDrive 'preview-home'
            New-Item -ItemType Directory -Path $destination -Force | Out-Null
            $state = Join-Path $TestDrive 'preview.boltdb'
            $preview = (chezmoi apply --dry-run --verbose --no-tty --include scripts --refresh-externals=never --source $script:RepoRoot --config $script:Config --override-data-file $script:Overrides --destination $destination --persistent-state $state --source-path $Path 2>&1) -join "`n"
            $LASTEXITCODE | Should -Be 0 -Because $preview
            $preview | Should -Match ([regex]::Escape($Expected))
        }
    }

    It "Provides an uninstall list for every native package manager" {
        $managers = @(
            $script:Data.linux.apt, $script:Data.linux.dnf, $script:Data.linux.brew,
            $script:Data.darwin.brew.formulas, $script:Data.darwin.brew.cask,
            $script:Data.darwin.brew.'app-store', $script:Data.windows.winget
        )
        foreach ($manager in $managers) {
            $manager.PSObject.Properties.Name | Should -Contain 'uninstall'
            ($manager.uninstall -is [array]) | Should -BeTrue
        }
    }

    It "Renders WinGet removal before installs in <Mode> mode" -TestCases @(
        @{ Mode = 'light' }
        @{ Mode = 'full' }
    ) {
        param($Mode)
        $rendered = Render-PackageScript $script:WindowsScript (New-PackageOverrides windows $Mode)

        $rendered | Should -Match 'Uninstall-WinGetPackage -Id "Vendor.Retired"'
        $rendered.IndexOf('Uninstall-WinGetPackage -Id') | Should -BeLessThan $rendered.IndexOf('winget install')
        $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($rendered, [ref]$null, [ref]$parseErrors)
        $parseErrors | Should -BeNullOrEmpty
        Test-PackageDryRun $script:WindowsScript 'Uninstall-WinGetPackage -Id "Vendor.Retired"'
    }

    It "Renders Linux removals for <Distro> in <Mode> mode" -TestCases @(
        @{ Distro = 'ubuntu'; Manager = 'apt'; Mode = 'light' }
        @{ Distro = 'ubuntu'; Manager = 'apt'; Mode = 'full' }
        @{ Distro = 'fedora'; Manager = 'dnf'; Mode = 'light' }
        @{ Distro = 'fedora'; Manager = 'dnf'; Mode = 'full' }
    ) {
        param($Distro, $Manager, $Mode)
        $overrides = New-PackageOverrides linux $Mode
        $overrides.chezmoi.osRelease.id = $Distro
        $rendered = Render-PackageScript $script:UnixScript $overrides

        $rendered | Should -Match "uninstall_package $Manager `"retired-$Manager`" \|\| exit 1"
        $rendered | Should -Match 'uninstall_package brew-formula "retired-formula" \|\| exit 1'
        $rendered | Should -Not -Match 'uninstall_package (mas|brew-cask)'
        if ($Manager -eq 'apt') {
            $rendered.IndexOf('uninstall_package apt') | Should -BeLessThan $rendered.IndexOf('apt-get install')
            $rendered | Should -Not -Match 'uninstall_package dnf'
        }
        else {
            $rendered | Should -Not -Match 'uninstall_package apt'
        }
        Test-ShellSyntax $rendered
        Test-PackageDryRun $script:UnixScript "uninstall_package $Manager"
    }

    It "Renders all macOS removals before formulas in <Mode> mode" -TestCases @(
        @{ Mode = 'light' }
        @{ Mode = 'full' }
    ) {
        param($Mode)
        $rendered = Render-PackageScript $script:UnixScript (New-PackageOverrides darwin $Mode)

        foreach ($action in 'uninstall_package mas "123456"', 'uninstall_package brew-cask "retired-cask"', 'uninstall_package brew-formula "retired-formula"') {
            $rendered | Should -Match ([regex]::Escape($action))
            $rendered.IndexOf($action) | Should -BeLessThan $rendered.IndexOf('brew_install_quiet "fastfetch"')
        }
        $rendered.IndexOf('uninstall_package mas') | Should -BeLessThan $rendered.IndexOf('uninstall_package brew-formula')
        $rendered | Should -Not -Match 'uninstall_package (apt|dnf)'
        Test-ShellSyntax $rendered
        Test-PackageDryRun $script:UnixScript 'uninstall_package mas "123456"'
    }

    It "Processes an uninstall-only Linux Homebrew configuration" {
        $overrides = New-PackageOverrides linux light
        $overrides.packages.linux.brew.light = @()
        $overrides.packages.linux.brew.full = @()
        $rendered = Render-PackageScript $script:UnixScript $overrides

        $rendered | Should -Match 'uninstall_package brew-formula "retired-formula"'
        $rendered | Should -Match 'Homebrew is required to process its uninstall list'
    }

    It "Rejects install/uninstall conflicts for every native manager" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $managers = switch ($os) {
                windows { @('winget') }
                linux { @('apt', 'dnf', 'brew') }
                darwin { @('formulas', 'cask', 'app-store') }
            }
            foreach ($manager in $managers) {
                $overrides = New-PackageOverrides $os full
                $group = if ($os -eq 'darwin') { $overrides.packages.darwin.brew[$manager] } else { $overrides.packages[$os][$manager] }
                $group.full = $group.uninstall
                $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }

                { Render-PackageScript $path $overrides } | Should -Throw '*listed for both installation and uninstall*'
            }
        }

    }

    It "Rejects invalid uninstall selectors before rendering executable code" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $managers = switch ($os) {
                windows { @('winget') }
                linux { @('apt', 'dnf', 'brew') }
                darwin { @('formulas', 'cask', 'app-store') }
            }
            foreach ($manager in $managers) {
                $overrides = New-PackageOverrides $os full
                $group = if ($os -eq 'darwin') { $overrides.packages.darwin.brew[$manager] } else { $overrides.packages[$os][$manager] }
                if ($manager -eq 'app-store') {
                    $group.uninstall = @(@{ name = 'Invalid'; id = '$(exit 99)' })
                }
                else {
                    $group.uninstall = @('$(exit 99)')
                }
                $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }

                { Render-PackageScript $path $overrides } | Should -Throw '*invalid uninstall entry*'
            }
        }
    }

    It "Does not render native removals when uninstall lists are empty" {
        foreach ($os in 'windows', 'linux', 'darwin') {
            $overrides = New-PackageOverrides $os full
            foreach ($manager in $overrides.packages.linux.Values) { $manager.uninstall = @() }
            foreach ($manager in $overrides.packages.darwin.brew.Values) { $manager.uninstall = @() }
            $overrides.packages.windows.winget.uninstall = @()
            $path = if ($os -eq 'windows') { $script:WindowsScript } else { $script:UnixScript }
            $rendered = Render-PackageScript $path $overrides

            $rendered | Should -Not -Match '(?m)^\s*(Uninstall-WinGetPackage|uninstall_package) '
        }
    }
}
