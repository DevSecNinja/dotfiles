#!/bin/bash
# GitHub CLI completion for Bash
# Generate completion dynamically if gh is available

if command -v gh >/dev/null 2>&1; then
	eval "$(gh completion -s bash)"
fi
