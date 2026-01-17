#!/bin/bash
# Bash configuration
# This file should be sourced by ~/.bashrc or ~/.bash_profile

# Load all functions from shell/functions directory
if [ -d "$HOME/.config/shell/functions" ]; then
	for func_file in "$HOME/.config/shell/functions"/*; do
		if [ -r "$func_file" ] && [ -f "$func_file" ]; then
			# shellcheck source=/dev/null
			source "$func_file"
		fi
	done
fi

# Source any shell-specific configurations
if [ -f "$HOME/.config/shell/bashrc" ]; then
	# shellcheck source=/dev/null
	source "$HOME/.config/shell/bashrc"
fi
