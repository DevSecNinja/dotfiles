#!/bin/zsh
# shellcheck disable=SC1071
# Zsh configuration
# This file should be sourced by ~/.zshrc

# Initialize Homebrew (macOS)
if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

# Load all functions from shell/functions directory
if [[ -d "$HOME/.config/shell/functions" ]]; then
    for func_file in "$HOME/.config/shell/functions"/*; do
        if [[ -r "$func_file" && -f "$func_file" ]]; then
            source "$func_file"
        fi
    done
fi

# Source any shell-specific configurations
if [[ -f "$HOME/.config/shell/zshrc" ]]; then
    source "$HOME/.config/shell/zshrc"
fi
