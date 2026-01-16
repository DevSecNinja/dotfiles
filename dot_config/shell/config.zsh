#!/bin/zsh
# Zsh configuration
# This file should be sourced by ~/.zshrc

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
