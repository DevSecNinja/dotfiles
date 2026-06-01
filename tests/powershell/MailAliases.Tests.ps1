<#
.SYNOPSIS
    Pester tests for DotfilesHelpers module

.DESCRIPTION
    Comprehensive Pester tests covering all public functions in the DotfilesHelpers module.
    These tests use mocking to avoid requiring actual Exchange Online connections.

.NOTES
    Author: DotfilesHelpers Contributors
#>

BeforeAll {
    # Create a stub module for the ExchangeOnlineManagement cmdlets so the
    # mail-alias functions resolve (and can be mocked) without a real
    # Exchange Online connection.
    $stubModulePath = Join-Path $PSScriptRoot 'ExchangeOnlineManagement.psm1'
    if (-not (Test-Path $stubModulePath)) {
        New-Item -Path $stubModulePath -ItemType File -Force | Out-Null
        Set-Content -Path $stubModulePath -Value @'
# Stub module to satisfy Exchange Online cmdlet resolution during testing
function Connect-ExchangeOnline { }
function Disconnect-ExchangeOnline { }
function Get-DistributionGroup { }
function New-DistributionGroup { }
function Set-DistributionGroup { }
function Add-RecipientPermission { }
function Add-DistributionGroupMember { }
function Remove-DistributionGroupMember { }
Export-ModuleMember -Function *
'@
    }

    # Import the stub module first so the cmdlets exist and can be mocked
    Import-Module $stubModulePath -Force -Global

    # Import the module under test (mail-alias functions live in DotfilesHelpers)
    $script:RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $ModulePath = Join-Path $script:RepoRoot 'home' 'dot_config' 'powershell' 'modules' 'DotfilesHelpers'
    Get-Module DotfilesHelpers -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $ModulePath -Force -DisableNameChecking

    # Mock Exchange Online cmdlets that are used by the module
    Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
    Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
    Mock Get-PSSession {
        return @()
    } -ModuleName DotfilesHelpers
    Mock Get-DistributionGroup { } -ModuleName DotfilesHelpers
    Mock New-DistributionGroup { } -ModuleName DotfilesHelpers
    Mock Set-DistributionGroup { } -ModuleName DotfilesHelpers
    Mock Add-RecipientPermission { } -ModuleName DotfilesHelpers
    Mock Add-DistributionGroupMember { } -ModuleName DotfilesHelpers
    Mock Remove-DistributionGroupMember { } -ModuleName DotfilesHelpers
}

AfterAll {
    # Clean up the stub module
    $stubModulePath = Join-Path $PSScriptRoot 'ExchangeOnlineManagement.psm1'
    if (Test-Path $stubModulePath) {
        Remove-Module ExchangeOnlineManagement -Force -ErrorAction SilentlyContinue
        Remove-Item $stubModulePath -Force -ErrorAction SilentlyContinue
    }
}

