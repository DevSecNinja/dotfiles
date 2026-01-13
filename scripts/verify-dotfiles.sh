#!/bin/bash
# Verify that dotfiles were applied correctly
# Checks that all expected files exist after chezmoi apply

set -e

echo "🔍 Verifying applied dotfiles..."

# Expected files that should exist after apply
EXPECTED_FILES="
$HOME/.vimrc
$HOME/.tmux.conf
$HOME/.config/fish/config.fish
$HOME/.config/fish/conf.d/aliases.fish
$HOME/.config/fish/functions/fish_greeting.fish
$HOME/.config/git/config
$HOME/.config/git/ignore
"

# Track results
MISSING_COUNT=0
FOUND_COUNT=0

echo ""
echo "Checking expected files..."

for file in ${EXPECTED_FILES}; do
    if [ -n "${file}" ]; then
        if [ -f "${file}" ]; then
            echo "  ✅ ${file}"
            FOUND_COUNT=$((FOUND_COUNT + 1))
        else
            echo "  ❌ ${file} (missing)"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    fi
done

echo ""
echo "📊 Results: ${FOUND_COUNT} found, ${MISSING_COUNT} missing"

if [ "${MISSING_COUNT}" -gt 0 ]; then
    echo "❌ Some expected dotfiles are missing"
    exit 1
fi

echo "✅ All expected dotfiles are present!"
