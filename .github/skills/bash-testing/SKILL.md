---
name: bash-testing
description: Bash and shell script testing with Bats framework. Use this when writing or debugging Bash/shell script tests.
---

# Bash Testing with Bats

This skill provides expertise in testing Bash and shell scripts using the Bats (Bash Automated Testing System) framework.

## Bats Testing Framework

Bats is a TAP-compliant testing framework for Bash that provides a simple way to verify Unix programs behave as expected.

### Test Structure

Basic Bats test structure:

```bash
#!/usr/bin/env bats

@test "description of test" {
    # Test commands here
    run command-to-test
    [ "$status" -eq 0 ]
    [ "$output" = "expected output" ]
}
```

### The `run` Command

The `run` command executes the specified command and captures:
- `$status` - Exit status code
- `$output` - Combined stdout and stderr
- `${lines[@]}` - Array of output lines

```bash
@test "command succeeds" {
    run echo "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
    [ "${lines[0]}" = "hello world" ]
}
```

### Basic Assertions

Standard test assertions using `[ ]` or `[[ ]]`:

```bash
# Exit status
[ "$status" -eq 0 ]        # Success
[ "$status" -ne 0 ]        # Failure

# String comparisons
[ "$output" = "exact" ]     # Exact match
[ "$output" != "other" ]    # Not equal
[[ "$output" =~ regex ]]    # Regex match

# String checks
[ -z "$output" ]            # Empty string
[ -n "$output" ]            # Non-empty string

# Numeric comparisons
[ "$count" -eq 5 ]          # Equal
[ "$count" -gt 0 ]          # Greater than
[ "$count" -lt 10 ]         # Less than
[ "$count" -ge 5 ]          # Greater or equal
[ "$count" -le 10 ]         # Less or equal

# File checks
[ -f "$file" ]              # File exists
[ -d "$dir" ]               # Directory exists
[ -x "$script" ]            # File is executable
[ -r "$file" ]              # File is readable
```

### Helper Libraries

#### bats-support

Provides additional testing helpers:

```bash
load 'test_helper/bats-support/load'

@test "with better assertions" {
    run false
    assert_failure
}
```

#### bats-assert

Provides readable assertion functions:

```bash
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "with assert helpers" {
    run echo "hello world"
    assert_success
    assert_output "hello world"
    assert_line "hello world"
}
```

Common assertions:
- `assert_success` - Status is 0
- `assert_failure` - Status is non-zero
- `assert_equal` - Values are equal
- `assert_output` - Output matches string or pattern
- `assert_line` - Specific line matches
- `refute_output` - Output does not match

### Setup and Teardown

```bash
setup() {
    # Runs before each test
    export TEST_VAR="value"
    mkdir -p "$BATS_TEST_TMPDIR/test-dir"
}

teardown() {
    # Runs after each test
    rm -rf "$BATS_TEST_TMPDIR/test-dir"
}

setup_file() {
    # Runs once before all tests in file
    export GLOBAL_CONFIG="value"
}

teardown_file() {
    # Runs once after all tests in file
    # Cleanup shared resources
}
```

### Environment Variables

Bats provides several useful variables:

- `$BATS_TEST_FILENAME` - Path to test file
- `$BATS_TEST_DIRNAME` - Directory of test file
- `$BATS_TEST_TMPDIR` - Temporary directory for test
- `$BATS_TEST_NAME` - Name of current test
- `$BATS_TEST_NUMBER` - Number of current test

```bash
@test "using bats variables" {
    cd "$BATS_TEST_DIRNAME/.."
    run ./script.sh
    assert_success
}
```

## Testing Best Practices

### Test Organization

```bash
#!/usr/bin/env bats

# Load helpers at top
load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Group related tests with descriptive names
@test "function: validates input correctly" {
    run validate_input "valid"
    assert_success
}

@test "function: rejects invalid input" {
    run validate_input "invalid"
    assert_failure
}
```

### Testing Exit Codes

```bash
@test "script exits with 0 on success" {
    run ./script.sh --flag
    [ "$status" -eq 0 ]
}

@test "script exits with 1 on error" {
    run ./script.sh --invalid
    [ "$status" -eq 1 ]
}

@test "script exits with specific code" {
    run ./script.sh --not-found
    [ "$status" -eq 127 ]
}
```

### Testing Output

