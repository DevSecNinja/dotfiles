# Third-Party GitHub Actions Analysis

## Executive Summary

**Question:** Can we replace third-party actions with native GitHub Actions?

**Answer:** No fully native replacements exist, but we can use `GITHUB_STEP_SUMMARY` for basic test reporting at the cost of losing advanced features like GitHub Checks integration and PR annotations.

## Current Third-Party Actions

### 1. EnricoMi/publish-unit-test-result-action

**Used in:**
- `.github/workflows/ci.yaml` (test-bash-scripts job) - Linux variant
- `.github/workflows/ci.yaml` (test-powershell-scripts job) - Windows variant (note: PowerShell refers to the testing framework, the job name uses lowercase)

**Purpose:** Publishes JUnit XML test results as GitHub Checks

**Configuration:**
```yaml
- name: Publish Test Results
  uses: EnricoMi/publish-unit-test-result-action@v2
  if: always()
  with:
    files: tests/bash/test-results.xml
    check_name: 'Bash Test Results (Bats)'
    comment_mode: off
```

**Features Provided:**
- ✅ Parses JUnit/NUnit/XUnit/TRX XML test result files
- ✅ Creates GitHub Check Runs with pass/fail status
- ✅ Displays test counts (passed/failed/skipped) in PR UI
- ✅ Annotates failing tests at code level (when enabled)
- ✅ Supports PR comments with test summaries (currently disabled with `comment_mode: off`)
- ✅ Works on both Linux and Windows runners
- ✅ Handles multiple test result files and formats

### 2. alstr/todo-to-issue-action

**Used in:**
- `.github/workflows/todo-to-issue.yml`

**Purpose:** Automatically creates GitHub issues from TODO/FIXME comments in code

**Configuration:**
```yaml
- name: "TODO to Issue"
  uses: "alstr/todo-to-issue-action@v5"
  with:
    AUTO_ASSIGN: false
```

**Features Provided:**
- ✅ Scans code for TODO/FIXME/HACK comments
- ✅ Creates GitHub issues for new TODOs
- ✅ Updates existing issues when TODO text changes
- ✅ Closes issues when TODOs are removed from code
- ✅ Supports custom keywords and patterns
- ✅ Can auto-assign issues to contributors
- ✅ Supports custom labels

## Native GitHub Alternatives

### Test Result Publishing

**Native Options:**

#### Option A: Use `GITHUB_STEP_SUMMARY` (Basic)
- **What it is:** Environment variable that creates Markdown summaries in job output
- **Available since:** Late 2022
- **Documentation:** https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#adding-a-job-summary

**Example:**
```yaml
- name: Generate Test Summary
  if: always()
  run: |
    echo "### Test Results" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
    # Parse XML and generate markdown table
    # This requires custom scripting
```

**Pros:**
- ✅ Native GitHub feature (no third-party action)
- ✅ Displays in job summary UI
- ✅ Supports rich Markdown formatting

