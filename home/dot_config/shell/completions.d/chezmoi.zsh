#!/bin/zsh
# Chezmoi completion for Zsh
# Note: Homebrew provides chezmoi completions in $(brew --prefix)/share/zsh/site-functions/_chezmoi
# which are automatically loaded when Homebrew is initialized (brew shellenv adds to FPATH).
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if chezmoi is available and not already in fpath
if command -v chezmoi >/dev/null 2>&1 && [[ ! -f "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_chezmoi" ]]; then
    eval "$(chezmoi completion zsh)"
fi
