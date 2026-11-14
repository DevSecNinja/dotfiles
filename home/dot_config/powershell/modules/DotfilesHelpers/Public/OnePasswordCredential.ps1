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
# The GitHub App key can alternatively be read from the downloaded
# `.private-key.pem` file (Get-GitHubAppCredential -PrivateKeyPath), for
# machines without 1Password or for a one-off key rotation.
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

function Test-GitHubAppPrivateKeyDer {
    <#
    .SYNOPSIS
        Structurally check that DER bytes encode an RSA private key.
    .DESCRIPTION
        Fallback for Windows PowerShell 5.1, whose .NET Framework cannot import
        PEM keys. Verifies that the outer SEQUENCE spans the whole payload and
        starts with version INTEGER 0, then that a PKCS#1 key continues with the
        modulus INTEGER and a PKCS#8 key names the rsaEncryption algorithm. Not
        a full parse, but it rejects empty bodies, base64-encoded text and
        non-RSA keys.
    .PARAMETER Der
        The decoded PEM body.
    .PARAMETER Label
        The PEM label: 'RSA PRIVATE KEY' (PKCS#1) or 'PRIVATE KEY' (PKCS#8).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Der,

        [Parameter(Mandatory = $true)]
        [ValidateSet('RSA PRIVATE KEY', 'PRIVATE KEY')]
        [string]$Label
    )

    if ($Der.Length -lt 16 -or $Der[0] -ne 0x30) { return $false }

    $offset = 2
    $length = [long]$Der[1]
    if ($length -ge 0x80) {
        $count = $length - 0x80
        if ($count -lt 1 -or $count -gt 4) { return $false }
        $length = 0
        for ($i = 0; $i -lt $count; $i++) { $length = ($length * 256) + $Der[2 + $i] }
        $offset = 2 + $count
    }
    if ($offset + $length -ne $Der.Length) { return $false }

    if ($Der[$offset] -ne 0x02 -or $Der[$offset + 1] -ne 0x01 -or $Der[$offset + 2] -ne 0x00) { return $false }
    $next = $offset + 3

    if ($Label -eq 'RSA PRIVATE KEY') {
        return ($Der[$next] -eq 0x02)
    }

    # AlgorithmIdentifier SEQUENCE { OID 1.2.840.113549.1.1.1 (rsaEncryption), NULL }
    $rsaOid = [byte[]](0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01)
    if ($Der[$next] -ne 0x30 -or $Der.Length -lt ($next + 2 + $rsaOid.Length)) { return $false }
    for ($i = 0; $i -lt $rsaOid.Length; $i++) {
        if ($Der[$next + 2 + $i] -ne $rsaOid[$i]) { return $false }
    }
    return $true
}

function Test-GitHubAppPrivateKeyBlock {
    <#
    .SYNOPSIS
        Is this PEM block a usable RSA private key?
    .DESCRIPTION
        A block can carry the right header and still hold garbage - an empty
        body or base64-encoded text - which would roll out as an unusable
        secret. On PowerShell 7 the key is imported with .NET, which fully
        validates it; Windows PowerShell 5.1 falls back to a structural DER
        check. Returns a boolean and never surfaces the key or the parser's
        message.
    .PARAMETER Block
        The PEM block, BEGIN and END lines included.
    .PARAMETER Label
        The PEM label: 'RSA PRIVATE KEY' or 'PRIVATE KEY'.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)][string]$Block,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $der = $null
    try {
        if ($null -ne $rsa.PSObject.Methods['ImportFromPem']) {
            $rsa.ImportFromPem($Block)
            return $true
        }

        $body = ($Block -replace '-----(BEGIN|END) [A-Z ]+-----', '') -replace '\s', ''
        $der = [System.Convert]::FromBase64String($body)
        return (Test-GitHubAppPrivateKeyDer -Der $der -Label $Label)
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $der) { [Array]::Clear($der, 0, $der.Length) }
        $rsa.Dispose()
    }
}

