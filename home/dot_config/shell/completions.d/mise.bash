#!/bin/bash
# mise (rtx) initialization for Bash
# Note: 'mise activate' handles shell integration (PATH, hooks)
# Completions are generated separately using 'mise completion bash'

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
	# Activate mise (shell integration)
	eval "$(mise activate bash)"

	# Load completions
	eval "$(mise completion bash --include-bash-completion-lib)"
fi
