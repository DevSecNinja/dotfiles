# Dotfiles Test Suite

Comprehensive test suite for validating dotfiles configurations, scripts, and utilities across multiple platforms and languages.

## Directory Structure

```
tests/
├── powershell/      # Pester tests for PowerShell scripts
├── bash/            # Bats tests for Bash scripts ✨
├── python/          # Tests for Python utilities (future)
└── README.md        # This file
```

## Test Types

### PowerShell Tests (Pester)

**Location**: `tests/powershell/`

**Framework**: [Pester 5.x](https://pester.dev/)

**Coverage**:
- PowerShell utility scripts
- **Packages YAML validation** (cross-platform package configuration) ✨
- Code signing certificate generation (`New-SigningCert.ps1.tmpl`)
- Script signing workflows (`Sign-PowerShellScripts.ps1.tmpl`)
- End-to-end certificate creation and signing validation
- CI/CD pipeline validation

**Run locally**:
```powershell
# Using the test runner script (recommended)
.\tests\powershell\Invoke-PesterTests.ps1

# With specific tags
.\tests\powershell\Invoke-PesterTests.ps1 -Tag "E2E"

# Exclude specific tags
.\tests\powershell\Invoke-PesterTests.ps1 -ExcludeTag "Integration"

# Or directly with Pester
Invoke-Pester -Path ./tests/powershell

# Run with detailed output
Invoke-Pester -Path ./tests/powershell -Output Detailed

# Run specific tests by tag
Invoke-Pester -Path ./tests/powershell -Tag "E2E"
Invoke-Pester -Path ./tests/powershell -Tag "Pipeline"
```

### Bash Tests (Bats)

**Location**: `tests/bash/`

**Framework**: [Bats 1.13+](https://github.com/bats-core/bats-core)

**Coverage**:
- Shell function utilities (`find-broken-symlinks`, `git-https-to-ssh`, etc.)
- **Configuration validation** (Chezmoi, Fish, shell scripts) ✨
- **Dotfiles verification** (applied files existence) ✨
- **Integration tests** (Chezmoi apply dry-run, Fish loading) ✨
- Interactive command behavior
- File system operations
- Error handling and edge cases

**Test Files** (utility functions):
- `brewup.bats` - Tests Homebrew update/upgrade wrapper
- `file-set-execution-bit.bats` - Tests shell script executable bit management
- `find-broken-symlinks.bats` - Tests broken symlink detection and cleanup
- `get-external-ip.bats` - Tests external IP detection function ✨
- `get-internal-ip.bats` - Tests internal IP detection function ✨
- `gh-add-ssh-keys.bats` - Tests GitHub SSH key management
- `gh-check-ssh-keys.bats` - Tests GitHub SSH key verification
- `gh-env-var.bats` - Tests GitHub environment variable utilities
- `gh-ssh-keys-integration.bats` - Integration tests for GitHub SSH workflows
- `git-https-to-ssh.bats` - Tests Git remote URL conversion

**Test Files** (validation & integration):
- `validate-chezmoi.bats` - Validates Chezmoi configuration syntax
- `validate-shell-scripts.bats` - Validates all shell script syntax
- `validate-fish-config.bats` - Validates Fish configuration files
- `test-chezmoi-apply.bats` - Tests Chezmoi apply in dry-run mode
- `test-clean-shell-startup.bats` - Tests shell startup performance
- `test-entra-id-parsing.bats` - Tests Entra ID user parsing
- `test-fish-config.bats` - Tests Fish shell configuration loading
- `test-git-config-windows.bats` - Tests Git configuration on Windows
- `test-shell-startup-logic.bats` - Tests shell initialization logic
- `verify-dotfiles.bats` - Verifies applied dotfiles exist

**Run locally**:
```bash
# Using the test runner script (recommended)
./tests/bash/run-tests.sh

# In CI mode (installs dependencies automatically)
./tests/bash/run-tests.sh --ci

# Or directly with Bats
bats tests/bash/

# Run with TAP output to file
bats --tap tests/bash/*.bats > results.tap

# Run a specific test file
bats tests/bash/find-broken-symlinks.bats
```

**Test features**:
- Comprehensive coverage of all function options (--dry-run, --yes, --verbose)
- Edge cases (special characters, nested directories, mixed symlinks)
- Error conditions (nonexistent directories, permission issues)
- Output validation and behavior verification

**Validation tests** (new):
- `validate-chezmoi.bats` - Validates Chezmoi configuration syntax and structure
- `validate-shell-scripts.bats` - Checks all shell scripts for syntax errors
- `validate-fish-config.bats` - Validates Fish configuration files
- `test-chezmoi-apply.bats` - Tests Chezmoi apply in dry-run mode
- `test-fish-config.bats` - Tests Fish shell loading with repository config
- `verify-dotfiles.bats` - Verifies expected dotfiles exist after apply

### Python Tests (Future)

**Location**: `tests/python/`

**Planned Framework**: [pytest](https://pytest.org/)

**Planned Coverage**:
- Python utilities
- Validation scripts
- Configuration helpers

## CI/CD Integration

All tests run automatically in GitHub Actions on every push and pull request.

### GitHub Actions Jobs

1. **validate** - Pre-commit hooks and static validation
2. **test-install** - Installation workflow tests (Ubuntu)
3. **test-light-server** - Light mode installation
4. **test-dev-server** - Full mode installation
5. **test-windows** - Windows installation and configuration
6. **test-bash-scripts** - Bash Bats tests ✨
7. **test-powershell-scripts** - PowerShell Pester tests ✨

### Test Execution

The CI pipeline:
- Uses dedicated test runner scripts for each language:
  - PowerShell: `tests/powershell/Invoke-PesterTests.ps1`
  - Bash: `tests/bash/run-tests.sh` ✨
  - Python: (future) `tests/python/run-tests.sh`
- Automatically discovers all test files matching patterns:
  - PowerShell: `tests/powershell/**/*.Tests.ps1`
  - Bash: `tests/bash/**/*.bats` ✨
  - Python: `tests/python/**/test_*.py` (future)
- Runs tests with appropriate runners/frameworks
- Uploads test results as artifacts
- Fails the build if any tests fail

### Viewing Results

**Test Artifacts**:
1. Go to [Actions](../../actions) tab in GitHub
2. Click on the latest workflow run
3. Download test result artifacts:
   - `bats-test-results` - Bash test results (TAP format) ✨
   - `pester-test-results` - PowerShell test results (NUnit XML)

**Test Summary**:
- Displayed in workflow run logs
- Shows pass/fail/skip counts
- Includes detailed output for failures

## Adding New Tests

### PowerShell (Pester)

1. Create a new file in `tests/powershell/` with `.Tests.ps1` suffix:
   ```powershell
   # tests/powershell/MyFeature.Tests.ps1
   Describe "My Feature" {
       It "Should work correctly" {
           $result = Test-MyFeature
           $result | Should -Be $expected
       }
   }
   ```

2. The CI pipeline will automatically discover and run it!

### Bash (Bats)

1. Create a new file in `tests/bash/` with `.bats` suffix:
   ```bash
   # tests/bash/my-function.bats
   #!/usr/bin/env bats

   setup() {
       # Load the function
       load "../../home/dot_config/shell/functions/my-function.sh"

       # Create temp directory
       TEST_DIR="$(mktemp -d)"
       export TEST_DIR
   }

   teardown() {
       # Cleanup
       rm -rf "$TEST_DIR"
   }

   @test "my-function: basic functionality" {
       run my-function --help
       [ "$status" -eq 0 ]
       [[ "$output" =~ "Usage" ]]
   }
   ```

2. The CI pipeline will automatically discover and run it!

3. Run locally with: `./tests/bash/run-tests.sh`

### Python (Future)

1. Create test files with `test_*.py` prefix in `tests/python/`
2. Follow pytest conventions
3. Update CI pipeline to run pytest

## Test Organization Best Practices

### Naming Conventions

- **PowerShell**: `<Feature>.Tests.ps1` (e.g., `New-SigningCert.Tests.ps1`)
- **Bash**: `<feature>.bats` (e.g., `find-broken-symlinks.bats`) ✨
- **Python**: `test_<feature>.py` (e.g., `test_validation.py`)

### Test Tags

Use tags to organize and filter tests:

**PowerShell Tags**:
- `Platform` - Platform/environment checks
- `Integration` - Integration tests that create resources
- `E2E` - End-to-end workflow tests
- `Security` - Security-related validations
- `Pipeline` - CI/CD pipeline-specific tests

**Example**:
```powershell
Describe "My Feature" -Tag "Integration", "Security" {
    It "Should be secure" { ... }
}
```

### Cleanup

Always clean up resources created during tests:

```powershell
BeforeAll {
    # Setup
}

AfterAll {
    # Cleanup
}
```

### Platform-Specific Tests

Skip tests on unsupported platforms:

```powershell
It "Windows-only feature" -Skip:(-not $IsWindows) {
    # Test code
}
```

## Local Development

### Running All Tests

```bash
# From repository root
cd /workspaces/dotfiles

# Bash tests (using test runner) ✨
./tests/bash/run-tests.sh

# Bash tests (direct Bats invocation) ✨
bats tests/bash/*.bats

# PowerShell tests (using test runner)
pwsh -Command ".\tests\powershell\Invoke-PesterTests.ps1"

# PowerShell tests (direct Pester invocation)
pwsh -c "Invoke-Pester -Path ./tests/powershell"

# Future: Python tests
# ./tests/python/run-tests.sh
```

### Running Specific Tests

```bash
# Bash - Single test file ✨
bats tests/bash/find-broken-symlinks.bats

# Bash - Specific test by name ✨
bats tests/bash/find-broken-symlinks.bats --filter "help option"

# PowerShell - Single test file
Invoke-Pester -Path ./tests/powershell/New-SigningCert.Tests.ps1

# PowerShell - Using test runner with tags
.\tests\powershell\Invoke-PesterTests.ps1 -Tag "E2E"

# PowerShell - By tag (direct Pester)
Invoke-Pester -Path ./tests/powershell -Tag "E2E"

# PowerShell - Exclude tags
.\tests\powershell\Invoke-PesterTests.ps1 -ExcludeTag "Integration"
```

### Test Coverage

```powershell
# Generate code coverage report (PowerShell)
$config = New-PesterConfiguration
$config.Run.Path = './tests/powershell'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './home/dot_config/powershell/scripts/*.ps1'
Invoke-Pester -Configuration $config
```

## Troubleshooting

### PowerShell Tests Fail Locally

1. **Check Pester version**:
   ```powershell
   Get-Module Pester -ListAvailable
   ```
   Should be 5.0.0 or later.

2. **Update Pester**:
   ```powershell
   Install-Module -Name Pester -Force -SkipPublisherCheck -AllowClobber
   ```

3. **Run with verbose output**:
   ```powershell
   Invoke-Pester -Path ./tests/powershell -Output Detailed
   ```

### Tests Skip on Non-Windows

Many PowerShell tests require Windows (certificate operations). This is expected.

### CI Pipeline Doesn't Find Tests

1. Ensure test files follow naming conventions
2. Verify files are committed to git
3. Check test directory structure matches expectations

## Resources

- [Pester Documentation](https://pester.dev/)
- [Bats Core](https://github.com/bats-core/bats-core)
- [pytest Documentation](https://docs.pytest.org/)
- [GitHub Actions - Running Tests](https://docs.github.com/en/actions/automating-builds-and-tests)
