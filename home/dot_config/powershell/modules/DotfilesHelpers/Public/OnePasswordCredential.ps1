# Read deployment credentials out of 1Password.
#
# Secret *references* (op://Vault/Item/field) are hardcoded here: they are
# useless without authenticating to 1Password, so pinning them means a new
# machine needs no configuration at all.
#
# Every credential is verified before a value is read - op installed,
# 1Password unlocked, item present, both fields present - so a missing
# entry fails immediately with a message naming what to create, rather
# than surfacing as an empty secret partway through a bulk rollout.
#
# Part of the GitHub repository configuration tooling; see
# GitHubRepoConfig.ps1 for the public commands and docs/github-repo-config.md
# for the user-facing guide.

# Where the credentials live in 1Password. These are secret *references*, not
# secrets: they are useless without authenticating to 1Password, so they are
# hardcoded here rather than configured per machine. Edit these to move an item;
# the matching environment variables below override them for a one-off.
#
#   Vault    Private
#   Item     GitHub Automation App     (API Credential)
#   Fields   app-id, private-key
#
#   Vault    Private
#   Item     Cloudflare Pages Deploy   (API Credential)
#   Fields   account-id, api-token
$script:OnePasswordReferences = @{
    GitHubAppId         = 'op://Private/GitHub Automation App/app-id'
    GitHubPrivateKey    = 'op://Private/GitHub Automation App/private-key'
    CloudflareAccountId = 'op://Private/Cloudflare Pages Deploy/account-id'
    CloudflareApiToken  = 'op://Private/Cloudflare Pages Deploy/api-token'
}

function Invoke-OnePasswordCli {
    <#
    .SYNOPSIS
        Invoke the `op` CLI and return its stdout.
    .DESCRIPTION
        Wraps every `op` invocation this module makes, so tests can mock it
        without 1Password being installed or unlocked.
    .PARAMETER Arguments
        Argument array passed verbatim to `op`.
    .PARAMETER AllowFailure
        Return $null on a non-zero exit code instead of throwing.
    .PARAMETER ErrorContext
        Human-readable description of the operation, used in the error message.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [switch]$AllowFailure,

        [Parameter(Mandatory = $false)]
        [string]$ErrorContext
    )

    if ([string]::IsNullOrWhiteSpace($ErrorContext)) {
        $ErrorContext = "op $($Arguments -join ' ')"
    }

    $output = & op @Arguments 2>&1

    if ($LASTEXITCODE -ne 0) {
        if ($AllowFailure) {
            Write-Verbose "$ErrorContext failed (exit $LASTEXITCODE)."
            return $null
        }
        throw "$ErrorContext failed (exit $LASTEXITCODE): $output"
    }

    return ($output | Out-String).Trim()
}

function ConvertFrom-OnePasswordReference {
    <#
    .SYNOPSIS
        Split an `op://Vault/Item/field` secret reference into its parts.
    .DESCRIPTION
        Parsing the reference up front lets the pre-flight checks name the exact
        vault, item and field that are missing, rather than surfacing op's
        generic "isn't an item" error.
    .PARAMETER Reference
        Secret reference in `op://Vault/Item/field` form.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference
    )

    if ($Reference -notmatch '^op://([^/]+)/([^/]+)/(.+)$') {
        throw "'$Reference' is not a valid 1Password secret reference. Expected the form 'op://Vault/Item/field'."
    }

    return [PSCustomObject]@{
        Vault     = $Matches[1]
        Item      = $Matches[2]
        Field     = $Matches[3]
        Reference = $Reference
    }
}

function Test-OnePasswordSession {
    <#
    .SYNOPSIS
        Throw unless the 1Password CLI is installed and unlocked.
    .DESCRIPTION
        Separating "not installed" from "not signed in" means the error names
        which of the two to fix, instead of failing later with an opaque op
        error partway through a bulk rollout.
    #>
    [CmdletBinding()]
    param()

    if (-not (Get-Command op -ErrorAction SilentlyContinue)) {
        throw "The 1Password CLI (op) was not found on PATH. Install it from https://developer.1password.com/docs/cli/ first."
    }

    $whoami = Invoke-OnePasswordCli -Arguments @('whoami') -AllowFailure -ErrorContext 'op whoami'
    if ($null -eq $whoami) {
        throw "The 1Password CLI is not signed in. Unlock the 1Password app with the CLI integration enabled (Settings -> Developer -> 'Integrate with 1Password CLI'), or run 'op signin'."
    }
}