```bash
@test "output contains expected text" {
    run ./script.sh
    [[ "$output" =~ "Success" ]]
}

@test "output matches exactly" {
    run echo "hello"
    [ "$output" = "hello" ]
}

@test "specific line matches" {
    run ./script.sh
    [ "${lines[0]}" = "First line" ]
    [ "${lines[1]}" = "Second line" ]
}

@test "output contains substring" {
    run ./script.sh
    [[ "$output" == *"substring"* ]]
}
```

### Testing Files and Directories

```bash
@test "script creates expected file" {
    run ./script.sh create test.txt
    [ "$status" -eq 0 ]
    [ -f test.txt ]
    [ -r test.txt ]
}

@test "script creates directory structure" {
    run ./script.sh setup
    [ -d "output/subdir" ]
    [ -x "output/script.sh" ]
}

@test "file contains expected content" {
    ./script.sh generate > output.txt
    run cat output.txt
    [[ "$output" =~ "expected content" ]]
}
```

### Testing Functions

Source the script and test functions directly:

```bash
@test "function returns expected value" {
    source ./script.sh
    run my_function "input"
    [ "$status" -eq 0 ]
    [ "$output" = "expected" ]
}

@test "function handles edge case" {
    source ./script.sh
    run my_function ""
    [ "$status" -eq 1 ]
}
```

### Skipping Tests

```bash
@test "work in progress test" {
    skip "Not yet implemented"
    run ./new-feature.sh
    assert_success
}

@test "platform-specific test" {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        skip "Linux only test"
    fi
    run ./linux-specific.sh
    assert_success
}
```

### Testing with Mock Data

```bash
setup() {
    # Create mock data
    mkdir -p "$BATS_TEST_TMPDIR/mock"
    echo "test data" > "$BATS_TEST_TMPDIR/mock/file.txt"
}

@test "processes mock data" {
    run ./script.sh "$BATS_TEST_TMPDIR/mock/file.txt"
    assert_success
    assert_output --partial "test data"
}
```

## Running Tests

### Basic Execution

```bash
# Run all tests in directory
bats tests/

# Run specific test file
bats tests/test-script.bats

# Run multiple files
bats tests/test-1.bats tests/test-2.bats

# Verbose output
bats --verbose tests/
```

### Formatting Output

```bash
# TAP output (default)
bats tests/

# Pretty output
bats --pretty tests/

# Timing information
bats --timing tests/

# JUnit XML for CI
bats --formatter junit tests/ > test-results.xml
```

### Filtering Tests

```bash
# Run tests matching pattern
bats --filter "function name" tests/

# Count tests without running
bats --count tests/
```

### Parallel Execution

```bash
# Run tests in parallel (faster)
bats --jobs 4 tests/

# Run with GNU parallel
find tests -name '*.bats' | parallel -j 4 bats
```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Run Bats tests
  run: |
    # Install bats-core
    npm install -g bats

    # Run tests with CI-friendly output
    bats --formatter junit tests/ > test-results.xml
```

### Shell Script Validation

Combine with shellcheck for comprehensive validation:

```bash
@test "shellcheck passes" {
    if ! command -v shellcheck &> /dev/null; then
        skip "shellcheck not installed"
    fi

    run shellcheck script.sh
    assert_success
}

@test "script has correct shebang" {
    run head -n1 script.sh
    assert_output "#!/usr/bin/env bash"
}

@test "script is executable" {
    [ -x script.sh ]
}
```

## Common Patterns

### Testing Error Messages

```bash
@test "displays helpful error message" {
    run ./script.sh --invalid
    assert_failure
    assert_output --partial "Error: Invalid option"
}
```

### Testing Command Availability

```bash
@test "requires git command" {
    if ! command -v git &> /dev/null; then
        skip "git not installed"
    fi

    run ./git-script.sh
    assert_success
}
```

### Testing with stdin

```bash
@test "accepts stdin" {
    echo "input data" | run ./script.sh -
    assert_success
    assert_output --partial "input data"
}
```

### Testing Environment Variables

```bash
@test "respects environment variable" {
    DEBUG=true run ./script.sh
    assert_output --partial "Debug mode"
}
```

## Debugging Tests

```bash
# Print output for debugging
@test "debug failing test" {
    run ./script.sh
    echo "Status: $status"
    echo "Output: $output"
    [ "$status" -eq 0 ]
}

# Use set -x for tracing
@test "trace execution" {
    set -x
    run ./script.sh
    set +x
    assert_success
}
```

## Quick Reference

### When to use this skill

- Writing new Bats tests for shell scripts
- Debugging failing Bats tests
- Testing Bash functions and shell utilities
- Validating script behavior and exit codes
- Setting up shell script test infrastructure
- Integrating Bats tests into CI/CD pipelines
