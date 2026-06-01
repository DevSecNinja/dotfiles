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
