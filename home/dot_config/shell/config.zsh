#!/bin/zsh
# shellcheck disable=SC1071
# Zsh configuration
# This file should be sourced by ~/.zshrc

# Load common aliases
if [[ -f "$HOME/.config/shell/aliases.sh" ]]; then
    source "$HOME/.config/shell/aliases.sh"
fi

# Load all completions and evals from completions.d/
if [[ -d "$HOME/.config/shell/completions.d" ]]; then
    for comp_file in "$HOME/.config/shell/completions.d"/*.zsh; do
        if [[ -r "$comp_file" && -f "$comp_file" ]]; then
            source "$comp_file"
        fi
    done
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