Describe 'New-MailAlias' {
    Context 'Parameter Validation' {
        It 'Should have mandatory parameter: NumberOfAliases' {
            (Get-Command New-MailAlias).Parameters['NumberOfAliases'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have mandatory parameter: EmailDomain' {
            (Get-Command New-MailAlias).Parameters['EmailDomain'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have mandatory parameter: Owner' {
            (Get-Command New-MailAlias).Parameters['Owner'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have mandatory parameter: GroupNamePrefix' {
            (Get-Command New-MailAlias).Parameters['GroupNamePrefix'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have optional parameter: KeepAlive' {
            (Get-Command New-MailAlias).Parameters['KeepAlive'].Attributes.Mandatory | Should -Be $false
        }
    }

    Context 'Typical Usage' {
        BeforeEach {
            Mock Get-PSSession {
                return @()
            } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                return @()
            } -ModuleName DotfilesHelpers
            Mock New-DistributionGroup { } -ModuleName DotfilesHelpers
            Mock Set-DistributionGroup { } -ModuleName DotfilesHelpers
            Mock Add-RecipientPermission { } -ModuleName DotfilesHelpers
            Mock Add-DistributionGroupMember { } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should create specified number of aliases' {
            New-MailAlias -NumberOfAliases 3 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST'

            Should -Invoke New-DistributionGroup -ModuleName DotfilesHelpers -Exactly 3
        }

        It 'Should connect to Exchange Online when no session exists' {
            New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST'

            Should -Invoke Connect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should disconnect from Exchange Online when KeepAlive is not specified' {
            Mock Get-PSSession {
                return @([PSCustomObject]@{ ComputerName = 'outlook.office365.com'; State = 'Opened' })
            } -ModuleName DotfilesHelpers

            New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST'

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should not disconnect from Exchange Online when KeepAlive is specified' {
            New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST' -KeepAlive

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 0
        }

        It 'Should set distribution group properties correctly' {
            New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST'

            Should -Invoke Set-DistributionGroup -ModuleName DotfilesHelpers -Exactly 1
            Should -Invoke Add-RecipientPermission -ModuleName DotfilesHelpers -Exactly 1
            Should -Invoke Add-DistributionGroupMember -ModuleName DotfilesHelpers -Exactly 1
        }
    }

    Context 'Edge Cases' {
        It 'Should skip creation when distribution group name already exists' {
            # Mock Get-Random to return a specific value
            Mock Get-Random {
                return 12345
            } -ModuleName DotfilesHelpers
            
            # Mock Get-DistributionGroup to return a matching name
            Mock Get-DistributionGroup {
                return @([PSCustomObject]@{ Name = 'TEST12345' })
            } -ModuleName DotfilesHelpers
            
            Mock New-DistributionGroup { } -ModuleName DotfilesHelpers

            New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST' -Verbose

            Should -Invoke New-DistributionGroup -ModuleName DotfilesHelpers -Exactly 0
        }

        It 'Should handle New-DistributionGroup exceptions' {
            Mock Get-DistributionGroup {
                return @()
            } -ModuleName DotfilesHelpers
            
            Mock New-DistributionGroup {
                throw "Distribution Group already exists"
            } -ModuleName DotfilesHelpers

            { New-MailAlias -NumberOfAliases 1 -EmailDomain 'contoso.com' -Owner 'admin@contoso.com' -GroupNamePrefix 'TEST' -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe 'Select-MailAlias' {
    Context 'Parameter Validation' {
        It 'Should have mandatory parameter: DomainName' {
            (Get-Command Select-MailAlias).Parameters['DomainName'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have optional parameter: ExportAliasesToMailDraft' {
            (Get-Command Select-MailAlias).Parameters['ExportAliasesToMailDraft'].Attributes.Mandatory | Should -Be $false
        }

        It 'Should have optional parameter: KeepAlive' {
            (Get-Command Select-MailAlias).Parameters['KeepAlive'].Attributes.Mandatory | Should -Be $false
        }
    }

    Context 'Typical Usage - Existing Alias' {
        BeforeEach {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                param($Identity)
                return @([PSCustomObject]@{
                    Name = 'TEST12345'
                    DisplayName = 'Google.com - contoso.com'
                    PrimarySmtpAddress = 'TEST12345@contoso.com'
                })
            } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should return existing alias when domain already has one' {
            $result = Select-MailAlias -DomainName 'Google.com'

            $result.Name | Should -Be 'TEST12345'
            $result.DisplayName | Should -Be 'Google.com - contoso.com'
            $result.'E-mail' | Should -Be 'TEST12345@contoso.com'
        }

        It 'Should not modify existing alias' {
            Select-MailAlias -DomainName 'Google.com'

            Should -Invoke Set-DistributionGroup -ModuleName DotfilesHelpers -Exactly 0
        }
    }

    Context 'Typical Usage - New Alias' {
        BeforeEach {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                param($Identity)
                # First call: Check for existing domain alias - returns nothing
                # Second call: Get claimable aliases
                if ($null -ne $Identity) {
                    return $null
                }
                return @([PSCustomObject]@{
                    Name = 'TEST12345'
                    DisplayName = 'TEST12345_CLAIMABLE'
                    PrimarySmtpAddress = 'TEST12345@contoso.com'
                    WhenCreated = (Get-Date).AddHours(-2)
                    WhenCreatedUtc = (Get-Date).AddHours(-2)
                })
            } -ModuleName DotfilesHelpers
            Mock Set-DistributionGroup { } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should claim a claimable alias when domain does not have one' {
            $result = Select-MailAlias -DomainName 'NewDomain.com'

            $result.Name | Should -Be 'TEST12345'
            $result.DisplayName | Should -Be 'NewDomain.com - contoso.com'
        }

        It 'Should rename claimable alias to domain name' {
            Select-MailAlias -DomainName 'NewDomain.com'

            Should -Invoke Set-DistributionGroup -ModuleName DotfilesHelpers -Exactly 1
        }
    }

    Context 'Edge Cases' {
        It 'Should throw error when no claimable aliases are found' {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                return $null
            } -ModuleName DotfilesHelpers

            { Select-MailAlias -DomainName 'Test.com' -ErrorAction Stop } | Should -Throw
        }

        It 'Should warn when alias is less than 60 minutes old' {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                param($Identity)
                if ($null -eq $Identity) {
                    return @([PSCustomObject]@{
                        Name = 'TEST12345'
                        DisplayName = 'TEST12345_CLAIMABLE'
                        PrimarySmtpAddress = 'TEST12345@contoso.com'
                        WhenCreated = (Get-Date).AddMinutes(-30)
                        WhenCreatedUtc = (Get-Date).AddMinutes(-30)
                    })
                }
                return $null
            } -ModuleName DotfilesHelpers
            Mock Set-DistributionGroup { } -ModuleName DotfilesHelpers
            Mock Write-Warning { } -ModuleName DotfilesHelpers

            Select-MailAlias -DomainName 'NewDomain.com' -WarningAction SilentlyContinue

            Should -Invoke Write-Warning -ModuleName DotfilesHelpers -Exactly 1
        }
    }
}

Describe 'Get-UsedMailAlias' {
    Context 'Parameter Validation' {
        It 'Should have optional parameter: GroupNamePrefix' {
            (Get-Command Get-UsedMailAlias).Parameters['GroupNamePrefix'].Attributes.Mandatory | Should -Be $false
        }

        It 'Should have optional parameter: ExportAliasesToMailDraft' {
            (Get-Command Get-UsedMailAlias).Parameters['ExportAliasesToMailDraft'].Attributes.Mandatory | Should -Be $false
        }

        It 'Should have optional parameter: KeepAlive' {
            (Get-Command Get-UsedMailAlias).Parameters['KeepAlive'].Attributes.Mandatory | Should -Be $false
        }
    }

    Context 'Typical Usage' {
        BeforeEach {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                return @(
                    [PSCustomObject]@{
                        Name = 'TEST12345'
                        DisplayName = 'Google.com - contoso.com'
                        PrimarySmtpAddress = 'TEST12345@contoso.com'
                    },
                    [PSCustomObject]@{
                        Name = 'TEST67890'
                        DisplayName = 'Microsoft.com - contoso.com'
                        PrimarySmtpAddress = 'TEST67890@contoso.com'
                    }
                )
            } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should return used mail aliases' {
            $result = Get-UsedMailAlias -GroupNamePrefix 'TEST'

            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'TEST12345'
            $result[1].Name | Should -Be 'TEST67890'
        }

        It 'Should return aliases sorted by DisplayName' {
            $result = Get-UsedMailAlias -GroupNamePrefix 'TEST'

            $result[0].DisplayName | Should -Be 'Google.com - contoso.com'
            $result[1].DisplayName | Should -Be 'Microsoft.com - contoso.com'
        }

        It 'Should connect to Exchange Online when no session exists' {
            Get-UsedMailAlias -GroupNamePrefix 'TEST'

            Should -Invoke Connect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should disconnect from Exchange Online when KeepAlive is not specified' {
            Mock Get-PSSession {
                return @([PSCustomObject]@{ ComputerName = 'outlook.office365.com'; State = 'Opened' })
            } -ModuleName DotfilesHelpers

            Get-UsedMailAlias -GroupNamePrefix 'TEST'

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }
    }

    Context 'Edge Cases' {
        It 'Should return nothing when no used aliases exist' {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup { return $null } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers

            $result = Get-UsedMailAlias -GroupNamePrefix 'TEST'

            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Get-UnusedMailAlias' {
    Context 'Parameter Validation' {
        It 'Should have optional parameter: GroupNamePrefix' {
            (Get-Command Get-UnusedMailAlias).Parameters['GroupNamePrefix'].Attributes.Mandatory | Should -Be $false
        }

        It 'Should have optional parameter: KeepAlive' {
            (Get-Command Get-UnusedMailAlias).Parameters['KeepAlive'].Attributes.Mandatory | Should -Be $false
        }
    }

    Context 'Typical Usage' {
        BeforeEach {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                return @(
                    [PSCustomObject]@{
                        Name = 'TEST11111'
                        DisplayName = 'TEST11111_CLAIMABLE'
                        PrimarySmtpAddress = 'TEST11111@contoso.com'
                    },
                    [PSCustomObject]@{
                        Name = 'TEST22222'
                        DisplayName = 'TEST22222_CLAIMABLE'
                        PrimarySmtpAddress = 'TEST22222@contoso.com'
                    }
                )
            } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should return unused mail aliases' {
            $result = Get-UnusedMailAlias -GroupNamePrefix 'TEST'

            $result.Count | Should -Be 2
            $result[0].Name | Should -Be 'TEST11111'
            $result[1].Name | Should -Be 'TEST22222'
        }

        It 'Should return only aliases with _CLAIMABLE suffix' {
            $result = Get-UnusedMailAlias -GroupNamePrefix 'TEST'

            $result[0].DisplayName | Should -Match '_CLAIMABLE$'
            $result[1].DisplayName | Should -Match '_CLAIMABLE$'
        }

        It 'Should connect to Exchange Online when no session exists' {
            Get-UnusedMailAlias -GroupNamePrefix 'TEST'

            Should -Invoke Connect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should disconnect from Exchange Online when KeepAlive is not specified' {
            Mock Get-PSSession {
                return @([PSCustomObject]@{ ComputerName = 'outlook.office365.com'; State = 'Opened' })
            } -ModuleName DotfilesHelpers

            Get-UnusedMailAlias -GroupNamePrefix 'TEST'

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }
    }

    Context 'Edge Cases' {
        It 'Should return nothing when no unused aliases exist' {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup { return $null } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers

            $result = Get-UnusedMailAlias -GroupNamePrefix 'TEST'

            $result | Should -BeNullOrEmpty
        }
    }
}

Describe 'Set-MailAliasToArchived' {
    Context 'Parameter Validation' {
        It 'Should have mandatory parameter: DomainName' {
            (Get-Command Set-MailAliasToArchived).Parameters['DomainName'].Attributes.Mandatory | Should -Be $true
        }

        It 'Should have optional parameter: KeepAlive' {
            (Get-Command Set-MailAliasToArchived).Parameters['KeepAlive'].Attributes.Mandatory | Should -Be $false
        }
    }

    Context 'Typical Usage' {
        BeforeEach {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup {
                param($Identity)
                if ($null -eq $Identity) {
                    return @([PSCustomObject]@{
                        Identity = 'TEST12345'
                        Name = 'TEST12345'
                        DisplayName = 'Google.com - contoso.com'
                        PrimarySmtpAddress = 'TEST12345@contoso.com'
                    })
                } else {
                    return [PSCustomObject]@{
                        Identity = $Identity
                        Name = 'TEST12345'
                        DisplayName = '(Archived) Google.com - contoso.com'
                        PrimarySmtpAddress = 'TEST12345@contoso.com'
                    }
                }
            } -ModuleName DotfilesHelpers
            Mock Set-DistributionGroup { } -ModuleName DotfilesHelpers
            Mock Remove-DistributionGroupMember { } -ModuleName DotfilesHelpers
            Mock Disconnect-ExchangeOnline { } -ModuleName DotfilesHelpers
        }

        It 'Should archive the specified alias' {
            $result = Set-MailAliasToArchived -DomainName 'Google.com'

            $result.DisplayName | Should -Be '(Archived) Google.com - contoso.com'
        }

        It 'Should update display name with (Archived) prefix' {
            Set-MailAliasToArchived -DomainName 'Google.com'

            Should -Invoke Set-DistributionGroup -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should remove members from distribution group' {
            Set-MailAliasToArchived -DomainName 'Google.com'

            Should -Invoke Remove-DistributionGroupMember -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should connect to Exchange Online when no session exists' {
            Set-MailAliasToArchived -DomainName 'Google.com'

            Should -Invoke Connect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should disconnect from Exchange Online when KeepAlive is not specified' {
            Mock Get-PSSession {
                return @([PSCustomObject]@{ ComputerName = 'outlook.office365.com'; State = 'Opened' })
            } -ModuleName DotfilesHelpers

            Set-MailAliasToArchived -DomainName 'Google.com'

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 1
        }

        It 'Should not disconnect when KeepAlive is specified' {
            Set-MailAliasToArchived -DomainName 'Google.com' -KeepAlive

            Should -Invoke Disconnect-ExchangeOnline -ModuleName DotfilesHelpers -Exactly 0
        }
    }

    Context 'Error Cases' {
        It 'Should throw error when domain name does not exist' {
            Mock Get-PSSession { return @() } -ModuleName DotfilesHelpers
            Mock Connect-ExchangeOnline { } -ModuleName DotfilesHelpers
            Mock Get-DistributionGroup { return $null } -ModuleName DotfilesHelpers

            { Set-MailAliasToArchived -DomainName 'NonExistent.com' -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe 'Module Integration' {
    Context 'Module Loading' {
        It 'Should export New-MailAlias function' {
            Get-Command New-MailAlias -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Select-MailAlias function' {
            Get-Command Select-MailAlias -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-UsedMailAlias function' {
            Get-Command Get-UsedMailAlias -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Get-UnusedMailAlias function' {
            Get-Command Get-UnusedMailAlias -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }

        It 'Should export Set-MailAliasToArchived function' {
            Get-Command Set-MailAliasToArchived -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        }
    }
}
