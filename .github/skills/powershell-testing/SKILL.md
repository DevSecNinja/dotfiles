---
name: powershell-testing
description: PowerShell testing with Pester framework and PSScriptAnalyzer. Use this when writing or debugging PowerShell tests, or when analyzing PowerShell code quality.
---

# PowerShell Testing with Pester and PSScriptAnalyzer

This skill provides expertise in PowerShell testing using the Pester framework and code quality analysis with PSScriptAnalyzer.

## Pester Testing Framework

### Test Structure

Use the standard Pester structure with `Describe`, `Context`, and `It` blocks:

```powershell
Describe "FunctionName" {
    Context "When specific condition exists" {
        It "Should produce expected behavior" {
            # Arrange
            $expected = "value"

            # Act
            $result = FunctionName -Parameter "value"

            # Assert
            $result | Should -Be $expected
        }
    }
}
```

### Setup and Teardown

Use lifecycle hooks for test setup and cleanup:

```powershell
BeforeAll {
    # Runs once before all tests in the block
    . $PSScriptRoot/../script.ps1
}

BeforeEach {
    # Runs before each test
    $testData = @{ Key = "Value" }
}

AfterEach {
    # Runs after each test
    Remove-Item -Path $testPath -ErrorAction SilentlyContinue
}

AfterAll {
    # Runs once after all tests in the block
    # Cleanup resources
}
```

### Pester Assertions

Common assertion patterns:

- `Should -Be` - Exact equality
- `Should -BeExactly` - Case-sensitive string equality
- `Should -Match` - Regex pattern matching
- `Should -Contain` - Collection contains item
- `Should -BeNullOrEmpty` - Null or empty check
- `Should -Throw` - Exception testing
- `Should -Exist` - File/path existence
- `Should -BeOfType` - Type checking
- `Should -Invoke` - Mock verification (with `-Times`, `-Exactly`, `-ParameterFilter`)

### Mocking

Mock external dependencies to isolate tests:

```powershell
BeforeAll {
    Mock Get-Content { return "mocked content" }

    Mock Get-ChildItem {
        return @(
            [PSCustomObject]@{ Name = "file1.txt"; Length = 100 }
        )
    } -ParameterFilter { $Path -eq "C:\temp" }
}

It "Should call Get-Content" {
    $result = Get-SomeData
    Should -Invoke Get-Content -Times 1 -Exactly
}
```

### Test Organization

- Name test files with `.Tests.ps1` suffix
- Group related tests in the same `Describe` block
- Use `Context` to group tests by scenario or condition
- Keep test names descriptive and action-oriented
- One assertion per `It` block when possible

## PSScriptAnalyzer Best Practices

PSScriptAnalyzer is a static code analyzer that enforces PowerShell best practices and catches common issues.

### Running PSScriptAnalyzer

```powershell
# Analyze a single file
Invoke-ScriptAnalyzer -Path script.ps1

# Analyze recursively with severity filter
Invoke-ScriptAnalyzer -Path . -Recurse -Severity Error,Warning

# Use specific rules
Invoke-ScriptAnalyzer -Path script.ps1 -IncludeRule PSAvoidUsingPositionalParameters
```

### Critical Rules to Follow

**PSAvoidUsingPositionalParameters**
```powershell
# Bad
Get-ChildItem C:\temp *.txt

# Good
Get-ChildItem -Path C:\temp -Filter *.txt
```

**PSUseShouldProcessForStateChangingFunctions**
```powershell
function Remove-CustomItem {
    [CmdletBinding(SupportsShouldProcess)]
    param($Path)

    if ($PSCmdlet.ShouldProcess($Path, "Remove")) {
        Remove-Item -Path $Path
    }
}
```

**PSAvoidUsingCmdletAliases**
```powershell
# Bad
gci | ? { $_.Length -gt 1MB } | % { $_.Name }

# Good
Get-ChildItem | Where-Object { $_.Length -gt 1MB } | ForEach-Object { $_.Name }
```

**PSUseDeclaredVarsMoreThanAssignments**
- Ensure variables are used after assignment
- Remove unused variables

**PSAvoidUsingWriteHost**
```powershell
# Bad - can't be captured or redirected
Write-Host "Information"

# Good - proper output streams
Write-Output "Information"    # Success stream
Write-Error "Error message"   # Error stream
Write-Warning "Warning"       # Warning stream
Write-Verbose "Details"       # Verbose stream
```

**PSAvoidUsingPlainTextForPassword**
```powershell
# Bad
param([string]$Password)

# Good
param([SecureString]$Password)
```

### Cmdlet Development Guidelines

Follow Microsoft's official cmdlet development guidelines from https://learn.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-development-guidelines

**Naming Conventions:**
- Use approved verbs: Get, Set, New, Remove, Add, Clear, etc.
- Use singular nouns: `Get-Process`, not `Get-Processes`
- Follow Verb-Noun pattern

**Parameter Guidelines:**
- Use `[CmdletBinding()]` for advanced functions
- Support common parameters via `[CmdletBinding()]`
- Use `[Parameter()]` attributes to define required/optional parameters
- Use `ValueFromPipeline` and `ValueFromPipelineByPropertyName` appropriately
- Validate parameters with `[ValidateSet()]`, `[ValidateRange()]`, etc.


### Integrating PSScriptAnalyzer in Tests

```powershell
Describe "PSScriptAnalyzer" {
    Context "Script quality" {
        It "Should pass PSScriptAnalyzer rules" {
            $results = Invoke-ScriptAnalyzer -Path $PSScriptRoot/../script.ps1
            $results | Should -BeNullOrEmpty
        }

        It "Should have no high severity issues" {
            $results = Invoke-ScriptAnalyzer -Path $PSScriptRoot/.. -Recurse -Severity Error
            $results | Should -BeNullOrEmpty
        }
    }
}
```

## Test Execution

### Running Pester Tests

```powershell
# Run all tests in current directory
Invoke-Pester

# Run specific test file
Invoke-Pester -Path .\MyFunction.Tests.ps1

# Run with code coverage
Invoke-Pester -CodeCoverage .\script.ps1

# Output to CI-friendly format
Invoke-Pester -OutputFormat NUnitXml -OutputFile test-results.xml

# Run with detailed output
Invoke-Pester -Output Detailed
```

### CI/CD Integration

For GitHub Actions or other CI systems:

```powershell
$config = New-PesterConfiguration
$config.Run.Path = './tests'
$config.Run.Exit = $true
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = 'test-results.xml'
$config.CodeCoverage.Enabled = $true

Invoke-Pester -Configuration $config
```

## Common Patterns

### Testing Functions with Pipeline Input

```powershell
It "Should accept pipeline input" {
    $input = @("file1.txt", "file2.txt")
    $result = $input | Process-CustomFunction
    $result.Count | Should -Be 2
}
```

### Testing Error Handling

```powershell
It "Should throw when path doesn't exist" {
    { Get-CustomData -Path "C:\nonexistent" } | Should -Throw
}

It "Should write error for invalid input" {
    Get-CustomData -Path "invalid" -ErrorVariable err
    $err | Should -Not -BeNullOrEmpty
}
```

### Testing Private Functions

```powershell
InModuleScope MyModule {
    It "Should test private function" {
        PrivateFunction | Should -Be $expected
    }
}
```

## Quick Reference

### When to use this skill

- Writing new Pester tests for PowerShell scripts or modules
- Debugging failing PowerShell tests
- Analyzing PowerShell code quality with PSScriptAnalyzer
- Refactoring PowerShell code to meet best practices
- Setting up PowerShell test infrastructure
- Integrating PowerShell tests into CI/CD pipelines
