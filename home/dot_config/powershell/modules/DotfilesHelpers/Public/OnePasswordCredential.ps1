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
