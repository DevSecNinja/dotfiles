# Office 365 mail alias helpers
#
# Functions to create and manage unique Office 365 mail aliases backed by
# Exchange Online distribution groups. These require the ExchangeOnlineManagement
# module and appropriate Exchange permissions at runtime; they are intentionally
# loaded without a hard "#Requires -Modules ExchangeOnlineManagement" so the
# DotfilesHelpers module still imports on machines where that module is absent.
#
# Originally the standalone "Office365MailAliases" module
# (https://github.com/DevSecNinja/Office365AliasModule).
#
# Author: Jean-Paul van Ravensberg, Cloudenius.com
#
# Examples:
#   Select-MailAlias -DomainName Google.com -ExportAliasesToMailDraft -Verbose
#   New-MailAlias -NumberOfAliases 9 -Verbose

Function New-MailAlias {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '*', Scope = 'Function', Target = '*', Justification = 'Does not change system state')]
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the amount of aliases required")]
        [ValidateNotNullOrEmpty()]
        [int]$NumberOfAliases,

        [parameter(Mandatory = $true, HelpMessage = "Specify the domain name that is used for the email address. E.g. johndoe.com")]
        [ValidateNotNullOrEmpty()]
        [string]$EmailDomain,

        [parameter(Mandatory = $true, HelpMessage = "Specify the owner of the alias. E.g. john@johndoe.com")]
        [ValidateNotNullOrEmpty()]
        [string]$Owner,

        [parameter(Mandatory = $true, HelpMessage = "Specify the prefix that will be used to create the alias. E.g. JD")]
        [ValidateNotNullOrEmpty()]
        [string]$GroupNamePrefix,

        [parameter(Mandatory = $false, HelpMessage = "Keep the Exchange Online session alive for further use")]
        [switch]$KeepAlive
    )

    ## Login to Office 365
    If (!(Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" })) {
        Connect-ExchangeOnline -ShowBanner:$false
    }

    Write-Verbose "Creating $NumberOfAliases aliases"

    Foreach ($i in 1..$NumberOfAliases) {
        $Random = Get-Random -Minimum 10000 -Maximum 99999
        $GroupName = $GroupNamePrefix + $Random
        $GroupEmail = ($GroupName + "@" + $EmailDomain)

        Write-Verbose "Creating alias $i with name $GroupName"

        If (Get-DistributionGroup | Where-Object { $_.Name -like "*$GroupName*" }) {
            Write-Verbose "Distribution Group name is not unique. Will skip name $GroupName"
        }

        Else {
            # Create the new Distribution Group
            Try {
                New-DistributionGroup -Name $GroupName -Type "Security" -ManagedBy $Owner -PrimarySmtpAddress $GroupEmail
            }

            Catch [Exception] {
                Write-Error "Distribution Group already exists or another error occurred"
                Break
            }

            # Allow external senders to mail to the address & set _CLAIMABLE suffix
            Set-DistributionGroup -Identity $GroupName -RequireSenderAuthenticationEnabled:$false -DisplayName $($GroupName + "_CLAIMABLE")

            # Modify the new Distribution Group with SendOnBehalf permissions
            Add-RecipientPermission -Identity $GroupName -AccessRights SendAs -Trustee $Owner -Confirm:$false

            # Add the owner to the Distribution Group
            Add-DistributionGroupMember -Identity $GroupName -Member $Owner

            Write-Verbose "Created group called $GroupName with owner $Owner"
        }
    }

    # Disconnect the session to make sure we don't run out of maximum concurrent connections
    If (!$KeepAlive) {
        If (Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" }) {
            $Null = Disconnect-ExchangeOnline -Confirm:$false
        }
    }
}

