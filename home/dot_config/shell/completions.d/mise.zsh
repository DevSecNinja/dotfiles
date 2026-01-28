#!/bin/zsh
# mise (rtx) initialization for Zsh
# Note: 'mise activate' handles shell integration (PATH, hooks)
# Completions are generated separately using 'mise completion zsh'

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
	# Activate mise (shell integration)
	# Safely evaluate, suppressing any error messages
	eval "$(mise activate zsh 2>/dev/null)" 2>/dev/null || true

	# Load completions
	eval "$(mise completion zsh 2>/dev/null)" 2>/dev/null || true
fi
