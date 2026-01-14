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
    [switch]$Force
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

        if (-not $ForceSign -and
            $currentSignature.Status -eq 'Valid' -and
            $currentSignature.SignerCertificate.Thumbprint -eq $Certificate.Thumbprint) {
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

        if ($result.Status -eq 'Valid') {
            return @{
                Status = 'Signed'
                Message = "Successfully signed"
            }
        }
        else {
            return @{
                Status = 'Failed'
                Message = "Signing failed with status: $($result.Status)"
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