**Cons:**
- ❌ Requires custom XML parsing scripts
- ❌ No GitHub Checks integration (doesn't show in PR checks UI)
- ❌ No code-level annotations
- ❌ More maintenance overhead
- ❌ Must implement separately for each test format

#### Option B: Upload Artifacts Only
- **What it is:** Use only `actions/upload-artifact@v6` to save test results
- **Available since:** Always (core GitHub Actions feature)

**Example:**
```yaml
- name: Upload Test Results
  if: always()
  uses: actions/upload-artifact@v6
  with:
    name: test-results
    path: test-results.xml
```

**Pros:**
- ✅ Native GitHub action (from `actions` org)
- ✅ Test results preserved for download
- ✅ Simple and reliable

**Cons:**
- ❌ No visibility in PR UI
- ❌ No pass/fail status in checks
- ❌ Requires manual download to view results
- ❌ Poor developer experience

### TODO-to-Issue Conversion

**Native Options:**

#### Option A: Manual Issue Creation
- Developers manually create issues from TODOs
- No automation

**Pros:**
- ✅ No dependencies
- ✅ Full control over issue content

**Cons:**
- ❌ Requires manual work
- ❌ TODOs often forgotten
- ❌ No automatic issue lifecycle management

#### Option B: Custom GitHub API Script
- Write custom script using GitHub API to scan and create issues
- Run in workflow with `actions/github-script@v8`

**Pros:**
- ✅ Uses official `actions/github-script` action
- ✅ Customizable to project needs

**Cons:**
- ❌ Requires significant development and maintenance
- ❌ Must handle all edge cases manually
- ❌ Complex issue lifecycle management
- ❌ Reinventing the wheel

## Third-Party Alternatives

### Test Result Publishing

#### dorny/test-reporter
- **Alternative to:** EnricoMi/publish-unit-test-result-action
- **Status:** Well-maintained, 450+ stars
- **GitHub:** https://github.com/dorny/test-reporter

**Features:**
- ✅ Similar functionality to EnricoMi action
- ✅ Supports JUnit, TAP, dotnet-trx, mocha, jest-junit
- ✅ Creates GitHub Checks
- ✅ Code annotations for failures
- ✅ Works on Linux only (no Windows support as of January 2026)

**Trade-offs vs EnricoMi:**
- ❌ No Windows support (as of January 2026; EnricoMi has `/windows` variant)
- ❌ Fewer test format options
- ✅ Simpler configuration
- ✅ Active development

#### test-summary/action
- **Alternative to:** EnricoMi/publish-unit-test-result-action
- **Status:** Well-maintained, GitHub-native feel
- **GitHub:** https://github.com/test-summary/action

**Features:**
- ✅ Creates detailed job summaries using `GITHUB_STEP_SUMMARY`
- ✅ Supports multiple test formats
- ✅ Cross-platform (Linux, macOS, Windows)
- ✅ Can create GitHub Checks

**Trade-offs vs EnricoMi:**
- ✅ Better summary formatting
- ✅ More modern approach
- ❌ Less PR integration features
- ❌ Fewer configuration options

### TODO-to-Issue Conversion

#### ribtoks/tdg-github-action
- **Alternative to:** alstr/todo-to-issue-action
- **Status:** Maintained
- **GitHub:** https://github.com/ribtoks/tdg-github-action

**Features:**
- ✅ Similar TODO scanning functionality
- ✅ Issue creation and management
- ✅ Supports custom patterns

**Trade-offs:**
- Similar feature set, different maintainer

## Recommendations

### For Test Result Publishing (EnricoMi Action)

**Recommendation: Keep EnricoMi/publish-unit-test-result-action**

**Rationale:**
1. **No native equivalent exists** - GitHub does not provide a built-in action for test result publishing
2. **Significant value provided** - GitHub Checks integration is important for PR review workflow
3. **Low maintenance overhead** - Action is stable, well-maintained (1.7k+ stars)
4. **Currently working well** - No issues reported, serves its purpose
5. **Native alternatives are insufficient:**
   - `GITHUB_STEP_SUMMARY` requires custom XML parsing for each test format
   - No Checks API integration means no PR status visibility
   - Significant development effort for marginal benefit

**Alternative if removal required:**
- For Linux: Could switch to `dorny/test-reporter` (still third-party)
- For Windows: Must remove or write custom solution (no alternatives exist)
- Could use `test-summary/action` (still third-party, less mature)

**Cost of removal:**
- ❌ Loss of GitHub Checks integration (no pass/fail in PR UI)
- ❌ Loss of test count summaries
- ❌ Need to download artifacts to see results
- ❌ Reduced developer experience
- ❌ Requires custom scripting with `GITHUB_STEP_SUMMARY` (more maintenance)

### For TODO-to-Issue Conversion (alstr Action)

**Recommendation: Keep alstr/todo-to-issue-action OR remove workflow entirely**

**Rationale:**
1. **No native equivalent exists** - This is a specialized automation tool
2. **Low risk, low maintenance** - Action is stable and simple
3. **Nice-to-have feature** - Not critical to CI/CD pipeline
4. **Removal is viable** - If truly want to eliminate third-party dependencies

**Alternative if removal required:**
- Remove the entire `todo-to-issue.yml` workflow
- Rely on manual issue creation
- Document TODO handling process in CONTRIBUTING.md

**Cost of removal:**
- ❌ Loss of automatic TODO tracking
- ❌ Manual process for TODO management
- ✅ One less third-party dependency
- ✅ Simplified workflow setup

## Official GitHub Actions (Already Using)

These are **official** actions from the `actions` organization and should be kept:

- ✅ `actions/checkout@v6` - Official
- ✅ `actions/setup-python@v6` - Official
- ✅ `actions/upload-artifact@v6` - Official
- ✅ `actions/github-script@v8` - Official

## Conclusion

**There are NO native GitHub Actions that can replace:**
1. EnricoMi/publish-unit-test-result-action
2. alstr/todo-to-issue-action

**Options:**
1. **Keep current setup** (recommended) - Actions provide significant value with minimal maintenance
2. **Replace with other third-party actions** - Marginal benefit, still not "native"
3. **Remove and use basic alternatives** - Significant loss of functionality, more maintenance

**Final Recommendation:** Keep the current third-party actions. They are:
- Well-maintained and stable
- Providing important features not available natively
- Low maintenance overhead
- Industry standard solutions
- Better than spending development time building custom alternatives

If the goal is to reduce external dependencies, the only realistic option is to remove the features entirely and accept the reduced functionality.
