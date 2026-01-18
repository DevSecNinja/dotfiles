#!/bin/zsh
# Chezmoi completion for Zsh
# Generate completion dynamically if chezmoi is available

if command -v chezmoi >/dev/null 2>&1; then
    eval "$(chezmoi completion zsh)"
fi
