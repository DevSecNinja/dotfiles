#!/bin/bash
# mise (rtx) initialization for Bash
# Note: 'mise activate' handles shell integration (PATH, hooks)
# Completions are generated separately using 'mise completion bash'

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
	# Set MISE_YES=1 in non-interactive environments to auto-accept trust prompts
	# This prevents mise from hanging when it encounters .mise.toml files in Codespaces/CI
	if [ -n "${CI:-}" ] || [ -n "${CODESPACES:-}" ] || [ -n "${GITHUB_ACTIONS:-}" ] || [ ! -t 0 ]; then
		export MISE_YES=1
	fi

	# Activate mise (shell integration)
	eval "$(mise activate bash)"

	# Load completions
	eval "$(mise completion bash --include-bash-completion-lib)"
fi
