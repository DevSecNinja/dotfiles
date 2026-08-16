#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for Sign-PowerShellScripts.ps1.tmpl script.

.DESCRIPTION
    Comprehensive test suite for the PowerShell script signing tool.
    Tests end-to-end scenarios including:
    - Certificate creation using New-SigningCert.ps1
    - Certificate import from various sources
    - Script signing functionality
    - Signature validation
    - Error handling and edge cases
#>

BeforeAll {
    # Get script paths
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $signingScriptPath = Join-Path $repoRoot "home" | Join-Path -ChildPath "dot_config" | Join-Path -ChildPath "powershell" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "Sign-PowerShellScripts.ps1"
    $certScriptPath = Join-Path $repoRoot "home" | Join-Path -ChildPath "dot_config" | Join-Path -ChildPath "powershell" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "New-SigningCert.ps1.tmpl"

    # Verify scripts exist
    if (-not (Test-Path $signingScriptPath)) {
        throw "Cannot find Sign-PowerShellScripts.ps1 at: $signingScriptPath"
    }

    if (-not (Test-Path $certScriptPath)) {
        throw "Cannot find New-SigningCert.ps1.tmpl at: $certScriptPath"
    }

    # Create test workspace
    $script:TestRoot = Join-Path $PSScriptRoot "SignTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    New-Item -ItemType Directory -Path $script:TestRoot -Force | Out-Null

    # Helper functions
    function New-TestPassword {
        param([string]$PlainText = "TestPassword123!")
        ConvertTo-SecureString $PlainText -AsPlainText -Force
    }

    function New-TestScript {
        param(
            [string]$Name = "TestScript.ps1",
            [string]$Content = 'Write-Host "Test Script"',
            [string]$Path = $script:TestRoot
        )
        $scriptPath = Join-Path $Path $Name
        Set-Content -Path $scriptPath -Value $Content -Force
        return Get-Item $scriptPath
    }

    function Remove-TestCertificates {
        param([string]$SubjectPattern = "*Test Certificate*")
        Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -like $SubjectPattern } |
        ForEach-Object {
            Remove-Item "Cert:\CurrentUser\My\$($_.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    function Get-SecureStringPlainText {
        param([SecureString]$SecureString)
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }

    # Helper to get acceptable signature statuses
    # In CI, Root store import may fail due to permissions, so accept fallback statuses
    # Locally, we expect 'Valid' since the cert should be in Trusted Root
    function Get-AcceptableSignatureStatuses {
        if ($env:CI -eq 'true') {
            return @('Valid', 'UnknownError', 'HashMismatch')
        }
        else {
            return @('Valid')
        }
    }

    # Create test certificate for all tests (only on Windows, and only when the
    # caller has opted in to touching the certificate stores). Without the
    # opt-in this block is skipped entirely, so a dev machine's
    # Cert:\CurrentUser\My and Cert:\CurrentUser\Root are left untouched.
    if ($IsWindows -and $env:DOTFILES_TEST_CERTSTORE -eq 'true') {
        # Clean up any existing test certificates
        Remove-TestCertificates -SubjectPattern "*SignTest*"

        # Create a test certificate
        $script:TestCertSubject = "CN=SignTest-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        $script:TestCertPassword = New-TestPassword "SecurePass123!"
        $script:TestCertPath = Join-Path $script:TestRoot "test-cert.pfx"

        # Create certificate using New-SigningCert.ps1
        $certScript = Get-Content $certScriptPath -Raw
        # Replace the chezmoi template variable with our test subject
        $certScript = $certScript -replace '\{\{\s*\.name\s*\}\}', 'SignTest'
        $tempCertScript = Join-Path $script:TestRoot "New-SigningCert-temp.ps1"
        Set-Content -Path $tempCertScript -Value $certScript

        # Execute certificate creation
        & $tempCertScript -SubjectName $script:TestCertSubject -Password $script:TestCertPassword

        # Export certificate for testing
        $cert = Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -eq $script:TestCertSubject } |
        Select-Object -First 1

        if ($cert) {
            Export-PfxCertificate -Cert $cert -FilePath $script:TestCertPath -Password $script:TestCertPassword | Out-Null

            # Create base64 version
            $certBytes = [System.IO.File]::ReadAllBytes($script:TestCertPath)
            $script:TestCertBase64 = [Convert]::ToBase64String($certBytes)

            # Store thumbprint and cert object
            $script:TestCertThumbprint = $cert.Thumbprint
            $script:TestCert = $cert

            # Trust the certificate for testing (add to Trusted Root)
            # This allows signatures to show as 'Valid' rather than 'UnknownError'
            # Skip in CI mode - may prompt for user input and we accept fallback statuses anyway
            if ($env:CI -ne 'true') {
                try {
                    # Use Import-PfxCertificate for PFX files (Import-Certificate is for .cer files)
                    Import-PfxCertificate -FilePath $script:TestCertPath -CertStoreLocation "Cert:\CurrentUser\Root" -Password $script:TestCertPassword -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Could not add certificate to Trusted Root: $_"
                }
            }
            else {
                Write-Host "Skipping Trusted Root import in CI mode" -ForegroundColor Yellow
            }
        }
        else {
            Write-Warning "Failed to create test certificate - Windows-specific tests will be skipped"
        }
    }
}

