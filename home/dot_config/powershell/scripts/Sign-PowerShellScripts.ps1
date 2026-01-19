#Requires -Version 7.0
<#
.SYNOPSIS
    Signs PowerShell scripts with a code signing certificate.

.DESCRIPTION
    This script imports a code signing certificate and signs PowerShell scripts (.ps1 files).
    It can import certificates from PFX files or base64-encoded strings, and supports
    filtering files to sign. It's designed to work both locally and in CI/CD environments.

.PARAMETER CertificatePath
    Path to a PFX certificate file to import.

.PARAMETER CertificateBase64
    Base64-encoded certificate string (alternative to CertificatePath).

.PARAMETER CertificatePassword
    Password to decrypt the certificate. Required for PFX imports.

.PARAMETER CertificateThumbprint
    Thumbprint of an already-installed certificate to use for signing.
    If not provided, will import from CertificatePath or CertificateBase64.

.PARAMETER Path
    Root path to search for PowerShell scripts. Defaults to current directory.

.PARAMETER Include
    File patterns to include (e.g., "*.ps1"). Defaults to "*.ps1".

.PARAMETER Exclude
    File patterns to exclude (e.g., "*.ps1.tmpl", "*.Tests.ps1").
    Defaults to excluding templates and test files.

.PARAMETER TimestampServer
    URL of the timestamp server to use. Defaults to DigiCert's server.

.PARAMETER SkipValidation
    Skip validation of the certificate before signing.

.PARAMETER Force
    Re-sign scripts even if they're already validly signed.

.PARAMETER TrustSelfSignedRoot
    For self-signed certificates, automatically add the certificate to the
    Trusted Root store. This is required for signing to succeed with self-signed
    certs. Uses certutil which works non-interactively (suitable for CI).

.EXAMPLE
    .\Sign-PowerShellScripts.ps1 -CertificatePath "cert.pfx" -CertificatePassword $securePass
    Imports certificate from PFX file and signs all .ps1 files in current directory.

.EXAMPLE
    .\Sign-PowerShellScripts.ps1 -CertificateThumbprint "ABC123..." -Path "C:\Scripts"
    Signs scripts using an already-installed certificate.

.EXAMPLE
    $env:CERT_BASE64 = "MIIKqQ..."
    $env:CERT_PASSWORD = "password"
    .\Sign-PowerShellScripts.ps1 -CertificateBase64 $env:CERT_BASE64 -CertificatePassword (ConvertTo-SecureString $env:CERT_PASSWORD -AsPlainText -Force)
    Imports certificate from base64 string (typical CI scenario).

.OUTPUTS
    Returns a hashtable with signing statistics:
    @{
        TotalScripts = [int]
        Signed = [int]
        AlreadySigned = [int]
        Failed = [int]
        Skipped = [int]
    }

.NOTES
    This script must be run on Windows with PowerShell 7.0 or later.
    Requires appropriate permissions to import certificates and sign files.
#>

