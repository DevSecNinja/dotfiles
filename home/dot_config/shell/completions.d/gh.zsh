#!/bin/zsh
# GitHub CLI completion for Zsh
# Note: Homebrew provides gh completions in $(brew --prefix)/share/zsh/site-functions/_gh
# which are automatically loaded when Homebrew is initialized (brew shellenv adds to FPATH).
# This file exists only for non-Homebrew installations.

# Only generate completion dynamically if gh is available and not already in fpath
if command -v gh >/dev/null 2>&1 && [[ ! -f "$(brew --prefix 2>/dev/null)/share/zsh/site-functions/_gh" ]]; then
    eval "$(gh completion -s zsh)"
fi
