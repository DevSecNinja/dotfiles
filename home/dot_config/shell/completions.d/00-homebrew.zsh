#!/bin/zsh
# Homebrew initialization for Zsh
# This file handles Homebrew shell environment setup

# Initialize Homebrew (macOS/Linux)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
elif [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Add Homebrew completions to fpath
# Note: brew shellenv does NOT set FPATH, we must do it manually
# See: https://docs.brew.sh/Shell-Completion#configuring-completions-in-zsh
if command -v brew &>/dev/null; then
    FPATH="$(brew --prefix)/share/zsh/site-functions:${FPATH}"
fi
