#!/bin/zsh
# mise (rtx) initialization for Zsh
# This file handles mise shell integration and completion

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
fi
