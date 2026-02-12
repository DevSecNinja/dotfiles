---
name: test-coverage
description: Test coverage analysis and strategies for comprehensive testing. Use this when improving test coverage or analyzing what tests are missing.
---

# Test Coverage and Comprehensive Testing

This skill provides guidance on analyzing test coverage, identifying gaps, and creating comprehensive test suites.

## Understanding Test Coverage

Test coverage measures how much of your code is executed during testing. While 100% coverage doesn't guarantee bug-free code, it helps identify untested paths.

### Types of Coverage

**Line Coverage:** Percentage of code lines executed
**Branch Coverage:** Percentage of decision branches (if/else) taken
**Function Coverage:** Percentage of functions called
**Statement Coverage:** Percentage of statements executed

## PowerShell Coverage with Pester

### Basic Coverage Collection

```powershell
# Run tests with coverage
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = './src/*.ps1'
$config.Run.Path = './tests/'

$result = Invoke-Pester -Configuration $config

# View coverage summary
$result.CodeCoverage
```

### Detailed Coverage Analysis

```powershell
# Get coverage for specific files
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = @(
    './src/Module.ps1'
    './src/Functions/*.ps1'
)
$config.CodeCoverage.OutputFormat = 'JaCoCo'
$config.CodeCoverage.OutputPath = 'coverage.xml'

$result = Invoke-Pester -Configuration $config

# Analyze missed commands
$result.CodeCoverage.MissedCommands | Format-Table File, Line, Command
```

### Coverage Thresholds

```powershell
# Fail if coverage below threshold
$result = Invoke-Pester -Configuration $config

$coveragePercent = ($result.CodeCoverage.CommandsExecutedCount /
                    $result.CodeCoverage.CommandsAnalyzedCount) * 100

if ($coveragePercent -lt 80) {
    throw "Coverage is $coveragePercent%, minimum is 80%"
}
```

## Bash Coverage Analysis

Bash doesn't have built-in coverage tools, but you can use alternative approaches:

### Using kcov

```bash
# Install kcov (Linux)
# apt-get install kcov

# Run tests with coverage
kcov --exclude-pattern=/usr/share coverage/ bats tests/

# View coverage report
xdg-open coverage/index.html
```

### Manual Coverage Tracking

```bash
# Track which functions are tested
@test "coverage: function_name is tested" {
    source ./script.sh
    run function_name
    [ "$status" -eq 0 ]
}

# Document untested paths
@test "coverage: error path not tested" {
    skip "TODO: test error handling when file doesn't exist"
}
```

## Identifying Coverage Gaps

### Review Uncovered Lines

```powershell
# PowerShell - List uncovered code
$result = Invoke-Pester -Configuration $config
foreach ($missed in $result.CodeCoverage.MissedCommands) {
    Write-Host "Missed: $($missed.File):$($missed.Line) - $($missed.Command)"
}
```

### Common Uncovered Patterns

**Error handling paths:**
```powershell
# Often uncovered
try {
    Get-Content $Path
}
catch {
    Write-Error "File not found"  # Test this path
    exit 1
}
```

**Edge cases:**
```powershell
# Empty input
It "handles empty input" {
    { Get-Function -Items @() } | Should -Not -Throw
}

# Null input
It "handles null input" {
    { Get-Function -Items $null } | Should -Throw
}

# Maximum values
It "handles large numbers" {
    $result = Calculate -Value ([int]::MaxValue)
    $result | Should -BeGreaterThan 0
}
```

**Conditional branches:**
```bash
@test "if branch: condition true" {
    CONDITION=true run ./script.sh
    [ "$status" -eq 0 ]
}

@test "else branch: condition false" {
    CONDITION=false run ./script.sh
    [ "$status" -eq 1 ]
}
```

## Comprehensive Testing Strategy

### Test Pyramid

```
           /\
          /  \     E2E Tests (few, slow, expensive)
         /    \
        /------\
       / Integ  \   Integration Tests (moderate)
      /  Tests   \
     /------------\
    /   Unit       \ Unit Tests (many, fast, cheap)
   /     Tests      \
  /------------------\
```

### Unit Test Coverage Checklist

**For each function/cmdlet:**
- ✅ Happy path (normal input, expected output)
- ✅ Empty input
- ✅ Null input
- ✅ Invalid input types
- ✅ Boundary values (min, max, zero, negative)
- ✅ Error conditions
- ✅ Edge cases
- ✅ Return value validation
- ✅ Side effects (file creation, state changes)
- ✅ Pipeline input (PowerShell)

### Example: Comprehensive Function Tests

```powershell
Describe "Get-UserAge" {
    Context "Valid input" {
        It "calculates age for birth year" {
            Get-UserAge -BirthYear 2000 | Should -Be 26
        }

        It "handles current year birth" {
            Get-UserAge -BirthYear 2026 | Should -Be 0
        }
    }

    Context "Boundary values" {
        It "handles minimum year 1900" {
            Get-UserAge -BirthYear 1900 | Should -Be 126
        }

        It "handles maximum year (current)" {
            $currentYear = (Get-Date).Year
            Get-UserAge -BirthYear $currentYear | Should -Be 0
        }
    }

    Context "Invalid input" {
        It "throws on future year" {
            { Get-UserAge -BirthYear 2050 } | Should -Throw
        }

        It "throws on year before 1900" {
            { Get-UserAge -BirthYear 1800 } | Should -Throw
        }

        It "throws on negative year" {
            { Get-UserAge -BirthYear -100 } | Should -Throw
        }
    }

    Context "Edge cases" {
        It "handles leap year birth" {
            Mock Get-Date { [datetime]"2026-02-28" }
            Get-UserAge -BirthYear 2000 -BirthMonth 2 -BirthDay 29 |
                Should -Be 26
        }
    }
}
```

