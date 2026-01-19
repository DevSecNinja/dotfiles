#!/bin/bash
# Homebrew initialization for Bash
# This file handles Homebrew shell environment setup

# Initialize Homebrew (macOS/Linux)
if [ -f "/opt/homebrew/bin/brew" ]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
	eval "$(/usr/local/bin/brew shellenv)"
elif [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Load Homebrew's bash completions from bash_completion.d directory
# These are static completion files provided by Homebrew packages
if command -v brew &>/dev/null; then
	HOMEBREW_PREFIX="$(brew --prefix)"
	if [ -d "${HOMEBREW_PREFIX}/etc/bash_completion.d" ]; then
		for completion_file in "${HOMEBREW_PREFIX}/etc/bash_completion.d"/*; do
			if [ -r "$completion_file" ] && [ -f "$completion_file" ]; then
				# shellcheck source=/dev/null
				source "$completion_file"
			fi
		done
	fi
fi
