#!/bin/bash
# Test light server installation scenario (CI only)
# This script only runs in GitHub Actions with hostname set via container options

set -e

# Only run in CI environment
if [ "${CI:-}" != "true" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
	echo "ℹ️  This test is designed to run in GitHub Actions only"
	echo "💡 It requires specific container hostname configuration"
	exit 0
fi

echo "🧪 Testing light server installation scenario..."
echo "🖥️  Hostname: $(hostname)"

# Set a temporary HOME for testing
TEST_HOME="${TMPDIR:-/tmp}/chezmoi-test-light-$$"
export HOME="${TEST_HOME}"
mkdir -p "${TEST_HOME}"

# Ensure .local/bin is in PATH
export PATH="${HOME}/.local/bin:${PATH}"

# Get the source directory (parent of .github)
SOURCE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "📂 Source directory: ${SOURCE_DIR}"
echo "🏠 Test HOME: ${TEST_HOME}"
echo ""

# Install chezmoi if not present
if ! command -v chezmoi >/dev/null 2>&1; then
	echo "Installing chezmoi..."
	sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "${HOME}/.local/bin"
fi

# Run chezmoi init and apply
echo "Running: chezmoi init --apply --no-tty --source='${SOURCE_DIR}'"
chezmoi init --apply --no-tty --source="${SOURCE_DIR}"

echo ""
echo "🔍 Verifying light server installation..."

# Check that essential files exist
ESSENTIAL_FILES="
${HOME}/.vimrc
${HOME}/.tmux.conf
${HOME}/.config/fish/config.fish
${HOME}/.config/git/config
"

# Verify essential files
echo ""
echo "Checking essential files (should exist)..."
MISSING_COUNT=0
for file in ${ESSENTIAL_FILES}; do
	if [ -n "${file}" ]; then
		if [ -f "${file}" ]; then
			echo "  ✅ ${file}"
		else
			echo "  ❌ ${file} (missing)"
			MISSING_COUNT=$((MISSING_COUNT + 1))
		fi
	fi
done

# Check chezmoi data to verify installType
echo ""
echo "📋 Checking chezmoi data:"
INSTALL_TYPE=$(chezmoi data 2>/dev/null | grep -o '"installType": "[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
echo "  Install type: ${INSTALL_TYPE}"

if [ "${INSTALL_TYPE}" != "light" ]; then
	echo "  ❌ Expected installType=light, got ${INSTALL_TYPE}"
	MISSING_COUNT=$((MISSING_COUNT + 1))
else
	echo "  ✅ Install type is correctly set to 'light'"
fi

# Clean up
echo ""
echo "🧹 Cleaning up test environment..."
rm -rf "${TEST_HOME}"

# Report results
echo ""
if [ "${MISSING_COUNT}" -gt 0 ]; then
	echo "❌ Light server test FAILED"
	echo "   Missing essential files or incorrect install type: ${MISSING_COUNT}"
	exit 1
fi

echo "✅ Light server test PASSED!"
echo "💡 All essential files present, install type correctly set to 'light'"