function Read-GitHubAppPrivateKeyFile {
    <#
    .SYNOPSIS
        Read and validate a GitHub App private key from a PEM file.
    .DESCRIPTION
        GitHub Apps authenticate with an RSA private key, which the App's
        settings page issues as `<app>.<date>.private-key.pem`. Both the PKCS#1
        (`BEGIN RSA PRIVATE KEY`) and PKCS#8 (`BEGIN PRIVATE KEY`) encodings
        are accepted; certificates, encrypted keys, empty files and anything
        else are rejected before a value is returned, and the block itself must
        parse as an RSA key (Test-GitHubAppPrivateKeyBlock).

        Error messages name the path and the problem but never echo the file
        contents, so a wrong file cannot leak a key into the console, a
        transcript or a log. Only the private-key block itself is kept.
    .PARAMETER Path
        Path to the PEM file. The extension does not matter.
    .OUTPUTS
        System.Security.SecureString
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The PEM is read from disk as plain text; converting it to a SecureString immediately is the hardening step, not a weakness.')]
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $howToGetOne = "Generate one on the GitHub App's settings page (General -> Private keys); the download is named like '<app>.<date>.private-key.pem'."

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "GitHub App private key file '$Path' was not found. $howToGetOne"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).ProviderPath
    $text = $null
    $keys = $null

    try {
        try {
            $text = [System.IO.File]::ReadAllText($resolved)
        }
        catch {
            throw "GitHub App private key file '$resolved' could not be read: $($_.Exception.Message)"
        }

        if ([string]::IsNullOrWhiteSpace($text)) {
            throw "GitHub App private key file '$resolved' is empty. $howToGetOne"
        }

        # [regex]::IsMatch rather than -match, so $Matches never holds any of
        # the file contents.
        if ([regex]::IsMatch($text, '-----BEGIN [A-Z0-9 ]*CERTIFICATE-----')) {
            throw "'$resolved' contains a certificate, not a private key. GitHub Apps authenticate with the App's private key ('-----BEGIN RSA PRIVATE KEY-----'). $howToGetOne"
        }

        if ([regex]::IsMatch($text, '-----BEGIN ENCRYPTED PRIVATE KEY-----|Proc-Type:\s*4,ENCRYPTED')) {
            throw "'$resolved' holds a passphrase-protected private key. GitHub Actions needs the key unencrypted, exactly as GitHub issued it."
        }

        $keys = [regex]::Matches($text, '-----BEGIN (RSA PRIVATE KEY|PRIVATE KEY)-----\s+[A-Za-z0-9+/=\s]+?-----END \1-----')
        if ($keys.Count -eq 0) {
            throw "'$resolved' does not contain a PEM private key. Expected a '-----BEGIN RSA PRIVATE KEY-----' or '-----BEGIN PRIVATE KEY-----' block. $howToGetOne"
        }
        if ($keys.Count -gt 1) {
            throw "'$resolved' contains $($keys.Count) private keys. Pass a file that holds exactly one."
        }

        $label = $keys[0].Groups[1].Value
        if (-not (Test-GitHubAppPrivateKeyBlock -Block $keys[0].Value -Label $label)) {
            throw "'$resolved' has a '-----BEGIN $label-----' block, but it does not hold a valid RSA private key. GitHub Apps sign with RSA keys. $howToGetOne"
        }

        return (ConvertTo-SecureString -String $keys[0].Value -AsPlainText -Force)
    }
    finally {
        $text = $null
        $keys = $null
    }
}

