#Requires -Version 7.0
<#
.SYNOPSIS
    Runs all Pester tests for PowerShell scripts.

.DESCRIPTION
    Discovers and executes all Pester test files (*.Tests.ps1) in the PowerShell tests directory.
    Generates test results in NUnit XML format and provides detailed console output.
    Used by both CI/CD pipelines and local development.

.PARAMETER TestPath
    The path to the directory containing Pester tests. Defaults to the script's directory.

.PARAMETER OutputPath
    The path where test results should be saved. Defaults to 'test-results.xml' in the current directory.

.PARAMETER Tag
    Optional array of tags to filter tests. Only tests with matching tags will be run.

.PARAMETER ExcludeTag
    Optional array of tags to exclude. Tests with these tags will be skipped.

.PARAMETER CI
    Switch to enable CI mode. Exits with non-zero code if tests fail.

.EXAMPLE
    .\Invoke-PesterTests.ps1
    Runs all tests with default settings.

.EXAMPLE
    .\Invoke-PesterTests.ps1 -CI
    Runs all tests in CI mode (exits with error code on failure).

.EXAMPLE
    .\Invoke-PesterTests.ps1 -Tag "E2E"
    Runs only tests tagged with "E2E".

.EXAMPLE
    .\Invoke-PesterTests.ps1 -ExcludeTag "Integration"
    Runs all tests except those tagged "Integration".

.NOTES
    Requires Pester 5.0 or later.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TestPath = $PSScriptRoot,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "test-results.xml",

    [Parameter(Mandatory = $false)]
    [string[]]$Tag,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeTag,

    [Parameter(Mandatory = $false)]
    [switch]$CI
)

# Ensure we're using PowerShell 7+
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Error "This script requires PowerShell 7.0 or later. Current version: $($PSVersionTable.PSVersion)"
    exit 1
}

# Check if Pester is available
$pesterModule = Get-Module -Name Pester -ListAvailable | Where-Object { $_.Version -ge '5.0.0' } | Select-Object -First 1
if (-not $pesterModule) {
    Write-Error "❌ Pester 5.0 or later is not installed. Please install it with: Install-Module -Name Pester -Force -SkipPublisherCheck -MinimumVersion 5.0.0"
    exit 1
}

Write-Host "🧪 Discovering and running Pester tests..." -ForegroundColor Cyan
Write-Host "   PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host "   Pester Version: $($pesterModule.Version)" -ForegroundColor Gray
Write-Host ""

# Validate test path
if (-not (Test-Path $TestPath)) {
    Write-Error "❌ Test directory not found: $TestPath"
    exit 1
}

# Discover test files
$testFiles = Get-ChildItem -Path $TestPath -Filter "*.Tests.ps1" -Recurse

if ($testFiles.Count -eq 0) {
    Write-Error "❌ No test files found in $TestPath"
    exit 1
}

Write-Host "📋 Found $($testFiles.Count) test file(s):" -ForegroundColor Cyan
$testFiles | ForEach-Object {
    Write-Host "   - $($_.Name)" -ForegroundColor Gray
}
Write-Host ""

# Configure Pester
$config = New-PesterConfiguration

# Run settings
$config.Run.Path = $TestPath
$config.Run.PassThru = $true

# Output settings
$config.Output.Verbosity = 'Detailed'

# Test result settings
$config.TestResult.Enabled = $true
$config.TestResult.OutputFormat = 'NUnitXml'
$config.TestResult.OutputPath = $OutputPath

# Error handling
$config.Should.ErrorAction = 'Stop'

# Apply tag filters if specified
if ($Tag) {
    Write-Host "🏷️  Running tests with tags: $($Tag -join ', ')" -ForegroundColor Yellow
    $config.Filter.Tag = $Tag
}

if ($ExcludeTag) {
    Write-Host "🚫 Excluding tests with tags: $($ExcludeTag -join ', ')" -ForegroundColor Yellow
    $config.Filter.ExcludeTag = $ExcludeTag
}

Write-Host ""
Write-Host "▶️  Starting test execution..." -ForegroundColor Cyan
Write-Host ""

# Run tests
try {
    $result = Invoke-Pester -Configuration $config
}
catch {
    Write-Error "❌ Test execution failed: $_"
    exit 1
}

# Display summary
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 Test Results Summary" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Total:   $($result.TotalCount)"
Write-Host "Passed:  $($result.PassedCount) ✅" -ForegroundColor Green
Write-Host "Failed:  $($result.FailedCount) ❌" -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'White' })
Write-Host "Skipped: $($result.SkippedCount) ⏭️" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Display execution time
$duration = $result.Duration
Write-Host "⏱️  Total execution time: $($duration.ToString('mm\:ss\.fff'))" -ForegroundColor Gray
Write-Host ""

# Display result file location
if (Test-Path $OutputPath) {
    $resultFile = Get-Item $OutputPath
    Write-Host "📄 Test results saved to: $($resultFile.FullName)" -ForegroundColor Gray
    Write-Host "   Size: $([math]::Round($resultFile.Length / 1KB, 2)) KB" -ForegroundColor Gray
    Write-Host ""
}

# Handle failures
if ($result.FailedCount -gt 0) {
    Write-Host "❌ $($result.FailedCount) test(s) failed" -ForegroundColor Red
    Write-Host ""

    if ($CI) {
        Write-Host "🚨 CI mode: Exiting with error code" -ForegroundColor Red
        exit 1
    }
    else {
        Write-Host "💡 Tip: Review failed tests above for details" -ForegroundColor Yellow
        exit 1
    }
}

# Success
Write-Host "✅ All tests passed!" -ForegroundColor Green
Write-Host ""

if ($CI) {
    Write-Host "🎉 CI validation successful" -ForegroundColor Green
}

exit 0
