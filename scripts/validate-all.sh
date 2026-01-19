#!/bin/bash
# Run all validation checks
# Wrapper to run validation tests using Bats test framework

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TESTS_DIR="${REPO_ROOT}/tests"

echo "╔════════════════════════════════════════╗"
echo "║   Dotfiles Validation Suite            ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Running validation tests via Bats framework..."
echo ""

# Run Bash validation tests
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running Bash Validation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if "${TESTS_DIR}/bash/run-tests.sh" --ci; then
	BASH_STATUS=0
	echo "✅ Bash validation tests passed"
else
	BASH_STATUS=1
	echo "❌ Bash validation tests failed"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Running PowerShell Validation Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if PowerShell is available
if command -v pwsh >/dev/null 2>&1; then
	if pwsh -c "${TESTS_DIR}/powershell/Invoke-PesterTests.ps1 -CI"; then
		PWSH_STATUS=0
		echo "✅ PowerShell validation tests passed"
	else
		PWSH_STATUS=1
		echo "❌ PowerShell validation tests failed"
	fi
else
	echo "⚠️  PowerShell not available, skipping PowerShell tests"
	PWSH_STATUS=0
fi

echo ""
echo "╔════════════════════════════════════════╗"
echo "║           Summary                      ║"
echo "╚════════════════════════════════════════╝"

if [ "${BASH_STATUS}" -eq 0 ] && [ "${PWSH_STATUS}" -eq 0 ]; then
	echo "✅ All validation checks passed!"
	exit 0
else
	echo "❌ Some validation checks failed"
	exit 1
fi
