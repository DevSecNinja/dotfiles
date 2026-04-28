#Requires -Version 5.1
<#
.SYNOPSIS
    Pester tests for PowerShell aliases defined in aliases.ps1.

.DESCRIPTION
    Tests that aliases.ps1 defines the expected aliases and helper functions,
    that the file has valid syntax, and that key alias targets exist.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $script:AliasesPath = Join-Path $script:RepoRoot "home/dot_config/powershell/aliases.ps1"

    # Make navigation aliases like "..", "..." and others work without side
    # effects (they use Set-LocationUp which is from DotfilesHelpers). Import the
    # module first so Set-Alias targets resolve.
    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking

    # Read aliases.ps1 content and dot-source it in a fresh scope captured by Invoke-Expression
    # We dot-source at the script-level so the aliases/functions are visible to Pester's tests.
    . $script:AliasesPath
}

AfterAll {
    Pop-Location
}

Describe "aliases.ps1 file" -Tag "Unit" {
    It "Should exist" {
        $script:AliasesPath | Should -Exist
    }

    It "Should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:AliasesPath, [ref]$null, [ref]$errors
        ) | Out-Null
        $errors.Count | Should -Be 0
    }
}

Describe "Navigation aliases" -Tag "Unit" {
    It "alias '..' should map to Set-LocationUp" {
        $a = Get-Alias '..' -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Set-LocationUp'
    }

    It "alias '...' should map to Set-LocationUpUp" {
        $a = Get-Alias '...' -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Set-LocationUpUp'
    }
}

Describe "Listing aliases (ll, la)" -Tag "Unit" {
    It "Function 'll' should exist" {
        Get-Command ll -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "Function 'la' should exist" {
        Get-Command la -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "'ll' should call Get-ChildItem with -Force" {
        $body = (Get-Command ll).ScriptBlock.ToString()
        $body | Should -Match 'Get-ChildItem'
        $body | Should -Match '-Force'
    }
}

Describe "Git aliases" -Tag "Unit" {
    It "Function '<name>' should exist and call git" -ForEach @(
        @{ name = 'g' }
        @{ name = 'gs' }
        @{ name = 'ga' }
        @{ name = 'gc' }
        @{ name = 'gps' }
        @{ name = 'gpl' }
        @{ name = 'gl' }
        @{ name = 'gd' }
        @{ name = 'gco' }
        @{ name = 'gb' }
    ) {
        $cmd = Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $body = $cmd.ScriptBlock.ToString()
        $body | Should -Match 'git'
    }

    It "'gs' should specifically call 'git status'" {
        (Get-Command gs).ScriptBlock.ToString() | Should -Match 'git\s+status'
    }

    It "'gl' should call 'git log --oneline --graph'" {
        (Get-Command gl -CommandType Function).ScriptBlock.ToString() | Should -Match 'git\s+log\s+--oneline\s+--graph'
    }
}

Describe "Docker aliases" -Tag "Unit" {
    It "Function '<name>' should exist and reference docker" -ForEach @(
        @{ name = 'd' }
        @{ name = 'dc' }
        @{ name = 'dps' }
        @{ name = 'dpsa' }
        @{ name = 'di' }
        @{ name = 'dex' }
    ) {
        $cmd = Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.ScriptBlock.ToString() | Should -Match 'docker'
    }

    It "'dc' should call 'docker compose'" {
        (Get-Command dc).ScriptBlock.ToString() | Should -Match 'docker\s+compose'
    }

    It "'dpsa' should call 'docker ps -a'" {
        (Get-Command dpsa).ScriptBlock.ToString() | Should -Match 'docker\s+ps\s+-a'
    }

    It "'dex' should call 'docker exec -it'" {
        (Get-Command dex).ScriptBlock.ToString() | Should -Match 'docker\s+exec\s+-it'
    }
}

Describe "Profile management aliases" -Tag "Unit" {
    It "alias 'ep' should map to Edit-Profile" {
        $a = Get-Alias ep -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Edit-Profile'
    }

    It "alias 'reload' should map to Import-Profile" {
        $a = Get-Alias reload -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Import-Profile'
    }

    It "alias 'aliases' should map to Show-Aliases" {
        $a = Get-Alias aliases -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Show-Aliases'
    }
}

Describe "Shell introspection helpers" -Tag "Unit" {
    It "Function 'paths' should exist and split PATH" {
        $cmd = Get-Command paths -CommandType Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $body = $cmd.ScriptBlock.ToString()
        $body | Should -Match 'PATH'
        $body | Should -Match 'PathSeparator'
    }

    It "'paths' should return an array of path entries" {
        $result = paths
        $result | Should -Not -BeNullOrEmpty
        # Should match the count from manually splitting PATH
        $expected = $env:PATH -split [IO.Path]::PathSeparator
        @($result).Count | Should -Be @($expected).Count
    }

    It "Function 'functions' should exist" {
        Get-Command functions -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }
}

Describe "fastfetch / system info aliases" -Tag "Unit" {
    It "Function '<name>' should exist and reference fastfetch" -ForEach @(
        @{ name = 'ff' }
        @{ name = 'sysinfo' }
        @{ name = 'motd' }
    ) {
        $cmd = Get-Command $name -CommandType Function -ErrorAction SilentlyContinue
        $cmd | Should -Not -BeNullOrEmpty
        $cmd.ScriptBlock.ToString() | Should -Match 'fastfetch'
    }
}

Describe "Winget aliases" -Tag "Unit" {
    It "alias 'wup' should map to Invoke-WingetUpgrade" {
        $a = Get-Alias wup -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Invoke-WingetUpgrade'
    }

    It "alias 'winup' should map to Invoke-WingetUpgrade" {
        $a = Get-Alias winup -ErrorAction SilentlyContinue
        $a | Should -Not -BeNullOrEmpty
        $a.Definition | Should -Be 'Invoke-WingetUpgrade'
    }
}

Describe "SSH helper" -Tag "Unit" {
    It "Function 'pubkey' should exist" {
        Get-Command pubkey -CommandType Function -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
    }

    It "'pubkey' should reference id_rsa.pub and Set-Clipboard" {
        $body = (Get-Command pubkey).ScriptBlock.ToString()
        $body | Should -Match 'id_rsa\.pub'
        $body | Should -Match 'Set-Clipboard'
    }
}
