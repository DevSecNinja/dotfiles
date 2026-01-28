#!/bin/fish
# Task (go-task) completion for fish
# Note: Homebrew provides task completions in $(brew --prefix)/share/fish/site-functions/_task
# which are automatically loaded when Homebrew is initialized (brew shellenv adds to FPATH).
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if task is available and not already provided by Homebrew
if command -v task >/dev/null 2>&1
	set -l brew_prefix (command -v brew >/dev/null 2>&1 && brew --prefix 2>/dev/null || echo "")
	if test -z "$brew_prefix" || test ! -f "$brew_prefix/share/fish/site-functions/_task"
		# Safely evaluate task completion, suppressing any error messages
		eval (task --completion fish 2>/dev/null || true)
	end
end
