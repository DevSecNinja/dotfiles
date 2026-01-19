#!/bin/bash
# Chezmoi completion for Bash
# Note: Homebrew provides chezmoi completions in $(brew --prefix)/etc/bash_completion.d/chezmoi
# which are automatically loaded by 00-homebrew.bash.
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if chezmoi is available and not already loaded from Homebrew
if command -v chezmoi >/dev/null 2>&1 && ! type _chezmoi_bash_autocomplete >/dev/null 2>&1; then
	eval "$(chezmoi completion bash)"
fi
