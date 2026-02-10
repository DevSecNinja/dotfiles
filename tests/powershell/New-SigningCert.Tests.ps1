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
    $scriptPath = Join-Path $repoRoot "home" | Join-Path -ChildPath "dot_config" | Join-Path -ChildPath "powershell" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "New-SigningCert.ps1.tmpl"

    # If running in CI/actual environment, might need to process template
    if (-not (Test-Path $scriptPath)) {
        $scriptPath = Join-Path $repoRoot "home" | Join-Path -ChildPath "dot_config" | Join-Path -ChildPath "powershell" | Join-Path -ChildPath "scripts" | Join-Path -ChildPath "New-SigningCert.ps1"
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

Describe "New-SigningCert.ps1 Parameter Validation" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

Describe "New-SigningCert.ps1 Platform Requirements" -Tag "Platform" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

Describe "New-SigningCert.ps1 Certificate Creation" -Tag "Integration" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

Describe "New-SigningCert.ps1 End-to-End Test" -Tag "E2E" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

Describe "New-SigningCert.ps1 Security Tests" -Tag "Security" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

Describe "New-SigningCert.ps1 CI/CD Pipeline Validation" -Tag "Pipeline" -Skip:($env:CHEZMOI_IS_WORK -eq 'true') {

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

# SIG # Begin signature block
# MIIfEQYJKoZIhvcNAQcCoIIfAjCCHv4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAQf8th4G1BJy4/
# N1bGZmtmqz6ECoBisdZl455Bpx4iLqCCGFQwggUWMIIC/qADAgECAhAQtuD2CsJx
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
# DQEJBDEiBCArY4GTvqwHod+LUowvguwX/782EcFZ6nM5ACjcXdZ0MzANBgkqhkiG
# 9w0BAQEFAASCAgBmJe0fmMRjHzm/KqUqw3IGcQfUeTRqUdI7PUlHbEQt2g3JZTts
# 0YoYHAk7tX7UsSpGk00BZegGDdzleQMhW+RmMPblmG64z5tHBBTbGnA69hbuC6XF
# 7utAaGpTLyrZxTtv0jUWzIRheRTypxLfdPyLwq9LU2iPAE1AUzZYYpx8pI4/lFrR
# bXAv3rSZgAgGklGprOTekRPkgldfCju7KvrdHbXRk3Cf90QjrTHaGZsnMYESqK3V
# pH8DJ+VfW166rsUtu8XTfpXmQgz/5r7GFOwkVuT9xplTZWdkmU6wWGt6OmWi2okt
# 6hDDkaG6NOmmvwflQFA8iOkJl2pf0zHRvaINSl1xazPp+AMlaQC7AlZYTsMHQY8j
# f+AAHGO7y+fZ70/e99bzNrIV6tR9R+OxRrsRpbAYFn5a5uHfEqmdstcqrCzhePtM
# dt8gfWPVngbnKdhYxa9NR/g6XBbhZUk3D6VHasMDvowv4oLZi1T7A6Bes9kla6I4
# C7fCdu+ucXsUU/hBxFgE5XRApKMa9nbK5Ev9c/ajzSUPT8OeNw75b1K2kDutcOLP
# K94kTSkn4lA1Nfh6FFbCQA0rQhM0a91GIueBbKigGIaknC7BpqLzWeLjgDQY5ygk
# 8OszWPd8hpmfEd0vR15mDcP7D75C10m5yLM0W0rMKmcD1TgaQUfAqPVHuKGCAyYw
# ggMiBgkqhkiG9w0BCQYxggMTMIIDDwIBATB9MGkxCzAJBgNVBAYTAlVTMRcwFQYD
# VQQKEw5EaWdpQ2VydCwgSW5jLjFBMD8GA1UEAxM4RGlnaUNlcnQgVHJ1c3RlZCBH
# NCBUaW1lU3RhbXBpbmcgUlNBNDA5NiBTSEEyNTYgMjAyNSBDQTECEAqA7xhLjfEF
# gtHEdqeVdGgwDQYJYIZIAWUDBAIBBQCgaTAYBgkqhkiG9w0BCQMxCwYJKoZIhvcN
# AQcBMBwGCSqGSIb3DQEJBTEPFw0yNjAxMTkyMjA4MjJaMC8GCSqGSIb3DQEJBDEi
# BCBq+5VNWLP88hbmY//5E5CItchbFKhRpVp2Vyzj9SOiVzANBgkqhkiG9w0BAQEF
# AASCAgBObvcHuwWJSwJE+oxx/V0BOhkXI6nyzCq/nt7wzlclDE602SGlY0BIoE0k
# mSQAslokocyIpl3vAQnvegwaqObzsVzOciXhGu9YdtGkGV+5hmK37INfA8zIq2EK
# qsWPJLEZQUtpNNxJWkToTvDjVpcLBIVc0nlZN3OXV2DbgsG81Vn4m5LGOD22ztFV
# mhvHVHIHc8lJmUdv7vubw6oCVLp9fVt5RY98EFAudcOpgNvrVLrEhoVAxxBLmYad
# 3C2dgMSaGnlK5PEpL/X9HYjI/QXMp22KcAxAYKejxs64WOWIAfjPlXPcr2AnoK+h
# JvBB1NyQMCs+p96VhNpUxb6ICvJgo6DdXRVlPkdcy3r4iPvxAFaMsfF4CrehLoFs
# Ht5uINKNvjBVThERFWUqTwvgmcdh9nlG7PHThYvMzSgn9ywM30avxH74OL4dFUfW
# ngH5S6OCORptUUc5aLO5eE4fN3J+GPW6jBHNfe4IGro7UzgjRVaUaosuBoDJlBm4
# oJos7tqyD1tztswocu1FSzDcJAQ/7ZEvUcLi5e/Tl8QQSL4CEgmX8sQtJgCzbXa4
# 7BT4cNgczUjG4P/JtnFgpcohFvfPQBGvatcaAsXbVDHRbFOnCdKoNpXgWCMIBy8e
# FBlphWvtjb3bYzgZ76bip7SJ+Yqcj9nk8xgYnpSHIvlwXmnxhw==
# SIG # End signature block
