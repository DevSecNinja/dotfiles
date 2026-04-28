#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for module installation utilities (Install-PowerShellModule,
    Install-GitPowerShellModule, Add-ToPSModulePath).

.DESCRIPTION
    Validates input handling, security validation (path traversal, URL allow-list)
    and idempotency of the module installation helpers in the DotfilesHelpers module.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    if (Test-Path $modulePath) {
        Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force -DisableNameChecking
    }
    else {
        throw "DotfilesHelpers module not found at: $modulePath"
    }
}

AfterAll {
    Pop-Location
}

Describe "Install-PowerShellModule Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Install-PowerShellModule -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should require ModuleName parameter" {
        $cmd = Get-Command Install-PowerShellModule
        $cmd.Parameters["ModuleName"].Attributes |
            Where-Object { $_ -is [Parameter] } |
            Select-Object -ExpandProperty Mandatory |
            Should -Contain $true
    }

    It "Should accept ModuleName as a string parameter" {
        $cmd = Get-Command Install-PowerShellModule
        $cmd.Parameters["ModuleName"].ParameterType.FullName | Should -Be "System.String"
    }
}

Describe "Install-GitPowerShellModule Function" -Tag "Unit" {
    It "Should be available as a function" {
        Get-Command Install-GitPowerShellModule -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should have mandatory Name, Url and Destination parameters" {
        $cmd = Get-Command Install-GitPowerShellModule
        foreach ($p in 'Name', 'Url', 'Destination') {
            $cmd.Parameters.ContainsKey($p) | Should -Be $true
        }
    }

    Context "Destination validation (path traversal protection)" {
        It "Should reject destination with parent directory traversal '..'" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar.git" -Destination "../evil" -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject destination with forward slash" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar.git" -Destination "evil/path" -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject destination with backslash" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar.git" -Destination "evil\path" -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject absolute Windows path destination" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar.git" -Destination "C:\evil" -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject UNC path destination" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar.git" -Destination "\\server\share" -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }
    }

    Context "URL validation (only GitHub HTTPS allowed)" {
        BeforeAll {
            # Ensure the destination directory does not exist for these tests so
            # we exercise the URL validation path. Use a unique destination name.
            $script:TestDest = "TestModule_$(Get-Random)"
            # On Linux, USERPROFILE may not be set. Set it to a temporary directory
            # so the function (which uses $env:USERPROFILE) can run cross-platform
            # for testing purposes.
            $script:OriginalUserProfile = $env:USERPROFILE
            if (-not $env:USERPROFILE) {
                $env:USERPROFILE = if ($env:HOME) { $env:HOME } else { '/tmp' }
            }
            $script:ModulesDir = Join-Path $env:USERPROFILE "Documents/PowerShell/Modules"
        }

        AfterAll {
            $target = Join-Path $script:ModulesDir $script:TestDest
            if (Test-Path $target) {
                Remove-Item -Recurse -Force $target -ErrorAction SilentlyContinue
            }
            # Restore USERPROFILE
            if ($null -eq $script:OriginalUserProfile) {
                Remove-Item Env:USERPROFILE -ErrorAction SilentlyContinue
            }
            else {
                $env:USERPROFILE = $script:OriginalUserProfile
            }
        }

        It "Should reject non-HTTPS git URL" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "git@github.com:foo/bar.git" -Destination $script:TestDest -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject HTTP URL" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "http://github.com/foo/bar.git" -Destination $script:TestDest -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject non-GitHub HTTPS URL" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://gitlab.com/foo/bar.git" -Destination $script:TestDest -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }

        It "Should reject URL not ending in .git" {
            $err = $null
            $result = Install-GitPowerShellModule -Name "Test" -Url "https://github.com/foo/bar" -Destination $script:TestDest -ErrorAction SilentlyContinue -ErrorVariable err 2>$null
            $result | Should -BeNullOrEmpty
            $err | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "Add-ToPSModulePath Function" -Tag "Unit" {
    BeforeAll {
        $script:OriginalUserPSModulePath = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
    }

    AfterAll {
        # Restore original
        if ($null -ne $script:OriginalUserPSModulePath) {
            [Environment]::SetEnvironmentVariable("PSModulePath", $script:OriginalUserPSModulePath, "User")
        }
    }

    It "Should be available as a function" {
        Get-Command Add-ToPSModulePath -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Should require Path parameter" {
        $cmd = Get-Command Add-ToPSModulePath
        $cmd.Parameters.ContainsKey('Path') | Should -Be $true
    }

    It "Should not throw when given a valid path" {
        $tmp = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
        $tempDir = New-Item -ItemType Directory -Path (Join-Path $tmp "ps-modpath-test-$(Get-Random)") -Force
        try {
            { Add-ToPSModulePath -Path $tempDir.FullName } | Should -Not -Throw
        }
        finally {
            Remove-Item -Recurse -Force $tempDir.FullName -ErrorAction SilentlyContinue
        }
    }

    It "Should be idempotent (adding same path twice does not duplicate)" {
        # Use a unique path so we can deterministically check before/after counts.
        $tmp = if ($env:TEMP) { $env:TEMP } else { '/tmp' }
        $tempDir = New-Item -ItemType Directory -Path (Join-Path $tmp "ps-modpath-idem-$(Get-Random)") -Force
        try {
            Add-ToPSModulePath -Path $tempDir.FullName
            $afterFirst = [Environment]::GetEnvironmentVariable("PSModulePath", "User")
            Add-ToPSModulePath -Path $tempDir.FullName
            $afterSecond = [Environment]::GetEnvironmentVariable("PSModulePath", "User")

            # Count occurrences of the path in PSModulePath
            $countFirst = ($afterFirst -split [IO.Path]::PathSeparator | Where-Object { $_ -eq $tempDir.FullName }).Count
            $countSecond = ($afterSecond -split [IO.Path]::PathSeparator | Where-Object { $_ -eq $tempDir.FullName }).Count

            $countSecond | Should -Be $countFirst
        }
        finally {
            Remove-Item -Recurse -Force $tempDir.FullName -ErrorAction SilentlyContinue
        }
    }
}
