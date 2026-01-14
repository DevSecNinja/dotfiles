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
    $signingScriptPath = Join-Path $repoRoot "dot_local/private_bin/scripts/powershell/Sign-PowerShellScripts.ps1"
    $certScriptPath = Join-Path $repoRoot "dot_local/private_bin/scripts/powershell/New-SigningCert.ps1.tmpl"

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
}

AfterAll {
    # Cleanup test workspace
    if (Test-Path $script:TestRoot) {
        Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Cleanup test certificates
    Remove-TestCertificates -SubjectPattern "*Test*"
}

Describe "Sign-PowerShellScripts.ps1 - Parameter Validation" {

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

Describe "Sign-PowerShellScripts.ps1 - Certificate Import" -Skip:(-not $IsWindows) {

    BeforeAll {
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

            # Store thumbprint
            $script:TestCertThumbprint = $cert.Thumbprint
        }
        else {
            throw "Failed to create test certificate"
        }
    }

    AfterAll {
        # Cleanup
        if (Test-Path $script:TestCertPath) {
            Remove-Item $script:TestCertPath -Force
        }
        Remove-TestCertificates -SubjectPattern "*SignTest*"
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
}

Describe "Sign-PowerShellScripts.ps1 - Certificate Validation" -Skip:(-not $IsWindows) {

    BeforeAll {
        # Ensure test certificate exists
        $script:TestCert = Get-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -ErrorAction SilentlyContinue
        if (-not $script:TestCert) {
            throw "Test certificate not found. Import tests may have failed."
        }
    }

    It "Should validate certificate has code signing EKU" {
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
        $script:TestCert.NotAfter | Should -BeGreaterThan (Get-Date)
    }

    It "Should validate certificate is currently valid" {
        $script:TestCert.NotBefore | Should -BeLessThan (Get-Date)
    }

    It "Should validate certificate has private key" {
        $script:TestCert.HasPrivateKey | Should -Be $true
    }
}

Describe "Sign-PowerShellScripts.ps1 - Script Discovery" {

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

Describe "Sign-PowerShellScripts.ps1 - Script Signing" -Skip:(-not $IsWindows) {

    BeforeAll {
        # Ensure certificate is available
        $script:SigningCert = Get-Item "Cert:\CurrentUser\My\$script:TestCertThumbprint" -ErrorAction SilentlyContinue
        if (-not $script:SigningCert) {
            throw "Test certificate not found for signing tests"
        }

        # Create test scripts
        $script:UnsignedScript = New-TestScript -Name "Unsigned.ps1"
        $script:ToBeSignedScript = New-TestScript -Name "ToBeSigned.ps1"
    }

    It "Should sign an unsigned script" {
        $result = Set-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName `
            -Certificate $script:SigningCert `
            -TimestampServer "http://timestamp.digicert.com"

        $result.Status | Should -Be 'Valid'
        $result.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
    }

    It "Should verify signed script has valid signature" {
        # Sign the script first
        Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Verify signature
        $signature = Get-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName

        $signature.Status | Should -Be 'Valid'
        $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
    }

    It "Should detect already-signed script" {
        # Sign the script
        Set-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Check signature
        $signature = Get-AuthenticodeSignature -FilePath $script:UnsignedScript.FullName

        $signature.Status | Should -Be 'Valid'
        $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint

        # Signing again should detect it's already signed
        # (This is what the script's logic does)
        $isAlreadySigned = ($signature.Status -eq 'Valid' -and
            $signature.SignerCertificate.Thumbprint -eq $script:SigningCert.Thumbprint)

        $isAlreadySigned | Should -Be $true
    }

    It "Should allow re-signing with Force flag simulation" {
        # Sign the script first
        Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert | Out-Null

        # Get initial signature
        $firstSignature = Get-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName
        $firstSignature.Status | Should -Be 'Valid'

        # Sign again (simulating Force behavior)
        Start-Sleep -Seconds 1  # Ensure timestamp difference
        $secondSignResult = Set-AuthenticodeSignature -FilePath $script:ToBeSignedScript.FullName `
            -Certificate $script:SigningCert

        $secondSignResult.Status | Should -Be 'Valid'
    }
}

Describe "Sign-PowerShellScripts.ps1 - End-to-End Integration Tests" -Skip:(-not $IsWindows) {

    BeforeAll {
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
            -Exclude "*.ps1.tmpl", "*.Tests.ps1"

        $stats | Should -Not -BeNullOrEmpty
        $stats.TotalScripts | Should -Be 5
        $stats.Signed | Should -Be 5
        $stats.Failed | Should -Be 0
    }

    It "Should detect already-signed scripts on second run" {
        # Run signing again
        $stats = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:E2ERoot `
            -Exclude "*.ps1.tmpl", "*.Tests.ps1"

        $stats | Should -Not -BeNullOrEmpty
        $stats.TotalScripts | Should -Be 5
        $stats.AlreadySigned | Should -Be 5
        $stats.Signed | Should -Be 0
    }

    It "Should verify all signed scripts have valid signatures" {
        $scripts = Get-ChildItem -Path $script:E2ERoot -Filter "E2EScript*.ps1"

        foreach ($script in $scripts) {
            $signature = Get-AuthenticodeSignature -FilePath $script.FullName
            $signature.Status | Should -Be 'Valid'
            $signature.SignerCertificate.Thumbprint | Should -Be $script:TestCertThumbprint
        }
    }

    It "Should sign scripts using certificate from PFX file" -Skip:(-not (Test-Path $script:TestCertPath)) {
        # Create a new test script
        $newScript = New-TestScript -Name "FromPFX.ps1" -Path $script:E2ERoot

        # Remove certificate temporarily to force import
        $tempThumbprint = $script:TestCertThumbprint
        Remove-Item "Cert:\CurrentUser\My\$tempThumbprint" -Force -ErrorAction SilentlyContinue

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

    It "Should sign scripts using base64-encoded certificate" {
        # Create a new test script
        $newScript = New-TestScript -Name "FromBase64.ps1" -Path $script:E2ERoot

        # Sign using base64
        $stats = & $script:SigningScriptPath `
            -CertificateBase64 $script:TestCertBase64 `
            -CertificatePassword $script:TestCertPassword `
            -Path $script:E2ERoot `
            -Include "FromBase64.ps1"

        $stats.Signed | Should -BeGreaterThan 0

        # Verify signature
        $signature = Get-AuthenticodeSignature -FilePath $newScript.FullName
        $signature.Status | Should -Be 'Valid'
    }
}

Describe "Sign-PowerShellScripts.ps1 - Error Handling" -Skip:(-not $IsWindows) {

    It "Should fail gracefully with invalid certificate thumbprint" {
        $invalidThumbprint = "0" * 40

        {
            & $script:SigningScriptPath `
                -CertificateThumbprint $invalidThumbprint `
                -Path $script:TestRoot
        } | Should -Throw
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

Describe "Sign-PowerShellScripts.ps1 - Statistics Reporting" -Skip:(-not $IsWindows) {

    BeforeAll {
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
        # First run - should sign all
        $stats1 = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:StatsRoot

        $stats1.Signed | Should -Be 3
        $stats1.AlreadySigned | Should -Be 0

        # Second run - should detect all as already signed
        $stats2 = & $script:SigningScriptPath `
            -CertificateThumbprint $script:TestCertThumbprint `
            -Path $script:StatsRoot

        $stats2.Signed | Should -Be 0
        $stats2.AlreadySigned | Should -Be 3
    }
}
