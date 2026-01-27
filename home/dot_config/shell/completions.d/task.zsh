#!/bin/zsh
# Task (go-task) completion for Zsh
# https://taskfile.dev

# Load Task completion if Task is available
if command -v task >/dev/null 2>&1; then
	eval "$(task --completion zsh)"
fi
