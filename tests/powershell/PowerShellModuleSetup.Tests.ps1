#Requires -Version 5.1

BeforeAll {
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $script:SetupScriptPath = Join-Path $script:RepoRoot "home/.chezmoiscripts/windows/run_once_20-install-modules.ps1.tmpl"
    $script:SetupScriptContent = Get-Content -Path $script:SetupScriptPath -Raw
}

Describe "PowerShell module setup script" -Tag "Unit" {
    It "Should create the PSResourceGet repository directory before configuring PSGallery" {
        $directoryCreation = 'New-Item -ItemType Directory -Path $repositoryStorePath -Force'
        $setRepository = 'Set-PSResourceRepository -Name "PSGallery"'

        $script:SetupScriptContent | Should -Match '\[Environment\]::GetFolderPath\(\[Environment\+SpecialFolder\]::LocalApplicationData\)'
        $script:SetupScriptContent | Should -Match 'Join-Path.+["'']PSResourceGet["'']'
        $script:SetupScriptContent.IndexOf($directoryCreation) | Should -BeGreaterThan -1
        $script:SetupScriptContent.IndexOf($directoryCreation) |
            Should -BeLessThan $script:SetupScriptContent.IndexOf($setRepository)
    }
}
