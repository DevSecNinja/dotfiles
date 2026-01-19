#!/bin/bash
# mise (rtx) initialization for Bash
# Note: 'mise activate' handles its own completion setup
# Homebrew does not provide mise completions as mise manages them internally

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
	eval "$(mise activate bash)"
fi
