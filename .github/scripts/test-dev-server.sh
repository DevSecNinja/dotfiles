#!/bin/bash
# Test dev server installation scenario (CI only)
# This script only runs in GitHub Actions with hostname set via container options

set -e

# Only run in CI environment
if [ "${CI:-}" != "true" ] && [ "${GITHUB_ACTIONS:-}" != "true" ]; then
	echo "ℹ️  This test is designed to run in GitHub Actions only"
	echo "💡 It requires specific container hostname configuration"
	exit 0
fi

echo "🧪 Testing dev server installation scenario..."
echo "🖥️  Hostname: $(hostname)"

# Ensure .local/bin is in PATH
export PATH="${HOME}/.local/bin:${PATH}"

# Get the source directory (parent of .github)
SOURCE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

echo "📂 Source directory: ${SOURCE_DIR}"
echo ""

# Install chezmoi if not present
if ! command -v chezmoi >/dev/null 2>&1; then
	echo "Installing chezmoi..."
	sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "${HOME}/.local/bin"
fi

# Run chezmoi init and apply
echo "Running: chezmoi init --apply --no-tty --source='${SOURCE_DIR}'"
chezmoi init --apply --no-tty --source="${SOURCE_DIR}"

echo ""
echo "🔍 Verifying dev server installation..."

# Check that all essential files exist
ALL_FILES="
${HOME}/.vimrc
${HOME}/.tmux.conf
${HOME}/.config/fish/config.fish
${HOME}/.config/git/config
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
INSTALL_TYPE=$(chezmoi data 2>/dev/null | grep -o '"installType": "[^"]*"' | head -1 | cut -d'"' -f4 || echo "unknown")
echo "  Install type: ${INSTALL_TYPE}"

if [ "${INSTALL_TYPE}" != "full" ]; then
	echo "  ❌ Expected installType=full, got ${INSTALL_TYPE}"
	MISSING_COUNT=$((MISSING_COUNT + 1))
else
	echo "  ✅ Install type is correctly set to 'full'"
fi

# Report results
echo ""
if [ "${MISSING_COUNT}" -gt 0 ]; then
	echo "❌ Dev server test FAILED"
	echo "   Missing files or incorrect install type: ${MISSING_COUNT}"
	exit 1
fi

echo "✅ Dev server test PASSED!"
echo "💡 All essential files present in full mode"
