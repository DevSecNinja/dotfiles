#!/bin/bash
# Chezmoi completion for Bash
# Generate completion dynamically if chezmoi is available

if command -v chezmoi >/dev/null 2>&1; then
    eval "$(chezmoi completion bash)"
fi
