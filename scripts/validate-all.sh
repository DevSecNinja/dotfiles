#!/bin/bash
# Run all validation checks
# Convenient wrapper to run all validation scripts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${1:-.}"

echo "╔════════════════════════════════════════╗"
echo "║   Dotfiles Validation Suite            ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Track overall results
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

run_check() {
    local name="$1"
    local script="$2"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Running: ${name}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if bash "${SCRIPT_DIR}/${script}" "${SOURCE_DIR}"; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo "✅ ${name} passed"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo "❌ ${name} failed"
        return 1
    fi
}

# Run all validation checks (continue even if one fails)
run_check "Chezmoi Configuration" "validate-chezmoi.sh" || true
run_check "Shell Script Syntax" "validate-shell-scripts.sh" || true
run_check "Fish Configuration" "validate-fish-config.sh" || true
run_check "Chezmoi Apply (Dry-run)" "test-chezmoi-apply.sh" || true

echo ""
echo "╔════════════════════════════════════════╗"
echo "║           Summary                      ║"
echo "╚════════════════════════════════════════╝"
echo "Total checks:  ${TOTAL_CHECKS}"
echo "Passed:        ${PASSED_CHECKS}"
echo "Failed:        ${FAILED_CHECKS}"
echo ""

if [ "${FAILED_CHECKS}" -gt 0 ]; then
    echo "❌ Some checks failed"
    exit 1
fi

echo "✅ All validation checks passed!"
