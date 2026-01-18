#!/bin/bash
# Test Chezmoi apply in dry-run mode
# Verifies that dotfiles can be applied without errors

set -e

echo "🧪 Testing Chezmoi apply (dry-run)..."

# Check if chezmoi is available
if ! command -v chezmoi >/dev/null 2>&1; then
	echo "⚠️  Chezmoi not found, installing..."
	sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "${HOME}/.local/bin"
	export PATH="${HOME}/.local/bin:${PATH}"
fi

# Get the source directory (current directory if not specified)
SOURCE_DIR="${1:-.}"

echo "📂 Source directory: ${SOURCE_DIR}"
echo "🏠 Target directory: ${HOME}"
echo ""

# Run chezmoi init in dry-run mode
echo "Running: chezmoi init --apply --dry-run --source='${SOURCE_DIR}'"
chezmoi init --apply --dry-run --source="${SOURCE_DIR}"

echo ""
echo "✅ Dry-run completed successfully!"
echo "💡 No errors detected during simulation"
