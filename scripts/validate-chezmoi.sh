#!/bin/bash
# Validate Chezmoi configuration
# This script checks if Chezmoi can successfully read and parse the configuration

set -e

echo "🔍 Validating Chezmoi configuration..."

# Check if chezmoi is available
if ! command -v chezmoi >/dev/null 2>&1; then
	echo "⚠️  Chezmoi not found, installing..."
	sh -c "$(curl -fsLS https://get.chezmoi.io)" -- -b "${HOME}/.local/bin"
	export PATH="${HOME}/.local/bin:${PATH}"
fi

# Get the source directory (current directory if not specified)
SOURCE_DIR="${1:-.}"

# Validate that chezmoi can read the data
echo "📊 Reading Chezmoi data..."
chezmoi data --source="${SOURCE_DIR}"

echo "✅ Chezmoi configuration is valid!"
