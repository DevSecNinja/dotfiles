#!/bin/bash
# Test dev server installation scenario
# Simulates installation on a dev server with hostname SVLDEV*

set -e

echo "🧪 Testing dev server installation scenario..."

# Set a temporary HOME for testing
TEST_HOME="${TMPDIR:-/tmp}/chezmoi-test-dev-$$"
export HOME="${TEST_HOME}"
mkdir -p "${TEST_HOME}"

# Set hostname to simulate a dev server
export HOSTNAME="SVLDEV01"

# Ensure .local/bin is in PATH
export PATH="${HOME}/.local/bin:${PATH}"

# Get the source directory (current directory if not specified)
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "📂 Source directory: ${SOURCE_DIR}"
echo "🏠 Test HOME: ${TEST_HOME}"
echo "🖥️  Simulated hostname: ${HOSTNAME}"
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
echo "🔍 Verifying dev server installation..."

# Check that all files exist (including dev tools)
ALL_FILES="
${HOME}/.vimrc
${HOME}/.tmux.conf
${HOME}/.config/fish/config.fish
${HOME}/.config/git/config
${HOME}/.pre-commit-config.yaml
${HOME}/requirements.txt
"

# Verify all files
echo ""
echo "Checking all files (should exist in full mode)..."
MISSING_COUNT=0
for file in ${ALL_FILES}; do
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
INSTALL_TYPE=$(chezmoi data | grep -o '"installType": "[^"]*"' | cut -d'"' -f4 || echo "unknown")
echo "  Install type: ${INSTALL_TYPE}"

if [ "${INSTALL_TYPE}" != "full" ]; then
	echo "  ❌ Expected installType=full, got ${INSTALL_TYPE}"
	MISSING_COUNT=$((MISSING_COUNT + 1))
else
	echo "  ✅ Install type is correctly set to 'full'"
fi

# Clean up
echo ""
echo "🧹 Cleaning up test environment..."
rm -rf "${TEST_HOME}"

# Report results
echo ""
if [ "${MISSING_COUNT}" -gt 0 ]; then
	echo "❌ Dev server test FAILED"
	echo "   Missing files: ${MISSING_COUNT}"
	exit 1
fi

echo "✅ Dev server test PASSED!"
echo "💡 All files present, including dev tools"