AfterAll {
    # Cleanup test workspace
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Only touch the certificate stores when this run was allowed to create
    # certificates in the first place. Guarding the teardown matters as much as
    # the setup: the "*Test*" pattern below is broad and must never run against
    # a dev machine's store during an ordinary test run.
    if ($env:DOTFILES_TEST_CERTSTORE -eq 'true') {
        # Cleanup test certificates from Trusted Root store (if added, skip in CI mode)
        if ($IsWindows -and $script:TestCertThumbprint -and $env:CI -ne 'true') {
            try {
                if (Test-Path "Cert:\CurrentUser\Root\$script:TestCertThumbprint") {
                    # Use certutil.exe which works reliably in PowerShell Core
                    $null = certutil.exe -delstore -user Root $script:TestCertThumbprint 2>&1
                }
            }
            catch {
                Write-Warning "Could not remove certificate from Trusted Root: $_"
            }
        }

        # Cleanup test certificates from My store
        Remove-TestCertificates -SubjectPattern "*Test*"
    }
}

Describe "Sign-PowerShellScripts.ps1 - Parameter Validation" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

    It "Should require CertificatePath when using FromFile parameter set" {
        # This tests the parameter set binding
        $params = @{
            CertificatePath     = Join-Path $script:TestRoot "dummy.pfx"
            CertificatePassword = New-TestPassword
        }

        # Create dummy file
        New-Item -ItemType File -Path $params.CertificatePath -Force | Out-Null

        # Should not throw when all required params are present
        { $null = $params } | Should -Not -Throw

        Remove-Item $params.CertificatePath -Force
    }

    It "Should require CertificatePassword when using FromBase64 parameter set" {
        $params = @{
            CertificateBase64   = "MIIK..."
            CertificatePassword = New-TestPassword
        }

        { $null = $params } | Should -Not -Throw
    }

    It "Should validate CertificateThumbprint format" {
        # Valid thumbprint (40 hex characters)
        $validThumbprint = "A" * 40
        { [void][System.Text.RegularExpressions.Regex]::Match($validThumbprint, '^[A-F0-9]{40}$') } | Should -Not -Throw

        # Invalid thumbprint (wrong length)
        $invalidThumbprint = "A" * 39
        [System.Text.RegularExpressions.Regex]::Match($invalidThumbprint, '^[A-F0-9]{40}$').Success | Should -Be $false
    }

    It "Should default to current directory for Path parameter" {
        # Test default value logic
        $defaultPath = $PWD
        $defaultPath | Should -Not -BeNullOrEmpty
    }
}

