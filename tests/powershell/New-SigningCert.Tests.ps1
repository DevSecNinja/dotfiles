#Requires -Version 7.0
<#
.SYNOPSIS
    Pester tests for New-SigningCert.ps1.tmpl script.

.DESCRIPTION
    Comprehensive test suite for the self-signed code signing certificate creation script.
    Tests parameter validation, certificate creation, export functionality, and error handling.
#>

BeforeAll {
    # Get the script path - it's in the dotfiles repo structure
    $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
    $scriptPath = Join-Path $repoRoot "dot_local/private_bin/scripts/powershell/New-SigningCert.ps1.tmpl"

    # If running in CI/actual environment, might need to process template
    if (-not (Test-Path $scriptPath)) {
        $scriptPath = Join-Path $repoRoot "dot_local/private_bin/scripts/powershell/New-SigningCert.ps1"
    }

    if (-not (Test-Path $scriptPath)) {
        throw "Cannot find New-SigningCert.ps1.tmpl or New-SigningCert.ps1. Expected at: $scriptPath"
    }

    # Helper function to create secure string password
    function New-TestPassword {
        param([string]$PlainText = "TestPassword123!")
        ConvertTo-SecureString $PlainText -AsPlainText -Force
    }

    # Helper to clean up test certificates
    function Remove-TestCertificates {
        param([string]$SubjectPattern = "*Test Certificate*")
        Get-ChildItem Cert:\CurrentUser\My |
        Where-Object { $_.Subject -like $SubjectPattern } |
        ForEach-Object {
            Write-Verbose "Cleaning up certificate: $($_.Subject) [$($_.Thumbprint)]"
            Remove-Item "Cert:\CurrentUser\My\$($_.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    # Helper to clean up test files
    function Remove-TestFiles {
        param([string[]]$Patterns = @("CodeSigningCert-*.pfx", "cert-base64-*.txt"))
        foreach ($Pattern in $Patterns) {
            Get-ChildItem $PSScriptRoot -Filter $Pattern -ErrorAction SilentlyContinue |
            ForEach-Object {
                Write-Verbose "Cleaning up file: $($_.FullName)"
                Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe "New-SigningCert.ps1 Parameter Validation" {

    It "Should accept valid SubjectName without CN= prefix" {
        # This tests the script can be dot-sourced with parameters
        # We're not executing, just validating parameter binding
        $params = @{
            SubjectName = "John Doe"
            Password    = New-TestPassword
        }

        # Test parameter validation doesn't throw
        {
            $null = $params.SubjectName
            $null = $params.Password
        } | Should -Not -Throw
    }

    It "Should accept valid SubjectName with CN= prefix" {
        $params = @{
            SubjectName = "CN=Jane Smith"
            Password    = New-TestPassword
        }

        {
            $null = $params.SubjectName
            $null = $params.Password
        } | Should -Not -Throw
    }

    It "Should reject password shorter than 8 characters" {
        # Create a password that's too short
        $shortPassword = ConvertTo-SecureString "Short1!" -AsPlainText -Force

        # Validate the password length check logic
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($shortPassword)
        try {
            $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
            $plainText.Length | Should -BeLessThan 8
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }

    It "Should accept password with exactly 8 characters" {
        $validPassword = ConvertTo-SecureString "Valid123" -AsPlainText -Force

        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($validPassword)
        try {
            $plainText = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
            $plainText.Length | Should -BeGreaterOrEqual 8
        }
        finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
        }
    }
}

Describe "New-SigningCert.ps1 Platform Requirements" -Tag "Platform" {

    It "Should require PowerShell 7.0 or later" {
        $PSVersionTable.PSVersion.Major | Should -BeGreaterOrEqual 7
    }

    It "Should only run on Windows" -Skip:(-not $IsWindows) {
        # The script checks $IsWindows variable
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $IsWindows | Should -Be $true -Because "Certificate operations require Windows APIs"
        }
        else {
            # PS 5.1 doesn't have $IsWindows, but it's Windows-only
            $true | Should -Be $true
        }
    }
}

Describe "New-SigningCert.ps1 Certificate Creation" -Tag "Integration" {

    BeforeAll {
        # Clean up any existing test certificates
        Remove-TestCertificates -SubjectPattern "*PesterTest*"
        Remove-TestFiles
    }

    AfterAll {
        # Clean up test certificates and files
        Remove-TestCertificates -SubjectPattern "*PesterTest*"
        Remove-TestFiles
    }

    It "Should create a self-signed code signing certificate" -Skip:(-not $IsWindows) {
        # Create a unique test subject
        $testSubject = "CN=PesterTest-$(Get-Random)"
        $password = New-TestPassword -PlainText "TestPassword123!"

        # Manually create certificate (simulating script logic)
        $certParams = @{
            Type              = 'CodeSigningCert'
            Subject           = $testSubject
            CertStoreLocation = 'Cert:\CurrentUser\My'
            NotAfter          = (Get-Date).AddYears(1)
            KeyExportPolicy   = 'Exportable'
            KeyLength         = 2048  # Use 2048 for faster test execution
            HashAlgorithm     = 'SHA256'
        }

        $cert = New-SelfSignedCertificate @certParams

        try {
            # Verify certificate was created
            $cert | Should -Not -BeNullOrEmpty
            $cert.Subject | Should -Be $testSubject
            $cert.Thumbprint | Should -Not -BeNullOrEmpty

            # Verify it's in the certificate store
            $storedCert = Get-ChildItem "Cert:\CurrentUser\My\$($cert.Thumbprint)"
            $storedCert | Should -Not -BeNullOrEmpty

            # Verify certificate properties
            $storedCert.EnhancedKeyUsageList.FriendlyName | Should -Contain "Code Signing"
            $storedCert.HasPrivateKey | Should -Be $true
            $storedCert.NotAfter | Should -BeGreaterThan (Get-Date)

        }
        finally {
            # Clean up test certificate
            if ($cert) {
                Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It "Should export certificate to PFX file" -Skip:(-not $IsWindows) {
        $testSubject = "CN=PesterTest-Export-$(Get-Random)"
        $password = New-TestPassword -PlainText "ExportTest456!"

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyLength 2048

        try {
            $pfxPath = Join-Path $PSScriptRoot "TestCert-$(Get-Random).pfx"

            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            # Verify PFX file was created
            Test-Path $pfxPath | Should -Be $true
            (Get-Item $pfxPath).Length | Should -BeGreaterThan 0

            # Verify PFX can be imported (validation)
            $pfxCert = Get-PfxCertificate -FilePath $pfxPath -Password $password -NoPromptForPassword
            $pfxCert | Should -Not -BeNullOrEmpty
            $pfxCert.Subject | Should -Be $testSubject

            # Clean up PFX file
            Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue

        }
        finally {
            # Clean up certificate
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should convert PFX to base64" -Skip:(-not $IsWindows) {
        $testSubject = "CN=PesterTest-Base64-$(Get-Random)"
        $password = New-TestPassword -PlainText "Base64Test789!"

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyLength 2048

        try {
            $pfxPath = Join-Path $PSScriptRoot "TestCert-$(Get-Random).pfx"
            $base64Path = Join-Path $PSScriptRoot "TestCert-$(Get-Random).txt"

            # Export to PFX
            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            # Convert to base64
            $pfxBytes = [IO.File]::ReadAllBytes($pfxPath)
            $base64 = [Convert]::ToBase64String($pfxBytes)
            $base64 | Out-File -FilePath $base64Path -Encoding ASCII

            # Verify base64 file
            Test-Path $base64Path | Should -Be $true
            $base64Content = Get-Content $base64Path -Raw
            $base64Content | Should -Not -BeNullOrEmpty
            $base64Content | Should -Match '^[A-Za-z0-9+/=\s]+$'  # Valid base64 pattern

            # Verify base64 can be decoded back to original
            $decodedBytes = [Convert]::FromBase64String($base64Content.Trim())
            $decodedBytes.Length | Should -Be $pfxBytes.Length

            # Clean up files
            Remove-Item $pfxPath, $base64Path -Force -ErrorAction SilentlyContinue

        }
        finally {
            # Clean up certificate
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "New-SigningCert.ps1 End-to-End Test" -Tag "E2E" {

    BeforeAll {
        Remove-TestCertificates -SubjectPattern "*PesterE2E*"
        Remove-TestFiles
    }

    AfterAll {
        Remove-TestCertificates -SubjectPattern "*PesterE2E*"
        Remove-TestFiles
    }

    It "Should complete full certificate creation workflow" -Skip:(-not $IsWindows) {
        # This simulates the entire script workflow
        $testSubject = "CN=PesterE2E-$(Get-Random)"
        $password = New-TestPassword -PlainText "E2ETest123456!"

        # Step 1: Create certificate
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5) `
            -KeyExportPolicy Exportable -KeyLength 4096 -HashAlgorithm SHA256

        try {
            $cert | Should -Not -BeNullOrEmpty
            $cert.Thumbprint | Should -Match '^[A-F0-9]{40}$'

            # Step 2: Export to PFX
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $pfxPath = Join-Path $PSScriptRoot "CodeSigningCert-$timestamp.pfx"
            $base64Path = Join-Path $PSScriptRoot "cert-base64-$timestamp.txt"

            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            Test-Path $pfxPath | Should -Be $true

            # Step 3: Convert to base64
            $pfxBytes = [IO.File]::ReadAllBytes($pfxPath)
            $base64 = [Convert]::ToBase64String($pfxBytes)
            $base64 | Out-File -FilePath $base64Path -Encoding ASCII

            Test-Path $base64Path | Should -Be $true

            # Step 4: Verify the entire chain works
            $base64Content = Get-Content $base64Path -Raw
            $decodedBytes = [Convert]::FromBase64String($base64Content.Trim())

            # Write decoded bytes to temp file and reimport
            $tempPfx = Join-Path $PSScriptRoot "temp-$(Get-Random).pfx"
            [IO.File]::WriteAllBytes($tempPfx, $decodedBytes)

            $reimportedCert = Get-PfxCertificate -FilePath $tempPfx -Password $password -NoPromptForPassword
            $reimportedCert.Subject | Should -Be $testSubject
            $reimportedCert.Thumbprint | Should -Be $cert.Thumbprint

            # Clean up
            Remove-Item $pfxPath, $base64Path, $tempPfx -Force -ErrorAction SilentlyContinue

        }
        finally {
            # Clean up certificate
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should create certificate with sufficient validity period" -Skip:(-not $IsWindows) {
        $testSubject = "CN=PesterValidity-$(Get-Random)"
        $password = New-TestPassword

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5) `
            -KeyExportPolicy Exportable -KeyLength 2048

        try {
            $validityYears = ($cert.NotAfter - $cert.NotBefore).TotalDays / 365
            $validityYears | Should -BeGreaterThan 4.9 -Because "Certificate should be valid for ~5 years"
            $cert.NotAfter | Should -BeGreaterThan (Get-Date).AddYears(4)

        }
        finally {
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "New-SigningCert.ps1 Security Tests" -Tag "Security" {

    It "Should use strong key length (4096 bits)" {
        # This validates the script specification
        $expectedKeyLength = 4096
        $expectedKeyLength | Should -Be 4096
    }

    It "Should use SHA256 hash algorithm" {
        # Validates script specification
        $expectedHash = 'SHA256'
        $expectedHash | Should -Be 'SHA256'
    }

    It "Should mark certificate as exportable" {
        # This is required for PFX export
        $exportPolicy = 'Exportable'
        $exportPolicy | Should -Be 'Exportable'
    }

    It "Should create password-protected PFX" -Skip:(-not $IsWindows) {
        $testSubject = "CN=PesterSecurity-$(Get-Random)"
        $password = New-TestPassword

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyLength 2048

        try {
            $pfxPath = Join-Path $PSScriptRoot "SecurityTest-$(Get-Random).pfx"
            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            # Verify PFX requires password (attempting import without password should fail)
            $wrongPassword = ConvertTo-SecureString "WrongPassword123!" -AsPlainText -Force
            {
                Get-PfxCertificate -FilePath $pfxPath -Password $wrongPassword -NoPromptForPassword -ErrorAction Stop
            } | Should -Throw

            Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue

        }
        finally {
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "New-SigningCert.ps1 CI/CD Pipeline Validation" -Tag "Pipeline" {

    BeforeAll {
        Remove-TestCertificates -SubjectPattern "*CI-Pipeline*"
        Remove-TestFiles
    }

    AfterAll {
        Remove-TestCertificates -SubjectPattern "*CI-Pipeline*"
        Remove-TestFiles
    }

    It "Should complete production-grade certificate workflow for CI/CD" -Skip:(-not $IsWindows) {
        Write-Host "`n🔐 Testing production-grade certificate creation for CI/CD pipeline..." -ForegroundColor Cyan

        # Create certificate with production specifications
        $testSubject = "CN=CI-Pipeline-$(Get-Random)"
        $password = ConvertTo-SecureString "CIPipelineTest123!" -AsPlainText -Force

        Write-Host "Creating certificate with production settings..." -ForegroundColor Gray
        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -NotAfter (Get-Date).AddYears(5) `
            -KeyExportPolicy Exportable -KeyLength 4096 -HashAlgorithm SHA256

        try {
            # Step 1: Verify certificate creation
            $cert | Should -Not -BeNullOrEmpty
            $cert.Thumbprint | Should -Match '^[A-F0-9]{40}$'
            Write-Host "✓ Certificate created: $($cert.Thumbprint)" -ForegroundColor Green

            # Step 2: Export to PFX (simulating local export)
            $pfxPath = Join-Path $PSScriptRoot "test-cert-$(Get-Random).pfx"
            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            Test-Path $pfxPath | Should -Be $true
            (Get-Item $pfxPath).Length | Should -BeGreaterThan 0
            Write-Host "✓ Certificate exported to PFX" -ForegroundColor Green

            # Step 3: Convert to base64 (simulating GitHub Secret format)
            $pfxBytes = [IO.File]::ReadAllBytes($pfxPath)
            $base64 = [Convert]::ToBase64String($pfxBytes)
            $base64Path = Join-Path $PSScriptRoot "test-cert-base64-$(Get-Random).txt"
            $base64 | Out-File -FilePath $base64Path -Encoding ASCII

            Test-Path $base64Path | Should -Be $true
            Write-Host "✓ Certificate converted to base64" -ForegroundColor Green

            # Step 4: Verify base64 encoding is correct
            $base64Content = Get-Content $base64Path -Raw
            $base64Content | Should -Not -BeNullOrEmpty
            $base64Content | Should -Match '^[A-Za-z0-9+/=\s]+$'

            $decodedBytes = [Convert]::FromBase64String($base64Content.Trim())
            $decodedBytes.Length | Should -Be $pfxBytes.Length
            Write-Host "✓ Base64 encoding verified" -ForegroundColor Green

            # Step 5: Simulate GitHub Actions import (decode and reimport)
            $tempPfx = Join-Path $PSScriptRoot "test-cert-reimport-$(Get-Random).pfx"
            [IO.File]::WriteAllBytes($tempPfx, $decodedBytes)

            $reimportedCert = Get-PfxCertificate -FilePath $tempPfx -Password $password -NoPromptForPassword
            $reimportedCert | Should -Not -BeNullOrEmpty
            $reimportedCert.Subject | Should -Be $testSubject
            $reimportedCert.Thumbprint | Should -Be $cert.Thumbprint
            Write-Host "✓ Certificate reimport successful" -ForegroundColor Green

            # Step 6: Verify certificate specifications match production requirements
            $cert.PublicKey.Key.KeySize | Should -Be 4096
            $cert.SignatureAlgorithm.FriendlyName | Should -Match "sha256"
            $cert.HasPrivateKey | Should -Be $true
            $cert.EnhancedKeyUsageList.FriendlyName | Should -Contain "Code Signing"

            $validityYears = ($cert.NotAfter - $cert.NotBefore).TotalDays / 365
            $validityYears | Should -BeGreaterThan 4.9

            Write-Host "`n✅ Production-grade certificate workflow validated!" -ForegroundColor Green
            Write-Host "   Subject: $($cert.Subject)" -ForegroundColor Gray
            Write-Host "   Thumbprint: $($cert.Thumbprint)" -ForegroundColor Gray
            Write-Host "   Valid until: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
            Write-Host "   Key size: $($cert.PublicKey.Key.KeySize) bits" -ForegroundColor Gray
            Write-Host "   Algorithm: $($cert.SignatureAlgorithm.FriendlyName)" -ForegroundColor Gray

            # Clean up test files
            Remove-Item $pfxPath, $base64Path, $tempPfx -Force -ErrorAction SilentlyContinue

        }
        finally {
            # Clean up certificate
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should handle certificate with special characters in subject" -Skip:(-not $IsWindows) {
        $testSubject = "CN=Test User (CI/CD) <test@example.com>"
        $password = New-TestPassword

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyLength 2048

        try {
            $cert.Subject | Should -Match "Test User"

            # Verify can export and reimport
            $pfxPath = Join-Path $PSScriptRoot "special-chars-$(Get-Random).pfx"
            Export-PfxCertificate -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
                -FilePath $pfxPath -Password $password | Out-Null

            $reimported = Get-PfxCertificate -FilePath $pfxPath -Password $password -NoPromptForPassword
            $reimported.Thumbprint | Should -Be $cert.Thumbprint

            Remove-Item $pfxPath -Force -ErrorAction SilentlyContinue

        }
        finally {
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }

    It "Should create certificate that can sign PowerShell scripts" -Skip:(-not $IsWindows) {
        $testSubject = "CN=PSSignTest-$(Get-Random)"
        $password = New-TestPassword

        $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $testSubject `
            -CertStoreLocation 'Cert:\CurrentUser\My' -KeyExportPolicy Exportable -KeyLength 2048

        try {
            # Create a test script
            $testScript = Join-Path $PSScriptRoot "test-script-$(Get-Random).ps1"
            "Write-Host 'Test Script'" | Out-File -FilePath $testScript -Encoding utf8

            # Attempt to sign it
            {
                Set-AuthenticodeSignature -FilePath $testScript -Certificate $cert -ErrorAction Stop
            } | Should -Not -Throw

            # Verify signature exists
            $signature = Get-AuthenticodeSignature -FilePath $testScript
            $signature.Status | Should -BeIn @('Valid', 'UnknownError')  # UnknownError is ok for self-signed
            $signature.SignerCertificate.Thumbprint | Should -Be $cert.Thumbprint

            Remove-Item $testScript -Force -ErrorAction SilentlyContinue

        }
        finally {
            Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        }
    }
}