function Get-GitHubAppCredential {
    <#
    .SYNOPSIS
        Read a GitHub App ID and private key from 1Password or a PEM file.

    .DESCRIPTION
        By default, resolves two 1Password secret references with `op read`
        and returns them as an object. With -PrivateKeyPath, the key is read
        from a local PEM file instead and the App ID is taken from -AppId, so
        1Password is not needed at all.

        Either way the private key is returned as a SecureString so it is not
        left as a plain string in the session; the App ID is returned as plain
        text because it is a non-secret identifier. The key is never written to
        any output stream.

        When reading from 1Password, the CLI is first checked for being
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

        The PEM file passed to -PrivateKeyPath must hold exactly one unencrypted
        private key, in PKCS#1 ('-----BEGIN RSA PRIVATE KEY-----') or PKCS#8
        ('-----BEGIN PRIVATE KEY-----') form. A certificate, an encrypted key,
        an empty file or any other content is rejected with an explanation.

    .PARAMETER AppIdReference
        1Password secret reference for the App ID, in `op://Vault/Item/field`
        form. Defaults to $env:OP_GITHUB_APP_ID_REF, then to
        'op://Private/GitHub Automation App/app-id'.

    .PARAMETER PrivateKeyReference
        1Password secret reference for the PEM-encoded private key. Defaults to
        $env:OP_GITHUB_APP_KEY_REF, then to
        'op://Private/GitHub Automation App/private-key'.

    .PARAMETER AppId
        The numeric App ID from the App's settings page. Required with
        -PrivateKeyPath.

    .PARAMETER PrivateKeyPath
        Path to the App's private key file, such as the downloaded
        '<app>.<date>.private-key.pem'. Reads the key from disk instead of from
        1Password.

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

    .EXAMPLE
        $cred = Get-GitHubAppCredential -AppId 3563533 -PrivateKeyPath ~/Downloads/automation-app.2026-11-14.private-key.pem
        Get-GitHubRepoConfig -All -HasRelease -Check AppCredential | Set-GitHubRepoConfig -AppCredential $cred -WhatIf

        Read the key from the downloaded file and preview rolling it out to the
        repositories that publish releases.

    .OUTPUTS
        PSCustomObject with AppId (string) and PrivateKey (SecureString).
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Read-only; does not change system state.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The 1Password CLI returns the PEM as plain text; converting it to a SecureString immediately is the hardening step, not a weakness.')]
    [CmdletBinding(DefaultParameterSetName = 'OnePassword')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'OnePassword')]
        [string]$AppIdReference,

        [Parameter(Mandatory = $false, ParameterSetName = 'OnePassword')]
        [string]$PrivateKeyReference,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [string]$AppId,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [ValidateNotNullOrEmpty()]
        [string]$PrivateKeyPath
    )

    if ($PSCmdlet.ParameterSetName -eq 'File') {
        $AppId = $AppId.Trim()
        if ($AppId -notmatch '^\d+$') {
            throw "'$AppId' is not a numeric GitHub App ID. Use the 'App ID' from the App's settings page, not the client ID or slug."
        }

        Write-Verbose "Reading GitHub App private key from file '$PrivateKeyPath'"
        $secure = Read-GitHubAppPrivateKeyFile -Path $PrivateKeyPath
        Write-Verbose "Private key file validated for App ID $AppId"

        return [PSCustomObject]@{
            PSTypeName = 'Dotfiles.GitHubAppCredential'
            AppId      = $AppId
            PrivateKey = $secure
        }
    }

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
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBfZuZBZ8NH8a1a
# JsD/050E+56BLZ3qfuIU9vkjahT/KKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# oW2jNrbM1pD2T7m3XDCCBu0wggTVoAMCAQICEAhP3DNPfkVO28MPj/mSGDUwDQYJ
# KoZIhvcNAQELBQAwaTELMAkGA1UEBhMCVVMxFzAVBgNVBAoTDkRpZ2lDZXJ0LCBJ
# bmMuMUEwPwYDVQQDEzhEaWdpQ2VydCBUcnVzdGVkIEc0IFRpbWVTdGFtcGluZyBS
# U0E0MDk2IFNIQTI1NiAyMDI1IENBMTAeFw0yNjA4MDUwMDAwMDBaFw0zNzExMDQy
# MzU5NTlaMGMxCzAJBgNVBAYTAlVTMRcwFQYDVQQKEw5EaWdpQ2VydCwgSW5jLjE7
# MDkGA1UEAxMyRGlnaUNlcnQgU0hBMjU2IFJTQTQwOTYgVGltZXN0YW1wIFJlc3Bv
# bmRlciAyMDI2IDEwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC2e6by
# yf7NSvjUm0xls/04xjD4fAkOkbnGQi7+Wpx81iYxfzViaxSIctuH3KSl5YEYpMuF
# gGsA31N2D9ATMbfZdw5uaAhuWevQKhDdZIB4NnqcfpfpWQXJiQnDdAElETC+bhSE
# vNLGbA8DtwUpFMQ4yyYQSPqomT92osQAv6hBi47ATZS6JfVWe6XxhF4jJZ3iSAuf
# 2Cros1czRSmWRHqMv9AfGZvp8ygYElhudpQjtcPpwoOl6QrZJUyV3iINvN4cO05p
# rGV0fkjG426xDr2d3z9lcSIHkdvGPdGUrXdxfVbgOUVcp2/8ISEzwKPW++Wa+E2u
# jI91EZtukGWDJ/xZ27k3oHKEXBRGfRTqjOU+jE3ba/5++JSE/7oNHnjs5mekExYN
# 96LV/mxUbCKJb8pBNY4r3uD7hEmk/M81XhVgwDA7aMzYC3LZBg9WY5BMmbSay5ec
# mtJuXaB/0nKWmQmVZeqTVDgsmzHP5MQuhAJkiWNuC9MmCg9TZHXbJ2/yLVSov9p1
# 6UDTLtT0+aa1vN71fHeu1qMLlLNB3WOB/ADCxr3S/1hxI92Z6jKgEED/btwIvbfu
# XkNNhg8MtDg43c4tMZae9FvqMOt/9PvmAxF9TNIsIFB8G6yb36ZJZGUL8N/pL971
# DyLXcK6HM5PYnH5X+eVtczhCgHCVQCF6XDAlPQIDAQABo4IBlTCCAZEwDAYDVR0T
# AQH/BAIwADAdBgNVHQ4EFgQUFMljijAu1Er7bpTz5uNAfvXszeIwHwYDVR0jBBgw
# FoAU729TSunkBnx6yuKQVvYv1Ensy04wDgYDVR0PAQH/BAQDAgeAMBYGA1UdJQEB
# /wQMMAoGCCsGAQUFBwMIMIGVBggrBgEFBQcBAQSBiDCBhTAkBggrBgEFBQcwAYYY
# aHR0cDovL29jc3AuZGlnaWNlcnQuY29tMF0GCCsGAQUFBzAChlFodHRwOi8vY2Fj
# ZXJ0cy5kaWdpY2VydC5jb20vRGlnaUNlcnRUcnVzdGVkRzRUaW1lU3RhbXBpbmdS
# U0E0MDk2U0hBMjU2MjAyNUNBMS5jcnQwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDov
# L2NybDMuZGlnaWNlcnQuY29tL0RpZ2lDZXJ0VHJ1c3RlZEc0VGltZVN0YW1waW5n
# UlNBNDA5NlNIQTI1NjIwMjVDQTEuY3JsMCAGA1UdIAQZMBcwCAYGZ4EMAQQCMAsG
# CWCGSAGG/WwHATANBgkqhkiG9w0BAQsFAAOCAgEAjcU6YR6dUgrfmawJgH59KECx
# a9Ji8sEi2g10CBDaMiqsaxWyW5cwlT/6ZF5sFznazqVsoC85U9dqLOYqQwst+UQQ
# oNlDHgKRLa3xoc+OReFreFhnTXSG0Vrd2E2CZqUfm+5a+He1MJ/h+tNLuA+0Zzhn
# /Fo+FDYAHWZHx4R79ZsfRFYe9UiXpXBDf6DkUo183Y38NYmR/XfDYf7YZ+oR9t3f
# lbDwK+hgGMs0gNNp1w9Z2CyOyI5or/sSwomAuNQ0hWC9xoU4stD8aWsD7RkcmgVR
# s6vlIk3zPKQ+ylcheWkMlj+CoVRlFE55pv0ZWCaFt04lwP/rdGHE9qEVQZtyRE42
# ox7oNgC/r+Y4bSlZ3dw9K2x1xLtu6PkPKeLBFjzKigwfqm3Hm+k/+lnME8F5kPZT
# giy2HLEHklpryqs6QHnPXrRNeIzkAMyylnRN8P0wmirS0WkU+ywpEWFZ4QNg+9xS
# 43tTuW9x0eXh7NDc1P/sV+zWxHXKH8tFt1ncHdVzqrZaYPyYMLSn2TOXajveJW1L
# 3joiQSPsWRGxkbDDW15jERFE4LvjnGu2O9zD1nLJSMdlYZEikl4w2w+q4IN/R+TI
# e0H4ngCI1moJCTbevGH4punIxM1Uoi0nmX3ZK+XbRT01uowE5ViXWHng0RgsmrX/
# EdYUo80r3TfMlkD0/YMxggYTMIIGDwIBATA3MCMxITAfBgNVBAMMGEplYW4tUGF1
# bCB2YW4gUmF2ZW5zYmVyZwIQELbg9grCcadOf9RJU4Fg9DANBglghkgBZQMEAgEF
# AKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkGCSqGSIb3DQEJAzEMBgor
# BgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEEAYI3AgEVMC8GCSqGSIb3
# DQEJBDEiBCADXD2FuM4dI4g6KUROMSOGRsdGkeqeM9YgnCctGNh+SDANBgkqhkiG
# 9w0BAQEFAASCAgAxZcTK7LFREuiTH7M0gciwCI+euA7djFnOziSJWTer2/lkBaVq
# relOqCTCubSsfKsAVnFRw7EHsafTqfpA7hdpL4qSdpPDgGaS4JKzQdZUjcw6qiX/
# D57n8csZYlwfyDbWkTJBK6AgdAADK8KQZzpkBNjJKaAnG0rvuO8RsN7mEXCocwX+
# l+MazbiE+PFpTNRtvCn3mOKFA210jk46FNGYC0BymVJmDxyjKoPveoG51AI7mCk4
# Sb98RQOdNgiADuakLVX3Ttsq30PIGFnbPClW0iGz0WwdraHySpTsgPU5Df8pmE1F
# OyrEQj5gG15qIjBNJS0UkpKm88+VFgsB+Qj0hEVJVCfkDIrbGbPgJcv89X6tT5ZX
# tRJBpo5MQpzgOKFykcGk+6q516UZd7IsbpiNx7R4XaZ4lenWfGey6sZN3VLlW8pN
# BOkrxU5a/UlG2QqeLknKcm9sCCqq4CX2dw7LGfGGlDjBcSPQwUk/kxRAHjNetpp7
# AaxyGNf1OguM2qDyq6EWLne31QX1cqxtv1yspa5j0kV483nXPwIbaMniYr0Wgu2M
# sLpvcW4KrJS1Txh6nA9MeR4sEwkvJU+j5RFubAytVEQHIy2QKfVdQjWCFi/lWaPv
# JDdtE8oGHpQSkYSN6SksrPV6B6DdR7RCpBZOzWa4HMKebI4e1G/jSJ9juaGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAhP3DNPfkVO
# 28MPj/mSGDUwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjExMTQxMTU0MjNaMC8GCSqGSIb3DQEJBDEi
# BCCBGD8fvUJl8KrLTbLlUAhoesdcDqESC3vxd5+fUAppKTANBgkqhkiG9w0BAQEF
# AASCAgCpt3Z5VZvU4ykP6V6w/3s/yxCljmvYHmjJ2VasKpDc2Pa5ra6BhN0jSEr5
# T0UULFq+vJ91QMNrNNc2/JKgpE4kwn1GgYII++qejLrlOzcfiD5reUkSGl2bXQnU
# pYAQqqIuQIaqI/xdiEOuLX84Bdw9+BhISNQD+Tku0V7195nNMCdEEQjR9Bh+FFzG
# 0jOeL1NmMpVT1o9/xINKCGiCmgW0dPOWyLzrYLea3zSD2JKD86m3IhESQcrWrMOG
# +ChiDxVF9AkJo+yQHgdJRH97kW/vPdqCsIY2qKLc/N8+I2Zq9XkhBfhThv4/cRjG
# glTBRx47K2g/NiIP1rF4fEK84oIhB/Iz6dHGR+GqQy2LIhcxvBNk382l2fF5T4gW
# WDJXZ8L9sv06YNg8Sf+P1/2p1e/VJX+dUt+Wk4C6vqJl3uTlGJ73106BxpzBa8B/
# 4C/+OBPtPt2sZdcDFuYV606Cbl7E7X5Re0cVcSN09pTJgmZg43+XPvNb6BZ+FJGD
# IY3GtAPNow0YeGl8oIdfV4xo4b467yHg3dGu1pYhputbRNfqpzF07OJ/WcIjZK7i
# S76ymN22NSIR2nOszZm4dvNULkslsK6mtYazcvOpreZgumrfjYGwuWLPnJqbjrgr
# eA0bWV4gDOUhuNJo8JQrAk7orUFTcjX2/EmhQhPndMBRTXoZag==
# SIG # End signature block