```bash
@test "get_user_age: valid input" {
    source ./functions.sh
    run get_user_age 2000
    [ "$status" -eq 0 ]
    [ "$output" = "26" ]
}

@test "get_user_age: current year" {
    source ./functions.sh
    run get_user_age 2026
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "get_user_age: future year" {
    source ./functions.sh
    run get_user_age 2050
    [ "$status" -eq 1 ]
    [[ "$output" =~ "error" ]]
}

@test "get_user_age: negative year" {
    source ./functions.sh
    run get_user_age -100
    [ "$status" -eq 1 ]
}
```

## Integration Test Coverage

Integration tests verify multiple components work together:

```powershell
Describe "User workflow integration" {
    It "creates, retrieves, and deletes user" {
        # Create
        $user = New-User -Name "Test" -Email "test@example.com"
        $user.Id | Should -Not -BeNullOrEmpty

        # Retrieve
        $retrieved = Get-User -Id $user.Id
        $retrieved.Name | Should -Be "Test"

        # Delete
        Remove-User -Id $user.Id
        { Get-User -Id $user.Id } | Should -Throw
    }
}
```

```bash
@test "integration: full deployment workflow" {
    # Setup
    run ./setup.sh
    [ "$status" -eq 0 ]

    # Deploy
    run ./deploy.sh test.conf
    [ "$status" -eq 0 ]
    [ -f "deployed.flag" ]

    # Verify
    run ./verify.sh
    [ "$status" -eq 0 ]

    # Cleanup
    run ./cleanup.sh
    [ "$status" -eq 0 ]
}
```

## E2E Test Coverage

E2E tests verify entire workflows from user perspective:

```powershell
Describe "E2E: Complete user journey" {
    BeforeAll {
        # Setup complete environment
        Start-TestEnvironment
    }

    It "completes full user registration flow" {
        # User visits site
        $response = Invoke-WebRequest "http://localhost:8080"
        $response.StatusCode | Should -Be 200

        # Registers account
        $result = Register-User -Email "new@example.com" -Password "secure"
        $result.Success | Should -Be $true

        # Receives confirmation email
        $email = Get-TestEmail -To "new@example.com"
        $email.Subject | Should -Match "Welcome"

        # Logs in
        $session = Connect-User -Email "new@example.com" -Password "secure"
        $session.Authenticated | Should -Be $true
    }

    AfterAll {
        Stop-TestEnvironment
    }
}
```

## Coverage Reports in CI

### GitHub Actions Integration

```yaml
- name: Run tests with coverage
  run: |
    $config = New-PesterConfiguration
    $config.CodeCoverage.Enabled = $true
    $config.CodeCoverage.Path = './src/**/*.ps1'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
    $config.CodeCoverage.OutputPath = 'coverage.xml'
    $config.TestResult.Enabled = $true
    Invoke-Pester -Configuration $config
  shell: pwsh

- name: Upload coverage to Codecov
  uses: codecov/codecov-action@v4
  with:
    file: ./coverage.xml

- name: Coverage threshold check
  run: |
    $result = Invoke-Pester -Configuration $config
    $coverage = ($result.CodeCoverage.CommandsExecutedCount /
                 $result.CodeCoverage.CommandsAnalyzedCount) * 100
    if ($coverage -lt 80) {
      Write-Error "Coverage $coverage% is below 80% threshold"
      exit 1
    }
  shell: pwsh
```

## Improving Low Coverage

### Prioritize Coverage Efforts

1. **Critical paths first:** Authentication, payment processing, data integrity
2. **Bug-prone areas:** Complex logic, error handling, edge cases
3. **Frequently changed code:** Areas with high churn
4. **Public APIs:** Functions exposed to users

### Refactoring for Testability

**Before (hard to test):**
```powershell
function Process-Data {
    $data = Invoke-RestAPI "http://api.example.com/data"
    $result = $data | Where-Object { $_.Active }
    Write-ToDatabase $result
}
```

**After (testable):**
```powershell
function Process-Data {
    param(
        [Parameter()]
        [object[]]$InputData = (Get-APIData),

        [Parameter()]
        [scriptblock]$OutputHandler = { param($data) Write-ToDatabase $data }
    )

    $result = $InputData | Where-Object { $_.Active }
    & $OutputHandler $result
}

# Now testable
It "filters active data" {
    $testData = @(
        @{Active=$true; Name="A"}
        @{Active=$false; Name="B"}
    )

    $output = @()
    Process-Data -InputData $testData -OutputHandler {
        param($data) $script:output = $data
    }

    $output.Count | Should -Be 1
    $output[0].Name | Should -Be "A"
}
```

## Coverage Metrics Dashboard

Track coverage over time:

```powershell
# Generate coverage report
$result = Invoke-Pester -Configuration $config

$report = @{
    Date = Get-Date -Format "yyyy-MM-dd"
    TotalCommands = $result.CodeCoverage.CommandsAnalyzedCount
    CoveredCommands = $result.CodeCoverage.CommandsExecutedCount
    CoveragePercent = [math]::Round(
        ($result.CodeCoverage.CommandsExecutedCount /
         $result.CodeCoverage.CommandsAnalyzedCount) * 100, 2)
    TestCount = $result.TotalCount
    PassedTests = $result.PassedCount
}

$report | Export-Csv -Path "coverage-history.csv" -Append
```

## Quick Reference

### When to use this skill
- Analyzing current test coverage levels
- Identifying untested code paths
- Planning comprehensive test suites
- Setting up coverage reporting in CI
- Improving low coverage areas
- Deciding what tests to write next
- Ensuring critical paths are tested
- Refactoring code for better testability