Function Select-MailAlias {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the domain name of the website")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [parameter(Mandatory = $false, HelpMessage = "Create a draft mail in the mailbox of the user that contains all the used mail aliases")]
        [switch]$ExportAliasesToMailDraft,

        [parameter(Mandatory = $false, HelpMessage = "Keep the Exchange Online session alive for further use")]
        [switch]$KeepAlive
    )

    ## Login to Office 365
    If (!(Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" })) {
        Connect-ExchangeOnline -ShowBanner:$false
    }

    Write-Verbose "Claiming an alias for $DomainName"

    # Check if domain name already exists in Distribution Group
    $ExistingDistributionGroup = Get-DistributionGroup | Where-Object { $_.DisplayName -like "$DomainName - *" }

    If ($ExistingDistributionGroup) {
        Write-Output "Alias for domain name '$($DomainName)' already exists. Returning the alias already in use"

        $DistributionGroup = $ExistingDistributionGroup

        $EmailDomain = $DistributionGroup.PrimarySmtpAddress.Split('@')[1]
        $DisplayName = $DomainName + " - " + $EmailDomain
    }

    Else {
        # Search for unused alias and return the oldest one
        $ClaimableDistributionGroups = Get-DistributionGroup | Where-Object { $_.DisplayName -Like "*_CLAIMABLE" } | Sort-Object WhenCreatedUtc

        If (!($ClaimableDistributionGroups)) {
            Write-Error "No claimable Mail Aliases found. Please run New-MailAlias first."
            Break
        }

        While (!($ClaimableDistributionGroups = Get-DistributionGroup | Where-Object { $_.DisplayName -Like "*_CLAIMABLE" })) {
            Write-Output "Waiting for a new claimable Distribution Group. Pause 5 seconds..."
            Start-Sleep -Seconds 5
        }

        Write-Verbose "Found $($ClaimableDistributionGroups.GetType().Count) claimable Distribution Group(s)"

        # Rename unused alias & change description
        $DistributionGroup = $ClaimableDistributionGroups[0]

        Write-Verbose "Picking $DistributionGroup for the rename"

        If ($DistributionGroup.WhenCreated.AddHours(1) -gt (Get-Date)) {
            Write-Warning "Be aware that this alias is <60 minutes old and might not be active yet"
        }

        # Change the Display Name for the Distribution Group
        $EmailDomain = $DistributionGroup.PrimarySmtpAddress.Split('@')[1]
        $DisplayName = $DomainName + " - " + $EmailDomain

        Set-DistributionGroup -Identity $DistributionGroup.Name -DisplayName $DisplayName
    }

    # Create the draft mail in the mailbox of the user that contains all the used mail aliases
    If ($ExportAliasesToMailDraft) {
        $MailMessage = New-MailMessage -Body (Get-UsedMailAlias | Select-Object Name, DisplayName | Sort-Object DisplayName | Out-String) -Subject "Used Mailbox Aliases"

        if ($MailMessage) {
            Write-Output "Successfully created draft mail message with subject '$($MailMessage.Subject)' and object state '$($MailMessage.ObjectState)'"
        }

        Else {
            Write-Warning "Something went wrong with creating the draft mail message"
        }
    }

    # Disconnect the session to make sure we don't run out of maximum concurrent connections
    If (!$KeepAlive) {
        If (Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" }) {
            $Null = Disconnect-ExchangeOnline -Confirm:$false
        }
    }

    # Return the new name of the alias
    return New-Object PSObject -Property ([ordered]@{"Name" = $DistributionGroup.Name; "DisplayName" = $DisplayName; "E-mail" = $DistributionGroup.PrimarySmtpAddress })
}

