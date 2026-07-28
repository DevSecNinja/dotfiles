#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for adding OneDrive Portable Programs to PATH.

.DESCRIPTION
    Tests the user-scope PATH helper without writing to the registry and checks
    that the PowerShell profile keeps the current session update cheap.
#>

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    Push-Location $script:RepoRoot

    $script:PortableProgramsScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_onchange_add-portable-programs-path.ps1"
    $script:ProfilePath = Join-Path $script:RepoRoot "home\dot_config\powershell\profile.ps1"

    . $script:PortableProgramsScriptPath -SkipApply
}

AfterAll {
    Pop-Location
}

Describe "Portable Programs PATH Script" -Tag "Unit" {
    It "script file should exist" {
        $script:PortableProgramsScriptPath | Should -Exist
    }

    It "script should have valid PowerShell syntax" {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:PortableProgramsScriptPath,
            [ref]$null,
            [ref]$errors
        ) | Out-Null

        $errors | Should -BeNullOrEmpty
    }

    It "should read the raw user PATH without expanding percent variables" {
        $content = Get-Content -LiteralPath $script:PortableProgramsScriptPath -Raw
        $content | Should -Match "DoNotExpandEnvironmentNames"
        $content | Should -Not -Match "GetEnvironmentVariable\(.+User"
    }

    It "should write only the user-scope PATH variable" {
        $content = Get-Content -LiteralPath $script:PortableProgramsScriptPath -Raw
        $content | Should -Match "OpenSubKey\(`"Environment`",\s*\`$true\)"
        $content | Should -Match "SetValue\(\`$writeInfo\.ValueName,\s*\`$Path,\s*\`$writeInfo\.Kind\)"
        $content | Should -Not -Match "SetEnvironmentVariable"
        $content | Should -Not -Match "`"Machine`""
    }

    It "should preserve an existing ExpandString registry value kind" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName "PATH" `
            -Kind ([Microsoft.Win32.RegistryValueKind]::ExpandString) `
            -Value "C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "PATH"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should choose ExpandString for a new value containing percent variables" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName $null `
            -Kind $null `
            -Value "%USERPROFILE%\bin;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "Path"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should choose String for a new plain value" {
        $info = Resolve-UserPathRegistryWriteInfo `
            -ValueName $null `
            -Kind $null `
            -Value "C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"

        $info.ValueName | Should -Be "Path"
        $info.Kind | Should -Be ([Microsoft.Win32.RegistryValueKind]::String)
    }

    It "should detect existing entries case-insensitively and ignore trailing backslashes" {
        $pathList = "C:\Tools;c:\users\demo\onedrive\portable programs\"

        Test-PathListContainsEntry -PathList $pathList -Entry "C:\Users\Demo\OneDrive\Portable Programs" |
            Should -Be $true
    }

    It "should append the Portable Programs path without expanding existing variables" {
        $userPath = "%USERPROFILE%\bin;C:\Tools"
        $entry = "C:\Users\Demo\OneDrive\Portable Programs"

        Add-PathListEntry -PathList $userPath -Entry $entry |
            Should -Be "%USERPROFILE%\bin;C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"
    }

    It "should not add a duplicate entry" {
        $userPath = "%USERPROFILE%\bin;C:\Users\Demo\OneDrive\Portable Programs\"
        $entry = "c:\users\demo\onedrive\portable programs"

        Add-PathListEntry -PathList $userPath -Entry $entry |
            Should -Be $userPath
    }

    It "should do nothing when OneDrive is not configured" {
        $script:PathExistsCalled = $false
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath $null `
            -PathExists { $script:PathExistsCalled = $true; $true } `
            -SetUserPath { $script:SetUserPathCalled = $true }

        $result.Status | Should -Be "OneDriveMissing"
        $result.Changed | Should -Be $false
        $script:PathExistsCalled | Should -Be $false
        $script:SetUserPathCalled | Should -Be $false
    }

    It "should skip persistence when Portable Programs does not exist" {
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $false } `
            -GetUserPath { "%USERPROFILE%\bin" } `
            -SetUserPath { $script:SetUserPathCalled = $true }

        $result.Status | Should -Be "PortableProgramsMissing"
        $result.Changed | Should -Be $false
        $script:SetUserPathCalled | Should -Be $false
    }

    It "should append and persist the user PATH when the folder exists" {
        $script:WrittenUserPath = $null
        $script:WrittenValueName = $null
        $script:WrittenValueKind = $null

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $true } `
            -GetUserPath {
                [pscustomobject]@{
                    Value     = "%USERPROFILE%\bin;C:\Tools"
                    ValueName = "PATH"
                    Kind      = [Microsoft.Win32.RegistryValueKind]::ExpandString
                }
            } `
            -SetUserPath {
                param(
                    [string]$Path,
                    [string]$ValueName,
                    [object]$Kind
                )
                $script:WrittenUserPath = $Path
                $script:WrittenValueName = $ValueName
                $script:WrittenValueKind = $Kind
            }

        $result.Status | Should -Be "Updated"
        $result.Changed | Should -Be $true
        $script:WrittenUserPath | Should -Be "%USERPROFILE%\bin;C:\Tools;C:\Users\Demo\OneDrive\Portable Programs"
        $script:WrittenValueName | Should -Be "PATH"
        $script:WrittenValueKind | Should -Be ([Microsoft.Win32.RegistryValueKind]::ExpandString)
    }

    It "should not write under WhatIf" {
        $script:SetUserPathCalled = $false

        $result = Add-PortableProgramsToUserPath `
            -OneDrivePath "C:\Users\Demo\OneDrive" `
            -PathExists { $true } `
            -GetUserPath { "C:\Tools" } `
            -SetUserPath { $script:SetUserPathCalled = $true } `
            -WhatIf

        $result.Status | Should -Be "Updated"
        $result.Changed | Should -Be $true
        $script:SetUserPathCalled | Should -Be $false
    }
}

Describe "PowerShell profile Portable Programs PATH" -Tag "Unit" {
    BeforeAll {
        $script:ProfileContent = Get-Content -LiteralPath $script:ProfilePath -Raw
    }

    It "should use OneDrive and Portable Programs for the session PATH update" {
        $script:ProfileContent | Should -Match "env:OneDrive"
        $script:ProfileContent | Should -Match "Portable Programs"
        $script:ProfileContent | Should -Match "env:Path"
    }

    It "should use a simple string check instead of reading the registry" {
        $script:ProfileContent | Should -Match "-split ';'"
        $script:ProfileContent | Should -Match "TrimEnd\('\\'\)"
        $script:ProfileContent | Should -Match "ToUpperInvariant"
        $script:ProfileContent | Should -Not -Match "GetEnvironmentVariable\(.+User"
        $script:ProfileContent | Should -Not -Match "Microsoft\.Win32\.Registry|RegistryValueOptions|Get-ItemProperty.*HKCU"
    }
}
