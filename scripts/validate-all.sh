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
"${TESTS_DIR}/bash/run-tests.sh" --ci
