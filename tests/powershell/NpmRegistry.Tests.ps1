#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:NpmRegistryScriptPath = Join-Path $script:RepoRoot "home\.chezmoiscripts\windows\run_always_30-configure-npm-registry.ps1"
    $script:NpmRegistryScriptContent = Get-Content -Path $script:NpmRegistryScriptPath -Raw
}

Describe "Microsoft work npm registry setup script" -Tag "Unit" {
    It "Should be a native PowerShell script" {
        $script:NpmRegistryScriptPath | Should -Not -Match '\.tmpl$'
        $script:NpmRegistryScriptContent |
            Should -Not -Match '\{\{'
    }

    It "Should prefer the inherited work-device environment variable" {
        $script:NpmRegistryScriptContent |
            Should -Match 'env:CHEZMOI_IS_WORK'
        $script:NpmRegistryScriptContent |
            Should -Match 'CHEZMOI_IS_WORK -eq "true"'
    }

    It "Should reject an invalid work-device environment value" {
        $script:NpmRegistryScriptContent |
            Should -Match '\^\(\?i:true\|false\)\$'
        $script:NpmRegistryScriptContent |
            Should -Match 'CHEZMOI_IS_WORK must be either true or false'
    }

    It "Should fall back to Chezmoi data during bootstrap" {
        $script:NpmRegistryScriptContent |
            Should -Match 'chezmoi data --format json'
        $script:NpmRegistryScriptContent |
            Should -Match '\$isWork = \[bool\]\$chezmoiData\.isWork'

        $workCheck = $script:NpmRegistryScriptContent.IndexOf('if (-not $isWork)')
        $npmCheck = $script:NpmRegistryScriptContent.IndexOf('if (-not (Get-Command npm')
        $workCheck | Should -BeGreaterThan -1
        $workCheck | Should -BeLessThan $npmCheck
    }

    It "Should configure the Microsoft proxy at user scope" {
        $script:NpmRegistryScriptContent |
            Should -Match 'npm config set registry "https://packagefeedproxy\.microsoft\.io/npm/" --location=user'
    }

    It "Should skip when npm is unavailable" {
        $script:NpmRegistryScriptContent |
            Should -Match 'Get-Command npm -ErrorAction SilentlyContinue'
        $script:NpmRegistryScriptContent |
            Should -Match '\[SKIP\] npm is not installed'
    }

    It "Should fail when npm cannot update the registry" {
        $script:NpmRegistryScriptContent |
            Should -Match '\$LASTEXITCODE -ne 0'
        $script:NpmRegistryScriptContent |
            Should -Match 'Write-Error "npm failed'
    }
}
