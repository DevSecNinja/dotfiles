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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDxqLoWMAHKj7vU
# pGiGn5QrDQD9Vs/ubkhGhuGcdDcAcqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDR2QWAoOLAAvBDT7M8EFKgL3ItaU/EczpqiAdAlpUt7TANBgkqhkiG
# 9w0BAQEFAASCAgBJAuWtgiSr8d7ow/fPOicEy9CTFLuPpvAYDJNUTQHn3LtUEkVq
# FgDxefmAywS4qy/pPqLIjKql/nZlpsDDCoaXVh740HsXUBUgXSjhKPssM/Cooyl6
# gV92e9GWDZiPgUFBEmEh2P9Zd/sqDXUB6S148xTcpsQXXh2xeIbdaVhKx/TUN24A
# oqslcyi65VOFii9zg/4Z6BLxfB+M1XqJ0AK8u4ziA/9YUzXX97jOcO/gvpYLlMth
# BNqCSTGOjHWFJwymd/CwN9Wc0Qc9/RKiJhoHeujTR8SHKR25g9e1SYp6GYxhrhGc
# SicP3LRhs7f28QwrdR//SH1T9msx9QnZd8XzywYN73SCJSETTBIOmm0jEjEcda+I
# CpQC3GwTRc7imo5FMZJAvRR/2kCifkj7UeQ2lpE1EDNR25GBW9+FNEXnwmBW7WTv
# bReCRTPshu/Q3gBaAIyEqHWCYP2yEgPUHfsodbTz3lYmSy5xrQ2DBVBpfFB+oqCJ
# YK0C8CSWz4AQoGt5QG9iVqOln0NtyQ1zZWI6a5GqE9a9wpwihZYNzFejJG/g8ni7
# RP5Nw1crTgefG7DcDAKdYLrDQGDlumB4U6ZoDuIhEpAerbenzH67KxAWDG0TjRm+
# 29V46uHGuUOdb66SM7AvffBM/A4AsjzbPuXXqalgTCzZj0/khmFQvK/cWaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA2MDExMDA2NDdaMC8GCSqGSIb3DQEJBDEi
# BCAe9n+m117rx4DSsd34VWxBvK/4qV02POEBp8ArfoCH8DANBgkqhkiG9w0BAQEF
# AASCAgCYPuEZ7rR8WwRUYIHS/EmzCfIO3yrgscGZrsLcMfUB6pN5JCY0aQM+mbxI
# ZDiyMFB6ZK7TRT4X9uTQLZqfaefz19jC7Ir6mCO1hxhs25eSlBEcrXU7E4XqOOXG
# x5U+EkUwDdTkNKlrhcwO86to2CmBwl3UNHWIpFNty/4/ZviPXbDPJATgYZU9n/g8
# mVgg0fnELw1zgn7d8ARUsh32gY2Us6Jkdpldtf5vGoGXHA/BC7C7YkzAkfETLU7s
# aIvGrY0iX9Nl6E4xi6t6BgfdW1NYnSi1P8vey8wESD40RbHlrIxGvweAPkID6C6O
# 3aDVyroNDzkgC//mHfnZfrjCt3i8YBg07a0qXz2kXSgvib/09n45kCqmRRtw4UfB
# UhHB3guGouziONUKljO0OcbGGgt5A/tnXx8wCr7CIlIu0z3yQswkjr2LYlQ3RTo5
# C0VcB7qfNWrW+zfGB2iGO9qpaSMQjy2DnAIqiN5hhFssvDxcPXT3o5J5ABfKNPR0
# OJiHfqheiv8BT91k7dPojpRUqtbkvl/xIK+PSXrvfSzYMOrisDEEV076HCo9PSiX
# /r5xu29qA8vuhdSghzSBgBwfWc34zeBthdU9QCutoiJkpPER7jymVcUunkjPs/Yw
# z/tVfA6qfJJrmFltASE9FgnoBzymR2D/AZgrXlGFjepGQNno2w==
# SIG # End signature block