Function Get-UsedMailAlias {
    param(
        [parameter(Mandatory = $false, HelpMessage = "Name prefix that is used to identify the Mail Aliases")]
        [ValidateNotNullOrEmpty()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '$GroupNamePrefix', Justification = 'False positive')]
        [string]$GroupNamePrefix,

        [parameter(Mandatory = $false, HelpMessage = "Create a draft mail in the mailbox of the user that contains all the used mail aliases")]
        [switch]$ExportAliasesToMailDraft,

        [parameter(Mandatory = $false, HelpMessage = "Keep the Exchange Online session alive for further use")]
        [switch]$KeepAlive
    )

    ## Login to Office 365
    If (!(Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" })) {
        Connect-ExchangeOnline -ShowBanner:$false
    }

    # Check if domain name already exists in Distribution Group
    $ExistingDistributionGroup = Get-DistributionGroup | Where-Object `
    { $_.Name -like "$GroupNamePrefix*" -and $_.DisplayName -notlike "*_CLAIMABLE" }

    # Create the draft mail in the mailbox of the user that contains all the used mail aliases
    If ($ExistingDistributionGroup -and $ExportAliasesToMailDraft) {
        $MailMessage = New-MailMessage -Body ($ExistingDistributionGroup | Select-Object Name, DisplayName | Sort-Object DisplayName | Out-String) -Subject "Used Mailbox Aliases"

        if ($MailMessage) {
            Write-Output "Successfully created draft mail message with subject '$($MailMessage.Subject)' and object state '$($MailMessage.ObjectState)'"
        }

        Else {
            Write-Warning "Something went wrong with creating the draft mail message"
        }
    }

    # Disconnect the session to make sure we don't run out of maximum concurrent connections
    If (!$KeepAlive) {
        If (Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" }) {
            $Null = Disconnect-ExchangeOnline -Confirm:$false
        }
    }

    # Return the new name of the alias(es)
    If ($ExistingDistributionGroup) {
        return $ExistingDistributionGroup | Select-Object Name, DisplayName, PrimarySmtpAddress | Sort-Object DisplayName
    }
    Else {
        return
    }
}

Function Get-UnusedMailAlias {
    param(
        [parameter(Mandatory = $false, HelpMessage = "Name prefix that is used to identify the Mail Aliases")]
        [ValidateNotNullOrEmpty()]
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '$GroupNamePrefix', Justification = 'False positive')]
        [string]$GroupNamePrefix,

        [parameter(Mandatory = $false, HelpMessage = "Keep the Exchange Online session alive for further use")]
        [switch]$KeepAlive
    )

    ## Login to Office 365
    If (!(Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" })) {
        Connect-ExchangeOnline -ShowBanner:$false
    }

    # Check if domain name already exists in Distribution Group
    $ExistingDistributionGroup = Get-DistributionGroup | Where-Object `
    { $_.Name -like "$GroupNamePrefix*" -and $_.DisplayName -like "*_CLAIMABLE" }

    # Disconnect the session to make sure we don't run out of maximum concurrent connections
    If (!$KeepAlive) {
        If (Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" }) {
            $Null = Disconnect-ExchangeOnline -Confirm:$false
        }
    }

    # Return the names of the unused alias(es)
    If ($ExistingDistributionGroup) {
        return $ExistingDistributionGroup | Select-Object Name, DisplayName, PrimarySmtpAddress
    }
    Else {
        return
    }
}

