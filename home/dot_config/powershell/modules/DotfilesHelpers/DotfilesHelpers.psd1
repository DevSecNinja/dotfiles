@{
    # Module metadata
    RootModule        = 'DotfilesHelpers.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a3e4b8c1-2d5f-4e6a-9b7c-8d0e1f2a3b4c'
    Author            = 'Jean-Paul van Ravensberg'
    Description       = 'Dotfiles helper functions for PowerShell profile management, system utilities, chezmoi, and winget.'

    # Minimum PowerShell version
    PowerShellVersion = '5.1'

    # Functions to export - explicitly listed to enable module auto-loading / lazy discovery
    FunctionsToExport = @(
        # Navigation
        'Set-LocationUp'
        'Set-LocationUpUp'

        # System utilities
        'which'
        'touch'
        'mkcd'

        # Chezmoi utilities
        'Reset-ChezmoiScripts'
        'Reset-ChezmoiEntries'
        'Invoke-ChezmoiSigning'

        # Winget utilities
        'Test-WingetUpdates'
        'Invoke-WingetUpgrade'

        # Profile management
        'Edit-Profile'
        'Import-Profile'
        'Show-Aliases'

        # Module installation
        'Install-PowerShellModule'
        'Install-GitPowerShellModule'
        'Add-ToPSModulePath'
    )

    # No cmdlets, variables, or aliases exported from this module
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    # Private data
    PrivateData       = @{
        PSData = @{
            Tags       = @('dotfiles', 'profile', 'chezmoi', 'winget')
            ProjectUri = 'https://github.com/DevSecNinja/dotfiles'
        }
    }
}
