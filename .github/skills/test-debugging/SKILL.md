---
name: test-debugging
description: Debugging failing tests and improving test reliability. Use this when tests fail, are flaky, or need troubleshooting.
---

# Test Debugging and Troubleshooting

This skill provides systematic approaches to debugging failing tests, improving test reliability, and resolving common testing issues.

## Systematic Debugging Approach

### 1. Understand the Failure

**Analyze the error message:**
- Read the complete error output
- Identify the specific assertion that failed
- Note the expected vs actual values
- Check the stack trace for failure location

**Reproduce locally:**
```bash
# Run the specific failing test
bats tests/failing-test.bats
Invoke-Pester tests/FailingTest.Tests.ps1

# Run with verbose output
bats --verbose tests/failing-test.bats
Invoke-Pester -Output Detailed

# Run with debugging enabled
DEBUG=1 bats tests/failing-test.bats
$DebugPreference = "Continue"; Invoke-Pester tests/
```

### 2. Isolate the Problem

**Run only the failing test:**
```bash
# Bats - run specific file
bats tests/specific-test.bats

# Pester - run specific test
Invoke-Pester -TestName "specific test name"
Invoke-Pester -Path tests/Specific.Tests.ps1
```

**Add diagnostic output:**
```bash
# Bats
@test "failing test" {
    echo "Input: $input" >&3
    echo "Status: $status" >&3
    echo "Output: $output" >&3
    run command
    [ "$status" -eq 0 ]
}

# Pester
It "failing test" {
    Write-Host "Variable value: $testVar" -ForegroundColor Yellow
    $result = Get-Function
    Write-Host "Result: $result" -ForegroundColor Yellow
    $result | Should -Be $expected
}
```

### 3. Common Test Failure Patterns

#### Timing Issues

**Problem:** Tests fail intermittently due to timing or race conditions.

**Solutions:**
```powershell
# Add appropriate waits
Start-Sleep -Milliseconds 100

# Poll for conditions
$timeout = (Get-Date).AddSeconds(5)
while ((Get-Date) -lt $timeout) {
    if (Test-Condition) { break }
    Start-Sleep -Milliseconds 100
}
```

```bash
# Wait for condition
for i in {1..50}; do
    if [ -f "$file" ]; then break; fi
    sleep 0.1
done
```

#### Environment Dependencies

**Problem:** Tests pass locally but fail in CI, or vice versa.

**Solutions:**
```bash
# Check environment differences
@test "environment check" {
    echo "PATH: $PATH" >&3
    echo "PWD: $PWD" >&3
    echo "HOME: $HOME" >&3
    env | sort >&3
}
```

```powershell
# Check environment
It "environment check" {
    Write-Host "OS: $($PSVersionTable.OS)"
    Write-Host "PSVersion: $($PSVersionTable.PSVersion)"
    Write-Host "PATH: $env:PATH"
    Get-ChildItem Env: | Format-Table
}
```

#### Path Issues

**Problem:** Files or commands not found.

**Solutions:**
```bash
# Use absolute paths based on test location
@test "path handling" {
    cd "$BATS_TEST_DIRNAME/.."
    run ./script.sh
    assert_success
}

# Check file exists before testing
@test "file operations" {
    [ -f "./script.sh" ] || skip "script.sh not found"
    run ./script.sh
}
```

```powershell
# Use PSScriptRoot for relative paths
It "path handling" {
    $scriptPath = Join-Path $PSScriptRoot '../script.ps1'
    Test-Path $scriptPath | Should -Be $true
}
```

#### State Pollution

**Problem:** Tests affect each other through shared state.

**Solutions:**
```bash
setup() {
    # Create isolated temp directory per test
    TEST_DIR="$BATS_TEST_TMPDIR/test-$$"
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"
}

teardown() {
    # Clean up after each test
    cd "$BATS_TEST_DIRNAME"
    rm -rf "$TEST_DIR"
}
```

```powershell
BeforeEach {
    # Reset state before each test
    $script:GlobalVar = $null
    Remove-Item TestDrive:\* -Recurse -Force
}

AfterEach {
    # Clean up mocks
    Remove-Mock *
}
```

## Flaky Test Patterns

### Identifying Flaky Tests

**Run tests multiple times:**
```bash
# Bash - run 10 times
for i in {1..10}; do
    echo "Run $i"
    bats tests/flaky-test.bats || break
done

# PowerShell - run 10 times
1..10 | ForEach-Object {
    Write-Host "Run $_"
    Invoke-Pester tests/Flaky.Tests.ps1
}
```

### Common Causes of Flakiness

#### 1. Non-Deterministic Order

**Problem:** Tests depend on execution order or unordered collections.

**Solution:**
```powershell
# Sort results before comparison
$result = Get-Items | Sort-Object Name
$result[0].Name | Should -Be "expected"

# Use -Contain instead of index-based checks
$result | Should -Contain "expected-item"
```

#### 2. External Dependencies

**Problem:** Tests depend on network, filesystem, or external services.

**Solution:**
```powershell
# Mock external calls
Mock Invoke-RestMethod {
    return @{ Status = "Success" }
}

Mock Test-Path { return $true }
```

```bash
# Mock external commands
my_curl() {
    echo '{"status":"success"}'
}
export -f my_curl
alias curl=my_curl
```

#### 3. Timestamp or Random Data

**Problem:** Tests use current time or random values.

