#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $modulePath = Join-Path $script:RepoRoot "home/dot_config/powershell/modules/DotfilesHelpers"
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $modulePath -Force -DisableNameChecking
}

Describe "Invoke-GitWithCredentialSwitch" -Tag "Unit" {
    BeforeEach {
        $script:TestDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
        $script:TestBin = Join-Path $script:TestDirectory "bin"
        $script:GitMarker = Join-Path $script:TestDirectory "git-marker"
        $script:GitCalls = Join-Path $script:TestDirectory "git-calls"
        $script:GhCalls = Join-Path $script:TestDirectory "gh-calls"
        New-Item -ItemType Directory -Path $script:TestBin -Force | Out-Null

        @'
@echo off
echo %*>>"%GIT_SWITCH_TEST_CALLS%"
if exist "%GIT_SWITCH_TEST_MARKER%" (
  echo retry succeeded
  exit /b 0
)
echo called>"%GIT_SWITCH_TEST_MARKER%"
echo fatal: Authentication failed for 'https://github.com/DevSecNinja/dotfiles.git/' 1>&2
exit /b 128
'@ | Set-Content -LiteralPath (Join-Path $script:TestBin "git.cmd") -Encoding Ascii

        @'
@echo off
if "%2"=="status" (
  echo {"hosts":{"github.com":[{"state":"success","active":true,"host":"github.com","login":"DevSecNinja","tokenSource":"keyring"},{"state":"success","active":false,"host":"github.com","login":"jeanpaulv_microsoft","tokenSource":"keyring"}]}}
  exit /b 0
)
echo %*>>"%GH_SWITCH_TEST_CALLS%"
exit /b %GH_SWITCH_TEST_EXIT%
'@ | Set-Content -LiteralPath (Join-Path $script:TestBin "gh.cmd") -Encoding Ascii

        $script:OriginalPath = $env:Path
        $env:Path = "$script:TestBin;$env:Path"
        $env:GIT_SWITCH_TEST_MARKER = $script:GitMarker
        $env:GIT_SWITCH_TEST_CALLS = $script:GitCalls
        $env:GH_SWITCH_TEST_CALLS = $script:GhCalls
        $env:GH_SWITCH_TEST_EXIT = "0"
        $env:GIT_CREDENTIAL_SWITCHER_FORCE = "1"
        $env:GIT_CREDENTIAL_SWITCHER_DISABLE = $null
        $env:GH_TOKEN = $null
        $env:GITHUB_TOKEN = $null
    }

    AfterEach {
        $env:Path = $script:OriginalPath
        $env:GIT_SWITCH_TEST_MARKER = $null
        $env:GIT_SWITCH_TEST_CALLS = $null
        $env:GH_SWITCH_TEST_CALLS = $null
        $env:GH_SWITCH_TEST_EXIT = $null
        $env:GIT_CREDENTIAL_SWITCHER_FORCE = $null
        $env:GIT_CREDENTIAL_SWITCHER_DISABLE = $null
        $env:GH_TOKEN = $null
        $env:GITHUB_TOKEN = $null
        Remove-Item -LiteralPath $script:TestDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }

    It "switches the failed host and retries once" {
        Mock Get-GitCredentialSwitchConfirmation -ModuleName DotfilesHelpers { $true }

        $output = Invoke-GitWithCredentialSwitch push origin main 2>&1 6>&1

        $LASTEXITCODE | Should -Be 0
        $output -join "`n" | Should -Match "retry succeeded"
        (Get-Content -LiteralPath $script:GhCalls -Raw).Trim() |
            Should -Be "auth switch --hostname github.com --user jeanpaulv_microsoft"
        @(Get-Content -LiteralPath $script:GitCalls).Count | Should -Be 2
        Should -Invoke Get-GitCredentialSwitchConfirmation -ModuleName DotfilesHelpers -Times 1 -Exactly `
            -ParameterFilter {
                $Message -eq "Failed to authenticate with GitHub credential DevSecNinja. Switch context to jeanpaulv_microsoft and retry git push?"
            }
    }

    It "preserves the original failure when gh account switching fails" {
        Mock Get-GitCredentialSwitchConfirmation -ModuleName DotfilesHelpers { $true }
        $env:GH_SWITCH_TEST_EXIT = "1"

        Invoke-GitWithCredentialSwitch push 2>&1 3>&1 6>&1 | Out-Null

        $LASTEXITCODE | Should -Be 128
        @(Get-Content -LiteralPath $script:GitCalls).Count | Should -Be 1
    }

    It "does not switch or retry when confirmation is declined" {
        Mock Get-GitCredentialSwitchConfirmation -ModuleName DotfilesHelpers { $false }

        Invoke-GitWithCredentialSwitch pull 2>&1 3>&1 6>&1 | Out-Null

        $LASTEXITCODE | Should -Be 128
        $script:GhCalls | Should -Not -Exist
        @(Get-Content -LiteralPath $script:GitCalls).Count | Should -Be 1
    }
}