function Test-OnePasswordReference {
    <#
    .SYNOPSIS
        Verify that the item and field behind a secret reference exist.
    .DESCRIPTION
        Checks the vault, item and field before any value is read, so a missing
        1Password entry produces an actionable message naming exactly what to
        create instead of an empty value surfacing later in the rollout.
    .PARAMETER Reference
        Secret reference in `op://Vault/Item/field` form.
    .PARAMETER Purpose
        What the field holds, used in the error message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reference,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $parsed = ConvertFrom-OnePasswordReference -Reference $Reference

    $json = Invoke-OnePasswordCli -Arguments @('item', 'get', $parsed.Item, '--vault', $parsed.Vault, '--format', 'json') `
        -AllowFailure -ErrorContext "op item get '$($parsed.Item)'"

    if ($null -eq $json) {
        $create = "op item create --category 'API Credential' --vault '$($parsed.Vault)' --title '$($parsed.Item)' 'app-id[text]=YOUR_APP_ID' 'private-key[password]=PEM_CONTENTS'"
        throw "1Password item '$($parsed.Item)' was not found in vault '$($parsed.Vault)' (needed for the $Purpose). Create it in the 1Password app as an API Credential with 'app-id' and 'private-key' fields, or run: $create"
    }

    try {
        $item = $json | ConvertFrom-Json
    }
    catch {
        throw "Could not parse the 1Password item '$($parsed.Item)' as JSON: $_"
    }

    $names = @($item.fields | ForEach-Object { $_.label }) + @($item.fields | ForEach-Object { $_.id })
    $found = @($names | Where-Object { $_ -and ([string]$_).ToLowerInvariant() -eq $parsed.Field.ToLowerInvariant() }).Count -gt 0

    if (-not $found) {
        $available = (@($item.fields | ForEach-Object { $_.label } | Where-Object { $_ }) | Sort-Object -Unique) -join ', '
        throw "1Password item '$($parsed.Item)' in vault '$($parsed.Vault)' has no field named '$($parsed.Field)' (needed for the $Purpose). Fields on that item: $available"
    }
}

function ConvertFrom-DotfilesSecureString {
    <#
    .SYNOPSIS
        Convert a SecureString to plain text (Windows PowerShell 5.1 safe).
    .DESCRIPTION
        ConvertFrom-SecureString -AsPlainText only exists on PowerShell 7+, and
        this module targets 5.1. The unmanaged buffer is always freed in the
        finally block so the plaintext is not left on the heap.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = 'Deliberate, scoped conversion required to hand the key to the gh CLI on stdin.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Get-GitHubAppCredential {
    <#
    .SYNOPSIS
        Read a GitHub App ID and private key from 1Password.

    .DESCRIPTION
        Resolves two 1Password secret references with `op read` and returns
        them as an object. The private key is returned as a SecureString so it
        is not left as a plain string in the session; the App ID is returned as
        plain text because it is a non-secret identifier.

        Before reading anything, the 1Password CLI is checked for being
        installed and unlocked, and both the item and the fields are verified to
        exist. A missing entry therefore fails immediately with a message naming
        exactly what to create, rather than surfacing as an empty value partway
        through a rollout.

        Expected 1Password entry (create it once):

            Vault    Private
            Item     GitHub Automation App   (category: API Credential)
            Fields   app-id        the numeric App ID from the App settings page
                     private-key   the full PEM, including the BEGIN/END lines

        Override the location with -AppIdReference / -PrivateKeyReference, or
        with the OP_GITHUB_APP_ID_REF / OP_GITHUB_APP_KEY_REF environment
        variables. Secret references are non-secret identifiers, useless without
        authenticating to 1Password.

    .PARAMETER AppIdReference
        1Password secret reference for the App ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_GITHUB_APP_ID_REF, then to
        'op://Private/GitHub Automation App/app-id'.

    .PARAMETER PrivateKeyReference
        1Password secret reference for the PEM-encoded private key. Defaults to
        $env:OP_GITHUB_APP_KEY_REF, then to
        'op://Private/GitHub Automation App/private-key'.

    .EXAMPLE
        Get-GitHubAppCredential

        Read the credential from the default 1Password location.

    .EXAMPLE
        $cred = Get-GitHubAppCredential
        Get-GitHubRepoConfig -All -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred

        Roll the App credential out to every repository that is missing it.

    .EXAMPLE
        Get-GitHubAppCredential -AppIdReference 'op://Work/Automation App/app-id' -PrivateKeyReference 'op://Work/Automation App/private-key'

        Read the credential from a different vault or item.

    .OUTPUTS
        PSCustomObject with AppId (string) and PrivateKey (SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the PEM as plain text; converting it to a SecureString immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AppIdReference,

        [Parameter(Mandatory = $false)]
        [string]$PrivateKeyReference
    )

    if ([string]::IsNullOrWhiteSpace($AppIdReference)) {
        $AppIdReference = $env:OP_GITHUB_APP_ID_REF
    }
    if ([string]::IsNullOrWhiteSpace($AppIdReference)) {
        $AppIdReference = $script:OnePasswordReferences.GitHubAppId
    }

    if ([string]::IsNullOrWhiteSpace($PrivateKeyReference)) {
        $PrivateKeyReference = $env:OP_GITHUB_APP_KEY_REF
    }
    if ([string]::IsNullOrWhiteSpace($PrivateKeyReference)) {
        $PrivateKeyReference = $script:OnePasswordReferences.GitHubPrivateKey
    }

    Test-OnePasswordSession

    Write-Verbose "Verifying $AppIdReference"
    Test-OnePasswordReference -Reference $AppIdReference -Purpose 'GitHub App ID'

    Write-Verbose "Verifying $PrivateKeyReference"
    Test-OnePasswordReference -Reference $PrivateKeyReference -Purpose 'GitHub App private key'

    Write-Verbose "Reading App ID from $AppIdReference"
    $appId = Invoke-OnePasswordCli -Arguments @('read', $AppIdReference) -ErrorContext "op read '$AppIdReference'"
    if ([string]::IsNullOrWhiteSpace($appId)) {
        throw "The field at '$AppIdReference' is empty. Set it to the numeric App ID shown on the GitHub App's settings page."
    }
    if ($appId -notmatch '^\d+$') {
        throw "The value at '$AppIdReference' is not a numeric GitHub App ID. Use the 'App ID' from the App's settings page, not the client ID or slug."
    }

    Write-Verbose "Reading private key from $PrivateKeyReference"
    $privateKey = Invoke-OnePasswordCli -Arguments @('read', $PrivateKeyReference) -ErrorContext "op read '$PrivateKeyReference'"
    if ([string]::IsNullOrWhiteSpace($privateKey)) {
        throw "The field at '$PrivateKeyReference' is empty. Paste the full contents of the App's .private-key.pem file into it."
    }
    if ($privateKey -notmatch 'BEGIN [A-Z ]*PRIVATE KEY') {
        throw "The value at '$PrivateKeyReference' does not look like a PEM-encoded private key. It must include the '-----BEGIN ... PRIVATE KEY-----' header."
    }

    $secure = ConvertTo-SecureString -String $privateKey -AsPlainText -Force
    $privateKey = $null

    return [PSCustomObject]@{
        PSTypeName = 'Dotfiles.GitHubAppCredential'
        AppId      = $appId
        PrivateKey = $secure
    }
}

function Get-CloudflareCredential {
    <#
    .SYNOPSIS
        Read a Cloudflare account ID and API token from 1Password.

    .DESCRIPTION
        Both values are secrets used by the central reusable Pages workflow to
        deploy to Cloudflare Pages. They are returned as SecureStrings so they
        are not left as plain strings in the session.

        Note this is the Cloudflare **account** ID, not a project ID: the
        project name is a workflow input (`cloudflare-project-name`, defaulting
        to the repository name), not a secret.

        As with Get-GitHubAppCredential, everything is verified before a value
        is read, so a missing entry fails immediately with a message naming what
        to create rather than surfacing as an empty secret partway through a
        rollout.

        Expected 1Password entry (create it once):

            Vault    Private
            Item     Cloudflare Pages Deploy   (category: API Credential)
            Fields   account-id   the Account ID from the Cloudflare dashboard
                     api-token    a token with the Cloudflare Pages:Edit scope

    .PARAMETER AccountIdReference
        1Password secret reference for the account ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_CLOUDFLARE_ACCOUNT_REF, then to
        'op://Private/Cloudflare Pages Deploy/account-id'.

    .PARAMETER ApiTokenReference
        1Password secret reference for the API token. Defaults to
        $env:OP_CLOUDFLARE_TOKEN_REF, then to
        'op://Private/Cloudflare Pages Deploy/api-token'.

    .EXAMPLE
        Get-CloudflareCredential

        Read the credential from the default 1Password location.

    .EXAMPLE
        $cf = Get-CloudflareCredential
        Get-GitHubRepoConfig -All -Check CloudflareCredential | Set-GitHubRepoConfig -CloudflareCredential $cf

        Roll the Cloudflare credential out to every repository that deploys
        through the central Pages workflow and is missing it.

    .OUTPUTS
        PSCustomObject with AccountId and ApiToken (both SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the values as plain text; converting them to SecureStrings immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false)]
        [string]$AccountIdReference,

        [Parameter(Mandatory = $false)]
        [string]$ApiTokenReference
    )

    if ([string]::IsNullOrWhiteSpace($AccountIdReference)) { $AccountIdReference = $env:OP_CLOUDFLARE_ACCOUNT_REF }
    if ([string]::IsNullOrWhiteSpace($AccountIdReference)) { $AccountIdReference = $script:OnePasswordReferences.CloudflareAccountId }

    if ([string]::IsNullOrWhiteSpace($ApiTokenReference)) { $ApiTokenReference = $env:OP_CLOUDFLARE_TOKEN_REF }
    if ([string]::IsNullOrWhiteSpace($ApiTokenReference)) { $ApiTokenReference = $script:OnePasswordReferences.CloudflareApiToken }

    Test-OnePasswordSession

    Write-Verbose "Verifying $AccountIdReference"
    Test-OnePasswordReference -Reference $AccountIdReference -Purpose 'Cloudflare account ID'

    Write-Verbose "Verifying $ApiTokenReference"
    Test-OnePasswordReference -Reference $ApiTokenReference -Purpose 'Cloudflare API token'

    $accountId = Invoke-OnePasswordCli -Arguments @('read', $AccountIdReference) -ErrorContext "op read '$AccountIdReference'"
    if ([string]::IsNullOrWhiteSpace($accountId)) {
        throw "The field at '$AccountIdReference' is empty. Set it to the Account ID shown in the Cloudflare dashboard."
    }
    # Cloudflare account IDs are 32-character hex strings; catching a pasted
    # project name or zone ID here beats a 403 inside a deploy job.
    if ($accountId -notmatch '^[0-9a-fA-F]{32}$') {
        throw "The value at '$AccountIdReference' is not a Cloudflare account ID (expected 32 hex characters). Use the Account ID from the dashboard sidebar, not a project or zone ID."
    }

    $apiToken = Invoke-OnePasswordCli -Arguments @('read', $ApiTokenReference) -ErrorContext "op read '$ApiTokenReference'"
    if ([string]::IsNullOrWhiteSpace($apiToken)) {
        throw "The field at '$ApiTokenReference' is empty. Create a token with the 'Cloudflare Pages:Edit' permission and paste it in."
    }

    $result = [PSCustomObject]@{
        PSTypeName = 'Dotfiles.CloudflareCredential'
        AccountId  = (ConvertTo-SecureString -String $accountId -AsPlainText -Force)
        ApiToken   = (ConvertTo-SecureString -String $apiToken -AsPlainText -Force)
    }
    $accountId = $null
    $apiToken = $null

    return $result
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDKH2KIvsWR9pbr
# s6VCy7JRY9fvLJdrFgFjfB0r0FtvhKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCDtlhaKnOW3Y8Vkml9hXceCG8s8AjDeCS/hvDf+qMz47TANBgkqhkiG
# 9w0BAQEFAASCAgB0d2N7VuddgTEIg73jJ7ljFIc/0rcjB6YSInPr6EWBixL8tqUI
# oLIddHB7PKR57rPVzGhOSM1fvkpXBExjmP7aRuVtVFwdcNav0yfucAMNWZj/Inh9
# PkbKqT4GdwdeSfakuPvpwSLetGUi6/t2ifSGQGKV+5oGuDjyjN2t0HTG9RRZMs+v
# ODZr4TOs+pp+qCTBoc2AKLQFV1fc9/fgaEsooEKfpcz9FlvzCgqWQe4u8BINPDpy
# B4sNhmlm7gIgaik9xH3wAtXlUBpb6XdXRnGyLSa/yrrHD/biWpqwtFlYJOmFQj6m
# O6gfhEqpb3MXD98DjfsCRHEfViXEnVP2xS6soJwSPjwDqlTJmZFkcaYR1V4F9tgm
# XgkGXZebD67CA4jSvHBR0GI+3Eruf/U4IC/Uh2SWU+X/qUmq6HBoMDphLFc51bFO
# 6kxCcZnBa0JDL8+K6wVAnTT7d7NHRO0bYv+XhUH1PFXVqSSc9rl1HI46XCnoINeH
# NJtH+TkEffmwXaSpcMzyOVs6TqdN+fU6emdeZC0A7dP0LJUbiCnQZpwRE7CDzmyA
# rI6Lwb6FIXU9+5tQmtCA4756ZUYWCM8gy54hQSZyL6cDjG7YcKwUV1MCdsASXWnA
# Gnr6mJFYEHi13oLhiO2uraXDlEoACM2CEwkUjwV7ZxyIIngwnO1DQR+SsqGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA3MjkwODE4MDZaMC8GCSqGSIb3DQEJBDEi
# BCA0joZiFmHkO6eNAQv/SMPuiLOV1Rq1Fv2FR0yI6d7D/DANBgkqhkiG9w0BAQEF
# AASCAgC9NcLl6h3KxFIBx8hZn2XvvtkLaUflZ33/+1o1mYKh7Ym+7EZshRTWwVBk
# RYSHx1wS0G/7zWcfWyz2Uz4N03ZVD6PJgAu0rXVPfo+hVFdXwxzoGuGNH9n5tNTr
# l8ZX0Y2AF08D5Bb5jgRSwbVlCjJEKRiqR9XHzUbb1gWR1xNT8OdlmecRCN/xh+Pj
# Tj+/YH94Y6kFZmE/dFI046pjxu2PJdO4Laq5BNTLvuTiOsWKubomSjYpf2bKt/rL
# cJ/nx1xbtZHaRoM8Hk1h4aOGf1iRVfWifR0kTbtF+PvpDl5uVvv0felaTK4qJyvq
# jT7HlhodTTZE0G62f79ZUAdTfg7PYpIMPggCq5oaKV5tBRNTjeWkV5JZJ9obfxeT
# n3d/5oRxnT7delmFl9laUKV6WNuJ17ZRzcOpUw7sTkZ3no92T0H24yYYtb7H26D6
# Ux+2JCnr1hUfDV1t26dKcn/l8FDzQZgIo9EOINuAU6TdgzOCGXHXvqDmt5LqvzBN
# 1Rw7DZujzA1hB9joLz2qqdMl3pC/4nLFv5Yq/mOibHPWMZKU+nHNt4fbUd8a7h12
# pus7kochSidxAnh+E6P9NqtBcmRObVhkfOw0Ebmt6gWcxVDZe3p/+4UOg/NH6je4
# UhPSXnK0EHLRTZfOxQe//39fypzvWAdWHNXKaBUADTroLaA4Mg==
# SIG # End signature block