**Solution:**
```powershell
# Mock Get-Date
Mock Get-Date {
    return [datetime]"2026-01-01 12:00:00"
}

# Use fixed seed for random
Get-Random -SetSeed 42
```

#### 4. Resource Cleanup

**Problem:** Previous test runs leave artifacts.

**Solution:**
```bash
setup() {
    # Clean start
    rm -rf "$BATS_TEST_TMPDIR"/*
}

teardown() {
    # Ensure cleanup even on failure
    rm -rf "$BATS_TEST_TMPDIR"/* || true
}
```

## Test Isolation Best Practices

### Use Test Drives / Temp Directories

```powershell
# Pester provides TestDrive:
It "creates file in isolation" {
    New-Item TestDrive:\test.txt
    Test-Path TestDrive:\test.txt | Should -Be $true
}
# Cleaned up automatically after test
```

```bash
# Bats provides $BATS_TEST_TMPDIR
@test "creates file in isolation" {
    touch "$BATS_TEST_TMPDIR/test.txt"
    [ -f "$BATS_TEST_TMPDIR/test.txt" ]
}
```

### Reset Global State

```powershell
BeforeEach {
    # Clear module state
    Remove-Module MyModule -Force -ErrorAction SilentlyContinue
    Import-Module ./MyModule.psd1
}
```

### Avoid Test Interdependence

```bash
# Bad - depends on previous test
@test "create user" {
    create_user "testuser"
}

@test "delete user" {
    delete_user "testuser"  # Fails if previous test skipped
}

# Good - independent tests
@test "delete user" {
    setup() {
        create_user "testuser"
    }
    delete_user "testuser"
}
```

## Debugging Specific Failures

### Mock Not Being Called

```powershell
# Add diagnostic
Mock Get-Content {
    Write-Host "Mock called with: $Path"
    return "mocked"
}

It "test" {
    $result = Get-Data
    Should -Invoke Get-Content -Times 1 -Exactly
}

# Check parameter filters
Mock Get-Content { return "mocked" } -ParameterFilter {
    Write-Host "Filter checking: $Path"
    $Path -eq "expected.txt"
}
```

### Assertion Output Mismatch

```bash
@test "output debugging" {
    run ./script.sh

    # Debug output
    echo "Status: $status" >&3
    echo "Output length: ${#output}" >&3
    echo "Output (hex):" >&3
    echo "$output" | xxd >&3

    # Check for hidden characters
    [ "$output" = "expected" ]
}
```

```powershell
It "output debugging" {
    $result = Get-Output

    # Debug
    Write-Host "Type: $($result.GetType().Name)"
    Write-Host "Length: $($result.Length)"
    Write-Host "Bytes: $([System.Text.Encoding]::UTF8.GetBytes($result))"

    $result | Should -Be "expected"
}
```

### Test Hangs or Timeouts

```bash
# Add timeout to commands
@test "with timeout" {
    run timeout 5s ./slow-script.sh
    [ "$status" -eq 0 ]
}
```

```powershell
# Use job with timeout
It "with timeout" {
    $job = Start-Job { ./slow-script.ps1 }
    $null = Wait-Job $job -Timeout 5
    $job.State | Should -Be "Completed"
    Remove-Job $job
}
```

## CI-Specific Debugging

### Reproduce CI Environment Locally

```bash
# Use same Docker image as CI
docker run -it -v $(pwd):/workspace ubuntu:latest bash
cd /workspace
./tests/run-tests.sh

# Export CI environment variables
export CI=true
export GITHUB_ACTIONS=true
./tests/run-tests.sh
```

### Add CI Diagnostic Steps

```yaml
# GitHub Actions example
- name: Debug test environment
  run: |
    echo "=== Environment ==="
    env | sort
    echo "=== Disk space ==="
    df -h
    echo "=== Files ==="
    ls -la

- name: Run tests with verbose output
  run: |
    bats --verbose --timing tests/
```

### Capture CI Artifacts

```yaml
- name: Upload test results
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: test-results
    path: |
      test-results.xml
      test-output.log
```

## Performance Issues

### Slow Tests

```bash
# Identify slow tests
bats --timing tests/ | grep -E '\([0-9]'

# Profile specific test
time bats tests/slow-test.bats
```

```powershell
# Measure test execution
Measure-Command {
    Invoke-Pester tests/Slow.Tests.ps1
}
```

**Solutions:**
- Remove unnecessary waits/sleeps
- Mock slow external calls
- Use test data instead of generating large datasets
- Parallelize independent tests

### Test Suite Takes Too Long

```bash
# Run tests in parallel
bats --jobs 4 tests/

# Split test suites in CI
# Job 1:
bats tests/unit/
# Job 2:
bats tests/integration/
```

## Quick Checklist

### When a test fails

1. ✅ Read the complete error message
2. ✅ Reproduce the failure locally
3. ✅ Run only the failing test in isolation
4. ✅ Add diagnostic output to understand state
5. ✅ Check for environment differences (CI vs local)
6. ✅ Verify test isolation (no shared state)
7. ✅ Check for timing/race conditions
8. ✅ Validate test setup/teardown
9. ✅ Review recent code changes
10. ✅ Consider flaky test patterns

### When to use this skill

- Tests fail in CI but pass locally (or vice versa)
- Intermittent test failures (flaky tests)
- Tests hang or timeout
- Unexpected test output or behavior
- Mock or assertion issues
- Need to improve test reliability
- Performance issues in test suites
