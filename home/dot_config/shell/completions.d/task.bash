#!/bin/bash
# Task (go-task) completion for Bash
# https://taskfile.dev

# Load Task completion if Task is available
if command -v task >/dev/null 2>&1; then
	eval "$(task --completion bash)"
fi