[CmdletBinding(DefaultParameterSetName = 'FromThumbprint')]
param(
    [Parameter(ParameterSetName = 'FromFile', Mandatory = $true)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string]$CertificatePath,

    [Parameter(ParameterSetName = 'FromBase64', Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateBase64,

    [Parameter(ParameterSetName = 'FromFile', Mandatory = $true)]
    [Parameter(ParameterSetName = 'FromBase64', Mandatory = $true)]
    [ValidateNotNull()]
    [SecureString]$CertificatePassword,

    [Parameter(ParameterSetName = 'FromThumbprint', Mandatory = $true)]
    [ValidatePattern('^[A-F0-9]{40}$')]
    [string]$CertificateThumbprint,

    [Parameter()]
    [ValidateScript({ Test-Path $_ -PathType Container })]
    [string]$Path = $PWD,

    [Parameter()]
    [string[]]$Include = @("*.ps1"),

    [Parameter()]
    [string[]]$Exclude = @("*.ps1.tmpl", "*.Tests.ps1"),

    [Parameter()]
    [string]$TimestampServer = "http://timestamp.digicert.com",

    [Parameter()]
    [switch]$SkipValidation,

    [Parameter()]
    [switch]$Force,

    [Parameter()]
    [switch]$TrustSelfSignedRoot
)

#region Helper Functions

function Write-ScriptLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $color = switch ($Level) {
        'Success' { 'Green' }
        'Warning' { 'Yellow' }
        'Error' { 'Red' }
        default { 'White' }
    }

    $prefix = switch ($Level) {
        'Success' { '✓' }
        'Warning' { '⚠' }
        'Error' { '✗' }
        default { '→' }
    }

    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Import-SigningCertificate {
    <#
    .SYNOPSIS
        Imports a code signing certificate from various sources.

    .OUTPUTS
        Returns the certificate object or $null on failure.
    #>
    param(
        [Parameter(ParameterSetName = 'FromFile')]
        [string]$FilePath,

        [Parameter(ParameterSetName = 'FromBase64')]
        [string]$Base64String,

        [Parameter(ParameterSetName = 'FromFile', Mandatory = $true)]
        [Parameter(ParameterSetName = 'FromBase64', Mandatory = $true)]
        [SecureString]$Password
    )

    try {
        if ($PSCmdlet.ParameterSetName -eq 'FromBase64') {
            Write-ScriptLog "Decoding certificate from base64 string..."
            $certBytes = [Convert]::FromBase64String($Base64String)
            $tempCertPath = Join-Path $env:TEMP "cert-$(New-Guid).pfx"

            try {
                [IO.File]::WriteAllBytes($tempCertPath, $certBytes)
                $cert = Import-PfxCertificate -FilePath $tempCertPath `
                    -CertStoreLocation 'Cert:\CurrentUser\My' `
                    -Password $Password `
                    -Exportable
                Write-ScriptLog "Certificate imported successfully (Thumbprint: $($cert.Thumbprint))" -Level Success
                return $cert
            }
            finally {
                if (Test-Path $tempCertPath) {
                    Remove-Item $tempCertPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        elseif ($PSCmdlet.ParameterSetName -eq 'FromFile') {
            Write-ScriptLog "Importing certificate from file: $FilePath..."
            $cert = Import-PfxCertificate -FilePath $FilePath `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -Password $Password `
                -Exportable
            Write-ScriptLog "Certificate imported successfully (Thumbprint: $($cert.Thumbprint))" -Level Success
            return $cert
        }
    }
    catch {
        Write-ScriptLog "Failed to import certificate: $_" -Level Error
        return $null
    }
}

function Test-CodeSigningCertificate {
    <#
    .SYNOPSIS
        Validates that a certificate is suitable for code signing.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $issues = @()

    # Check if certificate has code signing EKU
    $codeSigningOid = "1.3.6.1.5.5.7.3.3"
    $hasCodeSigningEku = $Certificate.Extensions |
        Where-Object { $_.Oid.Value -eq "2.5.29.37" } |
        ForEach-Object {
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$_
            $eku.EnhancedKeyUsages.Value -contains $codeSigningOid
        }

    if (-not $hasCodeSigningEku) {
        $issues += "Certificate does not have Code Signing Enhanced Key Usage"
    }

    # Check if certificate is expired
    if ($Certificate.NotAfter -lt (Get-Date)) {
        $issues += "Certificate has expired (NotAfter: $($Certificate.NotAfter))"
    }

    # Check if certificate is not yet valid
    if ($Certificate.NotBefore -gt (Get-Date)) {
        $issues += "Certificate is not yet valid (NotBefore: $($Certificate.NotBefore))"
    }

    # Check if certificate has a private key
    if (-not $Certificate.HasPrivateKey) {
        $issues += "Certificate does not have a private key"
    }

    return @{
        IsValid = ($issues.Count -eq 0)
        Issues = $issues
    }
}

function Test-CertificateInStore {
    <#
    .SYNOPSIS
        Checks if a certificate exists in a specific certificate store.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Thumbprint,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Root', 'TrustedPublisher', 'My', 'CA')]
        [string]$StoreName,

        [Parameter()]
        [ValidateSet('CurrentUser', 'LocalMachine')]
        [string]$StoreLocation = 'CurrentUser'
    )

    try {
        $storePath = "Cert:\$StoreLocation\$StoreName"
        $cert = Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $Thumbprint } |
            Select-Object -First 1

        return ($null -ne $cert)
    }
    catch {
        Write-Verbose "Error checking certificate store $storePath : $_"
        return $false
    }
}

function Get-ScriptsToSign {
    <#
    .SYNOPSIS
        Finds PowerShell scripts to sign based on include/exclude patterns.
    #>
    param(
        [string]$SearchPath,
        [string[]]$IncludePatterns,
        [string[]]$ExcludePatterns
    )

    $scripts = Get-ChildItem -Path $SearchPath -Recurse -Include $IncludePatterns |
        Where-Object {
            $file = $_
            # Exclude .git directory
            if ($file.FullName -match '[\\/]\.git[\\/]') {
                return $false
            }

            # Check exclude patterns
            foreach ($pattern in $ExcludePatterns) {
                if ($file.Name -like $pattern) {
                    return $false
                }
            }

            return $true
        }

    return $scripts
}

function Add-CertificateToTrustedRoot {
    <#
    .SYNOPSIS
        Adds a certificate to the Trusted Root store using certutil (non-interactive).
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate
    )

    $tempCertPath = $null
    try {
        # Export certificate to temp file
        $tempCertPath = Join-Path $env:TEMP "root-cert-$(New-Guid).cer"
        $certBytes = $Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        [IO.File]::WriteAllBytes($tempCertPath, $certBytes)

        Write-ScriptLog "Adding certificate to Trusted Root store..."

        # Use certutil with -f (force) for non-interactive operation
        # Try user store first (doesn't require admin)
        $result = & certutil -user -addstore -f "Root" $tempCertPath 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -eq 0) {
            Write-ScriptLog "Certificate added to CurrentUser Trusted Root store" -Level Success
            return $true
        }
        else {
            Write-ScriptLog "certutil output: $result" -Level Warning

            # Try machine store (requires admin, but might work in CI)
            Write-ScriptLog "Attempting machine store (may require elevation)..."
            $result = & certutil -addstore -f "Root" $tempCertPath 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -eq 0) {
                Write-ScriptLog "Certificate added to LocalMachine Trusted Root store" -Level Success
                return $true
            }
            else {
                Write-ScriptLog "Failed to add certificate to Trusted Root store: $result" -Level Error
                return $false
            }
        }
    }
    catch {
        Write-ScriptLog "Exception adding certificate to Trusted Root: $_" -Level Error
        return $false
    }
    finally {
        if ($tempCertPath -and (Test-Path $tempCertPath)) {
            Remove-Item $tempCertPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-ScriptSigning {
    <#
    .SYNOPSIS
        Signs a PowerShell script with the provided certificate.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Script,

        [Parameter(Mandatory = $true)]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

        [string]$TimestampServerUrl,

        [bool]$ForceSign = $false
    )

    try {
        # Check if already signed
        $currentSignature = Get-AuthenticodeSignature -FilePath $Script.FullName

        # Check if already signed with same certificate
        # Valid = fully trusted signature
        # UnknownError with trust message = signed but untrusted root (still a valid signature)
        $isAlreadySigned = $false
        if (-not $ForceSign -and $currentSignature.SignerCertificate) {
            $sameThumbprint = $currentSignature.SignerCertificate.Thumbprint -eq $Certificate.Thumbprint
            $isValidSignature = $currentSignature.Status -eq 'Valid'
            $isUntrustedRoot = $currentSignature.Status -eq 'UnknownError' -and 
                               $currentSignature.StatusMessage -like "*certificate*trusted*"
            
            $isAlreadySigned = $sameThumbprint -and ($isValidSignature -or $isUntrustedRoot)
        }

        if ($isAlreadySigned) {
            return @{
                Status = 'AlreadySigned'
                Message = "Already signed with same certificate"
            }
        }

        # Sign the script
        $signParams = @{
            FilePath = $Script.FullName
            Certificate = $Certificate
        }

        if ($TimestampServerUrl) {
            $signParams['TimestampServer'] = $TimestampServerUrl
        }

        $result = Set-AuthenticodeSignature @signParams

        # Check if signing succeeded
        # Status 'Valid' = fully trusted signature
        # Status 'UnknownError' with trust-related message = signed but cert not trusted (still valid signing operation)
        $isTrustIssue = $result.Status -eq 'UnknownError' -and 
                        $result.StatusMessage -like "*certificate*trusted*"

        if ($result.Status -eq 'Valid') {
            return @{
                Status = 'Signed'
                Message = "Successfully signed"
            }
        }
        elseif ($isTrustIssue -and $result.SignerCertificate) {
            # Signature was applied successfully, but certificate chain isn't fully trusted
            # This is expected with self-signed certs not in Trusted Root
            return @{
                Status = 'Signed'
                Message = "Signed (untrusted root certificate)"
            }
        }
        else {
            # Actual signing failure
            $errorDetails = @(
                "Status: $($result.Status)",
                "StatusMessage: $($result.StatusMessage)",
                "Path: $($result.Path)"
            )
            if ($result.SignerCertificate) {
                $errorDetails += "SignerCert: $($result.SignerCertificate.Subject)"
            }
            Write-Verbose "Set-AuthenticodeSignature details: $($errorDetails -join '; ')"
            Write-Host "" # Newline for readability
            Write-Host "    DEBUG - StatusMessage: $($result.StatusMessage)" -ForegroundColor Magenta

            return @{
                Status = 'Failed'
                Message = "Signing failed with status: $($result.Status) - $($result.StatusMessage)"
            }
        }
    }
    catch {
        return @{
            Status = 'Failed'
            Message = "Exception during signing: $_"
        }
    }
}

#endregion

#region Main Script Logic

# Check prerequisites
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-ScriptLog "This script requires PowerShell 7.0 or later" -Level Error
    exit 1
}

if (-not $IsWindows) {
    Write-ScriptLog "This script must be run on Windows" -Level Error
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  PowerShell Script Signing Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Get or import the certificate
$cert = $null

if ($PSCmdlet.ParameterSetName -eq 'FromThumbprint') {
    Write-ScriptLog "Using certificate with thumbprint: $CertificateThumbprint"
    $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction SilentlyContinue

    if (-not $cert) {
        Write-ScriptLog "Certificate with thumbprint $CertificateThumbprint not found" -Level Error
        exit 1
    }
}
elseif ($PSCmdlet.ParameterSetName -eq 'FromFile') {
    $cert = Import-SigningCertificate -FilePath $CertificatePath -Password $CertificatePassword
}
elseif ($PSCmdlet.ParameterSetName -eq 'FromBase64') {
    $cert = Import-SigningCertificate -Base64String $CertificateBase64 -Password $CertificatePassword
}

if (-not $cert) {
    Write-ScriptLog "Failed to obtain certificate" -Level Error
    exit 1
}

# Step 2: Validate the certificate
if (-not $SkipValidation) {
    Write-ScriptLog "Validating certificate..."
    $validation = Test-CodeSigningCertificate -Certificate $cert

    if (-not $validation.IsValid) {
        Write-ScriptLog "Certificate validation failed:" -Level Error
        foreach ($issue in $validation.Issues) {
            Write-ScriptLog "  - $issue" -Level Error
        }
        exit 1
    }

    Write-ScriptLog "Certificate is valid for code signing" -Level Success
}

# Step 2b: Check certificate trust stores
Write-Host ""
Write-Host "Certificate Trust Status:" -ForegroundColor Cyan

# Check Trusted Root CA store (both CurrentUser and LocalMachine)
$inRootCurrentUser = Test-CertificateInStore -Thumbprint $cert.Thumbprint -StoreName 'Root' -StoreLocation 'CurrentUser'
$inRootLocalMachine = Test-CertificateInStore -Thumbprint $cert.Thumbprint -StoreName 'Root' -StoreLocation 'LocalMachine'

if ($inRootCurrentUser -or $inRootLocalMachine) {
    $locations = @()
    if ($inRootCurrentUser) { $locations += "CurrentUser" }
    if ($inRootLocalMachine) { $locations += "LocalMachine" }
    Write-Host "  ✓ Trusted Root CA:        Yes ($($locations -join ', '))" -ForegroundColor Green
} else {
    Write-Host "  ✗ Trusted Root CA:        No" -ForegroundColor Yellow
    Write-Host "    (Certificate may not be trusted for signing)" -ForegroundColor Yellow
}

# Check Trusted Publishers store (both CurrentUser and LocalMachine)
$inPublisherCurrentUser = Test-CertificateInStore -Thumbprint $cert.Thumbprint -StoreName 'TrustedPublisher' -StoreLocation 'CurrentUser'
$inPublisherLocalMachine = Test-CertificateInStore -Thumbprint $cert.Thumbprint -StoreName 'TrustedPublisher' -StoreLocation 'LocalMachine'

if ($inPublisherCurrentUser -or $inPublisherLocalMachine) {
    $locations = @()
    if ($inPublisherCurrentUser) { $locations += "CurrentUser" }
    if ($inPublisherLocalMachine) { $locations += "LocalMachine" }
    Write-Host "  ✓ Trusted Publishers:     Yes ($($locations -join ', '))" -ForegroundColor Green
} else {
    Write-Host "  ℹ Trusted Publishers:     No" -ForegroundColor Gray
    Write-Host "    (Not required for signing, but may affect execution policy)" -ForegroundColor Gray
}
Write-Host ""

# Step 2c: Trust self-signed root if requested
if ($TrustSelfSignedRoot) {
    # Check if cert is self-signed (Subject == Issuer)
    $isSelfSigned = $cert.Subject -eq $cert.Issuer

    if ($isSelfSigned) {
        Write-ScriptLog "Certificate is self-signed, adding to Trusted Root store..."
        $trustResult = Add-CertificateToTrustedRoot -Certificate $cert

        if (-not $trustResult) {
            Write-ScriptLog "Failed to add self-signed certificate to Trusted Root store" -Level Error
            Write-ScriptLog "Signing may fail with 'root certificate not trusted' error" -Level Warning
        }
    }
    else {
        Write-ScriptLog "Certificate is not self-signed (Issuer: $($cert.Issuer))" -Level Warning
        Write-ScriptLog "You may need to manually trust the root CA certificate" -Level Warning
    }
}

# Debug: Display certificate details
Write-Host ""
Write-Host "Certificate Details:" -ForegroundColor Cyan
Write-Host "  Subject:        $($cert.Subject)"
Write-Host "  Issuer:         $($cert.Issuer)"
Write-Host "  Thumbprint:     $($cert.Thumbprint)"
Write-Host "  NotBefore:      $($cert.NotBefore)"
Write-Host "  NotAfter:       $($cert.NotAfter)"
Write-Host "  HasPrivateKey:  $($cert.HasPrivateKey)"

# Debug: Show Enhanced Key Usage list
$ekuExtension = $cert.Extensions | Where-Object { $_.Oid.Value -eq "2.5.29.37" }
if ($ekuExtension) {
    $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$ekuExtension
    Write-Host "  EnhancedKeyUsageList:" -ForegroundColor Cyan
    foreach ($usage in $eku.EnhancedKeyUsages) {
        $isCodeSigning = if ($usage.Value -eq "1.3.6.1.5.5.7.3.3") { " (Code Signing)" } else { "" }
        Write-Host "    - $($usage.FriendlyName) ($($usage.Value))$isCodeSigning"
    }
} else {
    Write-Host "  EnhancedKeyUsageList: NONE (Extension not found)" -ForegroundColor Yellow
}
Write-Host ""

# Step 3: Find scripts to sign
Write-ScriptLog "Searching for PowerShell scripts in: $Path"
$scripts = Get-ScriptsToSign -SearchPath $Path -IncludePatterns $Include -ExcludePatterns $Exclude

if ($scripts.Count -eq 0) {
    Write-ScriptLog "No scripts found matching criteria" -Level Warning
    exit 0
}

Write-ScriptLog "Found $($scripts.Count) script(s) to process"
Write-Host ""

# Step 4: Sign the scripts
$stats = @{
    TotalScripts = $scripts.Count
    Signed = 0
    AlreadySigned = 0
    Failed = 0
    Skipped = 0
}

foreach ($script in $scripts) {
    $relativePath = $script.FullName.Replace($Path, '').TrimStart('\', '/')
    Write-Host "  Processing: $relativePath" -NoNewline

    $result = Invoke-ScriptSigning -Script $script -Certificate $cert -TimestampServerUrl $TimestampServer -ForceSign $Force.IsPresent

    switch ($result.Status) {
        'Signed' {
            Write-Host " - ✓ Signed" -ForegroundColor Green
            $stats.Signed++
        }
        'AlreadySigned' {
            Write-Host " - ✓ Already signed" -ForegroundColor Gray
            $stats.AlreadySigned++
        }
        'Failed' {
            Write-Host " - ✗ Failed: $($result.Message)" -ForegroundColor Red
            $stats.Failed++
        }
        default {
            Write-Host " - ⊘ Skipped" -ForegroundColor Yellow
            $stats.Skipped++
        }
    }
}

# Step 5: Display summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Total scripts:   $($stats.TotalScripts)"
Write-Host "  Newly signed:    $($stats.Signed)" -ForegroundColor Green
Write-Host "  Already signed:  $($stats.AlreadySigned)" -ForegroundColor Gray
Write-Host "  Failed:          $($stats.Failed)" -ForegroundColor $(if ($stats.Failed -gt 0) { 'Red' } else { 'Gray' })
Write-Host "  Skipped:         $($stats.Skipped)" -ForegroundColor $(if ($stats.Skipped -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Return stats object for programmatic use
return $stats

#endregion

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBPt07PwYeOtzOm
# 17FginPPpKZtPtn/AVmmQ/6MofzgdKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCBYg0qnqjrRO3zlBz1xEOCwcSe/IIX4Wbq0FsSRYP8AnTANBgkqhkiG
# 9w0BAQEFAASCAgAfWhNWsYIPZNfqcLhCVBk0usd2zg1ejuMoNZvDD8fZMdgDC6RF
# yMxmkwKPvJYvjSGWcDy1IjUkpnB4xXoO801xap2NS84v/WqDhdMJTAwYuoLLAiAs
# /m41KYVUENX5G45XFQsfVK3spWcEhQTIL3RBQUA/3bcdplHjqUpRytmJztjrz4KD
# qUhh1GWUpfIdgrefoPMV7InaNR0jQ+8ahFbq8+kTwe8ni0WoV9LCbLehHmvJyekC
# lqh+FS81wls0dQJtoKsQjAufQOLCFu67PXjBUwVCcm17RD+f+4z4K6PzATd9UVmZ
# fKqCzxeqNVfDpWAaEkAHYY0OuBzmZeQXfZZZ2EVrO5wo5B/hQjrxc1HSKX4Pd1r9
# 4dcbVXffN7bB7dgvWMlhLel3MPclgV84rWTtbuGW9WuZznlnX6tOe7nOVXmldEPT
# JyYuQqtq2iy2fLlDlhps+aBGtIuh9XE45hkqnAodELlEVXbQvXSMuVojfhMsRvF2
# nvIQIH8twN4Y9kU6nepUSSfDekzJuyjC+PIPC/ZjBzRfcgZQ1CfcblF14NqGT4Xt
# HfqDXBSS0fWReNVrxAWJA7+OFOHukCwfpeJ27ROtsAzCNOVHnPPdW85/mgFruheH
# CD8zPDKsova09HB1K4zLNPLWyAzcRNhd6+sLleBHl7wITBPpbitrvP7n0aGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAxMTkyMjA0NDJaMC8GCSqGSIb3DQEJBDEi
# BCAWBk4sfGsB3HNcOrntZhMoQoi2f6n/NZxyN5CggkNymTANBgkqhkiG9w0BAQEF
# AASCAgAUlWDlteOsIVztU3sQHaWzR8tzog6jN7GIUNwcNrQUTkj81UhYZWaIFvq6
# SduWoR/UvDvV7BzW3g1YAc54OZp0/MwoITvYPW2CfasRE9fkPT8HcrZkNFQ3tLrk
# tijsHHZFOX0CrXwCDaW1eK3dQIYdvntgWaNjM0eBgAG+QpZ5uW3j5Ekp54UoQJsk
# 9LwkZnx3chmuo63+PicLdP35luJofAycy0nS/NUwPTPNf58JTG16joGhC1wMZPk0
# 1fU6ramDZex2ny/t74maR702om+LunI9Ggp6IT1UGbqy70mRXJOCmlUAI4sF/HfO
# VlRvR7L1kB9XzfUafHtUFT2lQsgeNV4EFQXuWi3PjKJZFMSe33gUa+c+2apgu1IX
# RgQTljl+v8tRl1GgCx0xOSG0f4B33nwH9Dz2fEuxXZG9pBnE1cYynlZXQKRq+aCd
# FBfm4lsNr8Ed8ao3MTgFmQwfzuS5wvLC/FwMZIg25H3Q17/DzaRDxmussyDnunBe
# Fv4nNSKciOokoL372bIxthnVRvi95xU9hIAnhDOyOVSMp94ogcLx9WQctnMpxQh7
# 98nfepjBSDb1+y/o3LxgGedIlKBoWJCydQjIzjNIUrbK5mWn7vVGlNCg/Y59FcaW
# akoJUbqv7E8VrT4kos1ypytn6BZdMBG7io0qY3zLyit/LcnTfw==
# SIG # End signature block
