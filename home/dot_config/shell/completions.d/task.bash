#!/bin/bash
# Task (go-task) completion for Bash
# Note: Homebrew provides task completions in $(brew --prefix)/etc/bash_completion.d/task
# which are automatically loaded by 00-homebrew.bash.
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if task is available and not already loaded from Homebrew
if command -v task >/dev/null 2>&1 && ! type _task_bash_autocomplete >/dev/null 2>&1; then
	eval "$(task --completion bash)"
fi
