#!/bin/bash
# GitHub CLI completion for Bash
# Note: Homebrew provides gh completions in $(brew --prefix)/etc/bash_completion.d/gh
# which are automatically loaded by 00-homebrew.bash.
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if gh is available and not already loaded from Homebrew
if command -v gh >/dev/null 2>&1 && ! type __start_gh >/dev/null 2>&1; then
	eval "$(gh completion -s bash)"
fi