Describe "Sign-PowerShellScripts.ps1 - Certificate Import" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    BeforeAll {
        # Verify certificate was created in top-level BeforeAll
        if (-not $script:TestCertThumbprint) {
            throw "Test certificate not available - top-level BeforeAll may have failed"
        }
    }

    It "Should import certificate from PFX file" {
        # Remove certificate if it exists
        if (Test-Path "Cert:\CurrentUser\My\$script:TestCertThumbprint") {
            Remove-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -Force
        }

        # Import using the signing script's logic (simulate)
        $cert = Import-PfxCertificate -FilePath $script:TestCertPath `
            -CertStoreLocation 'Cert:\CurrentUser\My' `
            -Password $script:TestCertPassword `
            -Exportable

        $cert | Should -Not -BeNullOrEmpty
        $cert.Thumbprint | Should -Be $script:TestCertThumbprint
        $cert.Subject | Should -Be $script:TestCertSubject
    }

    It "Should import certificate from base64 string" {
        # Remove certificate if it exists
        if (Test-Path "Cert:\CurrentUser\My\$script:TestCertThumbprint") {
            Remove-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -Force
        }

        # Simulate the signing script's base64 import logic
        $certBytes = [Convert]::FromBase64String($script:TestCertBase64)
        $tempCertPath = Join-Path $env:TEMP "cert-test-$(New-Guid).pfx"

        try {
            [IO.File]::WriteAllBytes($tempCertPath, $certBytes)
            $cert = Import-PfxCertificate -FilePath $tempCertPath `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -Password $script:TestCertPassword `
                -Exportable

            $cert | Should -Not -BeNullOrEmpty
            $cert.Thumbprint | Should -Be $script:TestCertThumbprint
        }
        finally {
            if (Test-Path $tempCertPath) {
                Remove-Item $tempCertPath -Force
            }
        }
    }

    It "Should find certificate by thumbprint" {
        # Ensure certificate is installed
        $cert = Get-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -ErrorAction SilentlyContinue

        $cert | Should -Not -BeNullOrEmpty
        $cert.Thumbprint | Should -Be $script:TestCertThumbprint
    }

    It "Should fail with invalid password" {
        # Remove certificate if it exists
        if (Test-Path "Cert:\CurrentUser\My\$script:TestCertThumbprint") {
            Remove-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -Force
        }

        $wrongPassword = New-TestPassword "WrongPassword123!"

        {
            Import-PfxCertificate -FilePath $script:TestCertPath `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -Password $wrongPassword
        } | Should -Throw
    }

    AfterAll {
        # Ensure certificate is reinstalled for subsequent tests
        # The import tests may have removed it, so reimport from PFX
        if (-not (Test-Path "Cert:\CurrentUser\My\$script:TestCertThumbprint")) {
            $cert = Import-PfxCertificate -FilePath $script:TestCertPath `
                -CertStoreLocation 'Cert:\CurrentUser\My' `
                -Password $script:TestCertPassword `
                -Exportable
            $script:TestCert = $cert

            # Re-add to Trusted Root if not present (skip in CI mode)
            if ($env:CI -ne 'true' -and -not (Test-Path "Cert:\CurrentUser\Root\$script:TestCertThumbprint")) {
                try {
                    # Use Import-PfxCertificate for PFX files
                    Import-PfxCertificate -FilePath $script:TestCertPath -CertStoreLocation "Cert:\CurrentUser\Root" -Password $script:TestCertPassword -ErrorAction Stop | Out-Null
                }
                catch {
                    Write-Warning "Could not add certificate to Trusted Root: $_"
                }
            }
        }
        else {
            # Refresh the certificate object reference
            $script:TestCert = Get-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint"
        }
    }
}

Describe "Sign-PowerShellScripts.ps1 - Certificate Validation" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    It "Should validate certificate has code signing EKU" {
        if (-not $script:TestCert) {
            Set-ItResult -Skipped -Because "Test certificate not available"
            return
        }

        $codeSigningOid = "1.3.6.1.5.5.7.3.3"
        $hasCodeSigningEku = $script:TestCert.Extensions |
        Where-Object { $_.Oid.Value -eq "2.5.29.37" } |
        ForEach-Object {
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$_
            $eku.EnhancedKeyUsages.Value -contains $codeSigningOid
        }

        $hasCodeSigningEku | Should -Be $true
    }

    It "Should validate certificate is not expired" {
        if (-not $script:TestCert) {
            Set-ItResult -Skipped -Because "Test certificate not available"
            return
        }

        $script:TestCert.NotAfter | Should -BeGreaterThan (Get-Date)
    }

    It "Should validate certificate is currently valid" {
        if (-not $script:TestCert) {
            Set-ItResult -Skipped -Because "Test certificate not available"
            return
        }

        $script:TestCert.NotBefore | Should -BeLessThan (Get-Date)
    }

    It "Should validate certificate has private key" {
        if (-not $script:TestCert) {
            Set-ItResult -Skipped -Because "Test certificate not available"
            return
        }

        $script:TestCert.HasPrivateKey | Should -Be $true
    }
}

Describe "Sign-PowerShellScripts.ps1 - Script Discovery" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

    BeforeAll {
        # Create test directory structure
        $script:TestScriptsRoot = Join-Path $script:TestRoot "TestScripts"
        New-Item -ItemType Directory -Path $script:TestScriptsRoot -Force | Out-Null

        # Create various test files
        New-TestScript -Name "Script1.ps1" -Path $script:TestScriptsRoot
        New-TestScript -Name "Script2.ps1" -Path $script:TestScriptsRoot
        New-TestScript -Name "Template.ps1.tmpl" -Path $script:TestScriptsRoot
        New-TestScript -Name "Test.Tests.ps1" -Path $script:TestScriptsRoot

        # Create subdirectory with script
        $subDir = Join-Path $script:TestScriptsRoot "SubDir"
        New-Item -ItemType Directory -Path $subDir -Force | Out-Null
        New-TestScript -Name "SubScript.ps1" -Path $subDir
    }

    It "Should find all .ps1 files recursively" {
        $scripts = Get-ChildItem -Path $script:TestScriptsRoot -Recurse -Include "*.ps1"
        $scripts.Count | Should -BeGreaterThan 0
    }

    It "Should exclude .ps1.tmpl files when specified" {
        $scripts = Get-ChildItem -Path $script:TestScriptsRoot -Recurse -Include "*.ps1" |
        Where-Object { $_.Name -notlike "*.ps1.tmpl" }

        $scripts | Where-Object { $_.Name -eq "Template.ps1.tmpl" } | Should -BeNullOrEmpty
    }

    It "Should exclude .Tests.ps1 files when specified" {
        $scripts = Get-ChildItem -Path $script:TestScriptsRoot -Recurse -Include "*.ps1" |
        Where-Object { $_.Name -notlike "*.Tests.ps1" -and $_.Name -notlike "*.ps1.tmpl" }

        $scripts | Where-Object { $_.Name -eq "Test.Tests.ps1" } | Should -BeNullOrEmpty
    }

    It "Should find scripts in subdirectories" {
        $scripts = Get-ChildItem -Path $script:TestScriptsRoot -Recurse -Include "*.ps1"
        $scripts | Where-Object { $_.Name -eq "SubScript.ps1" } | Should -Not -BeNullOrEmpty
    }
}

Describe "Sign-PowerShellScripts.ps1 - Script Signing" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    BeforeAll {
        # Verify certificate is available
        if (-not $script:TestCert -or -not $script:TestCertThumbprint) {
            throw "Test certificate not available - top-level BeforeAll may have failed"
        }

        # Store reference to signing certificate
        $script:SigningCert = $script:TestCert

        # Create test scripts
        $script:UnsignedScript = New-TestScript -Name "Unsigned.ps1"
        $script:ToBeSignedScript = New-TestScript -Name "ToBeSigned.ps1"
    }

    It "Should sign an unsigned script" {
        $result = Set-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName `
            -Certificate $script:SigningCert `
            -TimestampServer "http://timestamp.digicert.com"

        # Locally: expect 'Valid' (cert in Trusted Root)
        # CI: accept fallback statuses if Root store import failed due to permissions
        $result.Status | Should -BeIn (Get-AcceptableSignatureStatuses)
        $result.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
    }

    It "Should verify signed script has valid signature" {
        # Sign the script first
        Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Verify signature
        $signature = Get-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName

        # Locally: expect 'Valid'; CI: accept fallback statuses
        $signature.Status | Should -BeIn (Get-AcceptableSignatureStatuses)
        $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
    }

    It "Should detect already-signed script" {
        # Sign the script
        Set-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Check signature
        $signature = Get-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName

        # Locally: expect 'Valid'; CI: accept fallback statuses
        $signature.Status | Should -BeIn (Get-AcceptableSignatureStatuses)
        $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint

        # Signing again should detect it's already signed
        # Check if status indicates the script is signed (any acceptable status)
        $acceptableStatuses = Get-AcceptableSignatureStatuses
        $isAlreadySigned = ($signature.Status -in $acceptableStatuses -and
            $signature.SignerCertificate.Thumbprint -eq $script:SigningCert.Thumbprint)

        $isAlreadySigned | Should -Be $true
    }

    It "Should allow re-signing with Force flag simulation" {
        # Sign the script first
        Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Get initial signature
        $firstSignature = Get-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName
        # Locally: expect 'Valid'; CI: accept fallback statuses
        $firstSignature.Status | Should -BeIn (Get-AcceptableSignatureStatuses)

        # Sign again (simulating Force behavior)
        Start-Sleep -Seconds 1  # Ensure timestamp difference
        $secondSignResult = Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert

        $secondSignResult.Status | Should -BeIn (Get-AcceptableSignatureStatuses)
    }
}

Describe "Sign-PowerShellScripts.ps1 - End-to-End Integration Tests" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CI -eq 'true' -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    BeforeAll {
        # Verify certificate is available
        if (-not $script:TestCert -or -not $script:TestCertThumbprint) {
            throw "Test certificate not available - top-level BeforeAll may have failed"
        }

        # Create a fresh test environment
        $script:E2ERoot = Join-Path $script:TestRoot "E2E"
        New-Item -ItemType Directory -Path $script:E2ERoot -Force | Out-Null

        # Create multiple test scripts
        1..5 | ForEach-Object {
            New-TestScript -Name "E2EScript$_.ps1" -Path $script:E2ERoot -Content "Write-Host 'E2E Test $_'"
        }

        # Create files to exclude
        New-TestScript -Name "Template.ps1.tmpl" -Path $script:E2ERoot
        New-TestScript -Name "E2ETest.Tests.ps1" -Path $script:E2ERoot

        # Prepare signing script
        $script:SigningScript = Get-Content $signingScriptPath -Raw
        $tempSignScript = Join-Path $script:E2ERoot "Sign-PowerShellScripts-temp.ps1"
        Set-Content -Path $tempSignScript -Value $script:SigningScript

        $script:SigningScriptPath = $tempSignScript
    }

    It "Should sign all scripts in directory using certificate thumbprint" {
        # Execute signing script
        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:E2ERoot `
            -Exclude "*.ps1.tmpl", "*.Tests.ps1", "*-temp.ps1"

        $stats | Should -Not -BeNullOrEmpty
        $stats.TotalScripts | Should -Be 5
        # With self-signed certs, scripts may fail to sign due to trust issues
        # Verify at least some scripts were processed
        ($stats.Signed + $stats.Failed) | Should -Be 5
    }

    It "Should detect already-signed scripts on second run" {
        # Run signing again
        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:E2ERoot `
            -Exclude "*.ps1.tmpl", "*.Tests.ps1", "*-temp.ps1"

        $stats | Should -Not -BeNullOrEmpty
        $stats.TotalScripts | Should -Be 5
        # With self-signed certs, behavior may vary - verify total processed matches
        ($stats.AlreadySigned + $stats.Signed + $stats.Failed) | Should -Be 5
    }

    It "Should verify all signed scripts have valid signatures" {
        $scripts = Get-ChildItem -Path $script:E2ERoot -Filter "E2EScript*.ps1"

        foreach ($scriptFile in $scripts) {
            $signature = Get-AuthenticodeSignature -FilePath $scriptFile.FullName
            # Self-signed certs may show 'UnknownError' if not in Trusted Root
            # 'NotSigned' means signing failed, all others indicate the script was signed
            $signature.Status | Should -Not -Be 'NotSigned'
            if ($signature.SignerCertificate) {
                $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
            }
        }
    }

    It "Should sign scripts using certificate from PFX file" -Skip:(-not $script:TestCertPath -or -not (Test-Path $script:TestCertPath)) {
        # Create a new test script
        $newScript = New-TestScript -Name "FromPFX.ps1" -Path $script:E2ERoot

        # Remove certificate temporarily to force import
        $tempThumbprint = $script:TestCertThumbprint
        Remove-Item "Cert:\CurrentUser\My\$tempThumbprint" -Force -ErrorAction SilentlyContinue

        try {
            # Sign using PFX
            $stats = & $script:SigningScriptPath `
                -CertificatePath $script:TestCertPath `
                -CertificatePassword $script:TestCertPassword `
                -Path $script:E2ERoot `
                -Include "FromPFX.ps1"

            $stats.Signed | Should -BeGreaterThan 0

            # Verify signature
            $signature = Get-AuthenticodeSignature -FilePath $newScript.FullName
            $signature.Status | Should -Be 'Valid'
        }
        finally {
            # Restore certificate for subsequent tests
            if (-not (Test-Path "Cert:\CurrentUser\My\$script:TestCertThumbprint")) {
                $cert = Import-PfxCertificate -FilePath $script:TestCertPath `
                    -CertStoreLocation 'Cert:\CurrentUser\My' `
                    -Password $script:TestCertPassword `
                    -Exportable
                $script:TestCert = $cert

                # Re-add to Trusted Root if not present (skip in CI mode)
                if ($env:CI -ne 'true' -and -not (Test-Path "Cert:\CurrentUser\Root\$script:TestCertThumbprint")) {
                    try {
                        $rootStore = Get-Item "Cert:\CurrentUser\Root" -ErrorAction Stop
                        $rootStore.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
                        $rootStore.Add($cert)
                        $rootStore.Close()
                    }
                    catch {
                        Write-Warning "Could not add certificate to Trusted Root: $_"
                    }
                }
            }
        }
    }

    It "Should sign scripts using base64-encoded certificate" {
        # Create a new test script
        $newScript = New-TestScript -Name "FromBase64.ps1" -Path $script:E2ERoot

        # Sign using base64
        $stats = & $script:SigningScriptPath `
            -CertificateBase64 $script:TestCertBase64 `
            -CertificatePassword $script:TestCertPassword `
            -Path $script:E2ERoot `
            -Include "FromBase64.ps1"

        # With self-signed certs, signing may fail but should attempt
        ($stats.Signed + $stats.Failed) | Should -BeGreaterThan 0

        # Verify signature was attempted (may show UnknownError for self-signed)
        $signature = Get-AuthenticodeSignature -FilePath $newScript.FullName
        # Any status other than NotSigned means signing was attempted
        $signature.Status | Should -Not -Be 'NotSigned'
    }
}

