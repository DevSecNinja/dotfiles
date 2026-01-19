#!/bin/zsh
# mise (rtx) initialization for Zsh
# Note: 'mise activate' handles its own completion setup
# Homebrew does not provide mise completions as mise manages them internally

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi
