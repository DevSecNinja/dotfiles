#!/bin/zsh
# Task (go-task) completion for Zsh
# Note: Homebrew provides task completions in $(brew --prefix)/share/zsh/site-functions/_task
# which are automatically loaded when Homebrew is initialized (brew shellenv adds to FPATH).
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if task is available and not already in fpath
if command -v task >/dev/null 2>&1 && [[ ! -f "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_task" ]]; then
	# Safely evaluate task completion, suppressing any error messages
	eval "$(task --completion zsh 2>/dev/null)" 2>/dev/null || true
fi