Function Set-MailAliasToArchived {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '*', Scope = 'Function', Target = '*', Justification = 'Does not change system state')]

    param(
        [parameter(Mandatory = $true, HelpMessage = "Specify the domain name of the website")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainName,

        [parameter(Mandatory = $false, HelpMessage = "Keep the Exchange Online session alive for further use")]
        [switch]$KeepAlive
    )

    ## Login to Office 365
    If (!(Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" })) {
        Connect-ExchangeOnline -ShowBanner:$false
    }

    # Check if domain name already exists in Distribution Group
    $ExistingDistributionGroup = Get-DistributionGroup | Where-Object `
    { $_.DisplayName -like "$DomainName - *" }

    if (!$ExistingDistributionGroup) {
        throw "Cannot find an existing Distribution Group with domain name '$($DomainName)'"
    }

    else {
        Write-Output "Changing displayName from '$($ExistingDistributionGroup.DisplayName)' to '(Archived) $($ExistingDistributionGroup.DisplayName)'"
        Set-DistributionGroup -Identity $ExistingDistributionGroup.Identity -DisplayName "(Archived) $($ExistingDistributionGroup.DisplayName)"

        Write-Output "Removing members from distribution group"
        $ExistingDistributionGroup | Remove-DistributionGroupMember -Confirm:$false

        # Return the new name of the alias
        Write-Output "Done, new result:"
    }

    $output = Get-DistributionGroup -Identity $ExistingDistributionGroup.Identity | Select-Object Name, DisplayName, PrimarySmtpAddress

    # Disconnect the session to make sure we don't run out of maximum concurrent connections
    If (!$KeepAlive) {
        If (Get-PSSession | Where-Object { $_.ComputerName -eq "outlook.office365.com" -and $_.State -eq "Opened" }) {
            $Null = Disconnect-ExchangeOnline -Confirm:$false
        }
    }

    return $output
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA9PcwPG08FWXpY
# XiTK3A2HqihnmIRGRkb7BpFiGL+wJaCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCCN48yfuOEzCNwDsiPLwhpz8OiH4fiv4Q7C0qboe3cqLDANBgkqhkiG
# 9w0BAQEFAASCAgASJoyLcX1/c3pVY/V0+sqCvIm7Ahwpd0jUYFlZpWJQekM6nYrJ
# FG66WYcfrTzAlZ8wAKcfmoh5jRU1xowu1bHHa95PunV8uinEsMs0GOvFfGjcLm6H
# qpuLmdzGRaQn/OibnZxM+dg9yLOeYgbP0cyJEWO1kiLpkpKMicMuBmm7XbMGL3y0
# KE+jfOw2mPHFGGYuiMS1d8eyr63FGHYQ9qtjMeHH2bdlu62yknqIGNxJxfjfLnBI
# LaVpEM/o7mRe1E95M/v2hEBwkJCcJyoOPZtFHL1T+ZsVwm+8SXA8dC6Y/tQ8t7V8
# fu4pU+Djxi5TjzGq7rna1UdQLrdC1l+BS1o74STLuLgE3MnB09LFsoU8GH1u+QFC
# rMtQTZR5bquaWdLQVsWNB15uLU7OZIvJPjwkrXv2yLHohBaTJvTDyPjchG6EBcQv
# enMr5hztAPHeyNbzAYGbu87Pui4/50S2rMa0O2GCVPp+uTYPj7JkHFgfEqg9NIba
# V85thkZvklROiO9QF/anG7nMkWU2oFmbq8tMXq7B/76PFTFouj9GbiLZEB5i5qEE
# +hvzdUnWdkVCcv6Q/jfnkmn2fodt8SDp4AOFOJxP2KITRH7jpJaiqrL74elkVcSS
# e128xfqIk1lQjt5fBjdU0DktOzmRx6nWHOXcXGTA0Fq/ZRHplWuZz7Y+1KGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA2MDExMDA2NDdaMC8GCSqGSIb3DQEJBDEi
# BCCSmj65TmB71uZQZ9+vifg9kpGXHkcFfGx4zWgvq94TUzANBgkqhkiG9w0BAQEF
# AASCAgBl2c2+YSrgXIvDaQZdOOvMxbQzolOZOEOUvVpyk6GXt4ATWJDNgHubLSpL
# fnbVuIR2m05MCwokDYvu8t50AReXXy3IdsuXZi9g7enGpeiIoH8kpoS86uX2o4TL
# QbLK1zbWSaIEwCAZm/bjhO3MvWGPz2un1ZXlWRwyKwOBa4D/e7GmrqUoxXPKNeuG
# fEGj2J1e3L+p6aDxNCtpcjSz1GvrxBGg2/itv2EKJiiA8hYIvF8nvVU2qig5lH/A
# +0ztj3alkpjGHaEdxzg9xpjLWk0QoWtBvIAhmLwXJ2QnJ11Kbhq+Ax/+quziZfrQ
# XV8UztdEzViqSxakTVYSkoI0NvmzM7EhIPiPfydniY/oxUjWZvCl+kz8SnqIMgK0
# 3NXebPYDn5+B2+ML5DM0ZsfwuhRJjCMhm9W3Nmk9/FM57xbVuRG+MiBnA/QHiSh3
# Fm7MYQ3m7jMvKW/QwqXFKzf529s6ApHIeer+20cw/0fhFEt0lhk3sVA0WWmCTs+X
# aCpdCV1vtG3l/aHRJtp0KZP2JHaKIc/Xy9B2gXjaISYh9EhxDLNsH5GEVq0wfPbt
# 9yUNbMZAQC8T7P5fjB7I7dvGUXnj0y8FVUmalhe+VEZjxwd9RNlnvzrcWHnluGsK
# vWYvT4znTB5+Dptz8xr/RF6uEhP5Y+OUlQFg+fbA7qrHge5rfA==
# SIG # End signature block