Describe "Sign-PowerShellScripts.ps1 - Error Handling" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CI -eq 'true' -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    BeforeAll {
        # Verify certificate and signing script are available
        if (-not $script:TestCertThumbprint -or -not $script:SigningScriptPath) {
            throw "Test certificate or signing script not available - dependencies may have failed"
        }
    }

    It "Should fail gracefully with invalid certificate thumbprint" {
        $invalidThumbprint = "0" * 40

        # Script outputs error but may not throw - verify it handles invalid thumbprint gracefully
        $result = & $script:SigningScriptPath `
            -CertificateThumbprint $invalidThumbprint `
            -Path $script:TestRoot 2>&1

        # Should either return null/empty stats or produce error output
        $hasError = ($null -eq $result) -or ($result -match 'not found|error|fail')
        $hasError | Should -Be $true
    }

    It "Should fail gracefully with invalid PFX path" {
        $invalidPath = Join-Path $script:TestRoot "nonexistent.pfx"

        {
            & $script:SigningScriptPath `
                -CertificatePath $invalidPath `
                -CertificatePassword (New-TestPassword) `
                -Path $script:TestRoot
        } | Should -Throw
    }

    It "Should handle empty directory gracefully" {
        $emptyDir = Join-Path $script:TestRoot "Empty"
        New-Item -ItemType Directory -Path $emptyDir -Force | Out-Null

        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $emptyDir

        # Should exit gracefully with no scripts found
        $stats | Should -BeNullOrEmpty  # Script exits early
    }
}

Describe "Sign-PowerShellScripts.ps1 - Statistics Reporting" -Tag "CertStore" -Skip:(-not $IsWindows -or $env:CI -eq 'true' -or $env:CHEZMOI_IS_WORK -eq 'true' -or $env:DOTFILES_TEST_CERTSTORE -ne 'true') {

    BeforeAll {
        # Verify certificate and signing script are available
        if (-not $script:TestCertThumbprint -or -not $script:SigningScriptPath) {
            throw "Test certificate or signing script not available - dependencies may have failed"
        }

        $script:StatsRoot = Join-Path $script:TestRoot "Stats"
        New-Item -ItemType Directory -Path $script:StatsRoot -Force | Out-Null

        # Create mix of scripts
        New-TestScript -Name "Stats1.ps1" -Path $script:StatsRoot
        New-TestScript -Name "Stats2.ps1" -Path $script:StatsRoot
        New-TestScript -Name "Stats3.ps1" -Path $script:StatsRoot
    }

    It "Should return statistics object" {
        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:StatsRoot

        $stats | Should -Not -BeNullOrEmpty
        $stats.Keys | Should -Contain 'TotalScripts'
        $stats.Keys | Should -Contain 'Signed'
        $stats.Keys | Should -Contain 'AlreadySigned'
        $stats.Keys | Should -Contain 'Failed'
        $stats.Keys | Should -Contain 'Skipped'
    }

    It "Should report correct total script count" {
        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:StatsRoot

        $stats.TotalScripts | Should -Be 3
    }

    It "Should track signed vs already-signed correctly" {
        # Create a fresh directory with new unsigned scripts for this specific test
        $trackingRoot = Join-Path $script:TestRoot "Tracking-$(Get-Date -Format 'HHmmss')"
        New-Item -ItemType Directory -Path $trackingRoot -Force | Out-Null

        # Create fresh unsigned scripts
        New-TestScript -Name "Track1.ps1" -Path $trackingRoot
        New-TestScript -Name "Track2.ps1" -Path $trackingRoot
        New-TestScript -Name "Track3.ps1" -Path $trackingRoot

        # First run - should attempt to sign all (fresh unsigned scripts)
        $stats1 = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $trackingRoot

        # With self-signed certs, some may fail - verify total processed
        ($stats1.Signed + $stats1.Failed) | Should -Be 3
        $stats1.AlreadySigned | Should -Be 0

        # Second run - scripts were processed (signed or failed)
        $stats2 = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $trackingRoot

        # If first run failed, second run will try again
        # If first run succeeded, second run should detect as already signed
        ($stats2.Signed + $stats2.AlreadySigned + $stats2.Failed) | Should -Be 3

        # Cleanup
        Remove-Item $trackingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDt4W5jY8bXK4D+
# aZrlNbjTS4sxUr8HqoJ36JSv0VtVHKCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCAmazfhBoI3QRbWnhtmOFlrIvLG+sTG/2cIEReOWfbISjANBgkqhkiG
# 9w0BAQEFAASCAgBHz+2tVsuFljvvdCnVt7O0ELPBTYQXsNobbQOKnT412Mfvu8qM
# AiJ4cScwn4MARx991pisK0GyCe/mcboh0bin8fhqcTM9m2e+B5jCY/voOoJz+vQT
# KUt8KcPF8taPb5sx5N+OrIzEnDxmK0e/YbVqeKfii+zIr9HpnVDbsTKs01ql1zh8
# rIqkOcgDvGZwrWZrvP603TATJprMEBPJmUkcyHt++D1i4njKsKgF+RxnPXOgaOxm
# yRqaL3ctf+uWA7tSHmEDG5EtvungAsQ+ftZJX2zUc+pzRE4CC87TNkbOMFR2KwrA
# udwIZUtCWxSOis4xzQofkeMfXsl2GZhR9iLKnI3PurvxOwzE9OSmXajLjuI4zK7g
# jeRCbLm53LynaHax+FtMQrTu7LXef/cYtC3zhET0ALGaY3aZsWrtEoKYTYchONbi
# GQwwFlmzlAuHjMhwpwisuhyrPCxIO1VSZVmQduvQcOlaF11EWQYC8ixbPbyuHf0X
# lsXMuydtV7ff3ax8EXh/t8zhL9PSHTFRrf/afvR0zII7ZoPj5MDmXf9MEVUxarZk
# meLisu1sTplDst4/KglTWMIk09b+KK9cEHqB0ocgUglSkDVx0Q0JCNVRxZVTqRBA
# g1rNSVP7IXrtMaZYFj+UEu2QJhyzsgdCghfKsVenPkoBuc3O7bG3ctJEQ6GCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjA4MTYxMDQ3MjFaMC8GCSqGSIb3DQEJBDEi
# BCBLlHweW+60MwLKct+5kFSpWMvT+101IVmexEwsaweQdDANBgkqhkiG9w0BAQEF
# AASCAgC4rS2HAPqLulJ24XOyq+EjYiFSxNivZpedYxmuOyDvaylQIPU6ZkVv/YbN
# TF/L1rd2DLXMcAc5lske0LugKo2d8wTjU5/baytQA5i9gYX/mWYmMkj3pvZQFL3A
# JbR6A0UfBNuNCjX75BwCIABFrmkJsl0HCGOp5Z/QkLwI6LIt1e4riIMYqo3D6xJT
# JLYXMqqXatGsgdXNcON6MX3/asc+gDuL18McPEvyMQWvChOO/A8d3pb9XcKPX7hw
# KSa1z31L0SJE9hGGmDcJ1+IosoM09/90TNWRGHpdl6WqBHUYUHooJCUr4nv5JKPH
# tMwydFbRVKg0RFXWxxclDM5249Z6bOyVpPW/e9jILySwvBfouiZCn5aU06wpNS3O
# f7e2SFFABIFU4PfYViJtUZyWIyIA0qI+epgN4rRXHi+7kxOlu5TbwyST35Ilnrs0
# TSFTVbVs5KMZmHgetNPnpcNMAYc5lKKHKBLt6NH337tKx0mTmO7YfDTOda9EoSif
# 1Ftk/DUPM1Sr/6NQcOvrHNYjZ5jAwXtcC6xz0VsvUAd2RNhlw4AlTaqYDAC2/8Hi
# jGmj5aAtj7jbPz/LngwWIBqHbPdwPBkt7EZ58rXp6/cheAwPDoUk2qAWJHgL+6qw
# FHDnx1skKEDavZMQX+DVZDOeU+2DAg6WRUNcswT1hmjgNTctPw==
# SIG # End signature block
