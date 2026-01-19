#!/bin/bash
# Bash configuration
# This file should be sourced by ~/.bashrc or ~/.bash_profile

# Load common aliases
if [ -f "$HOME/.config/shell/aliases.sh" ]; then
	# shellcheck source=/dev/null
	source "$HOME/.config/shell/aliases.sh"
fi

# Load all completions and evals from completions.d/
if [ -d "$HOME/.config/shell/completions.d" ]; then
	for comp_file in "$HOME/.config/shell/completions.d"/*.bash; do
		if [ -r "$comp_file" ] && [ -f "$comp_file" ]; then
			# shellcheck source=/dev/null
			source "$comp_file"
		fi
	done
fi

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
