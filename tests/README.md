# Dotfiles Test Suite

Comprehensive test suite for validating dotfiles configurations, scripts, and utilities across multiple platforms and languages.

## Directory Structure

```
tests/
├── powershell/      # Pester tests for PowerShell scripts
├── bash/            # Tests for Bash scripts (future)
├── python/          # Tests for Python utilities (future)
└── README.md        # This file
```

## Test Types

### PowerShell Tests (Pester)

**Location**: `tests/powershell/`

**Framework**: [Pester 5.x](https://pester.dev/)

**Coverage**:
- PowerShell utility scripts
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

### Bash Tests (Future)

**Location**: `tests/bash/`

**Planned Framework**: [Bats](https://github.com/bats-core/bats-core) or similar

**Planned Coverage**:
- Shell script utilities
- Installation scripts
- Environment setup scripts

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
6. **test-powershell-scripts** - PowerShell Pester tests ✨

### Test Execution

The CI pipeline:
- Uses dedicated test runner scripts for each language:
  - PowerShell: `tests/powershell/Invoke-PesterTests.ps1`
  - Bash: (future) `tests/bash/run-tests.sh`
  - Python: (future) `tests/python/run-tests.sh`
- Automatically discovers all test files matching patterns:
  - PowerShell: `tests/powershell/**/*.Tests.ps1`
  - Bash: `tests/bash/**/*.bats` (future)
  - Python: `tests/python/**/test_*.py` (future)
- Runs tests with appropriate runners/frameworks
- Uploads test results as artifacts
- Fails the build if any tests fail

### Viewing Results

**Test Artifacts**:
1. Go to [Actions](../../actions) tab in GitHub
2. Click on the latest workflow run
3. Download test result artifacts:
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

### Bash (Future)

1. Create test files with `.bats` extension in `tests/bash/`
2. Follow Bats syntax
3. Update CI pipeline to run Bats tests

### Python (Future)

1. Create test files with `test_*.py` prefix in `tests/python/`
2. Follow pytest conventions
3. Update CI pipeline to run pytest

## Test Organization Best Practices

### Naming Conventions

- **PowerShell**: `<Feature>.Tests.ps1` (e.g., `New-SigningCert.Tests.ps1`)
- **Bash**: `<feature>.bats` (e.g., `install.bats`)
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
cd /workspaces/dotfiles-new

# PowerShell tests (using test runner)
pwsh -Command ".\tests\powershell\Invoke-PesterTests.ps1"

# PowerShell tests (direct Pester invocation)
pwsh -c "Invoke-Pester -Path ./tests/powershell"

# Future: Bash tests
# ./tests/bash/run-tests.sh

# Future: Python tests
# ./tests/python/run-tests.sh
```

### Running Specific Tests

```powershell
# Single test file
Invoke-Pester -Path ./tests/powershell/New-SigningCert.Tests.ps1

# Using test runner with tags
.\tests\powershell\Invoke-PesterTests.ps1 -Tag "E2E"

# By tag (direct Pester)
Invoke-Pester -Path ./tests/powershell -Tag "E2E"

# Exclude tags
.\tests\powershell\Invoke-PesterTests.ps1 -ExcludeTag "Integration"
```

### Test Coverage

```powershell
# Generate code coverage report (PowerShell)
$config = New-PesterConfiguration
$config.Run.Path = './tests/powershell'
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './dot_local/private_bin/scripts/powershell/*.ps1'
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
