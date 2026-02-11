#!/bin/bash
# silent-background - Run a command silently in the background
#
# Runs a command in the background with all output suppressed and
# immediately disowns the process. Works with both Bash and Zsh.
#
# Usage: silent-background [OPTIONS] COMMAND [ARGS...]
#   --help, -h       Show help message and exit
#
# Examples:
#   silent-background sleep 10       # Run sleep in the background
#   silent-background ./my-script    # Run a script silently
#
# Notes:
#   - Suppresses both stdout and stderr
#   - Works with both Bash and Zsh shells
#   - Based on https://superuser.com/a/1334617

silent-background() {
	if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		echo "Usage: silent-background COMMAND [ARGS...]"
		echo "Run a command silently in the background"
		echo ""
		echo "Options:"
		echo "  -h, --help       Show this help message"
		echo ""
		echo "Examples:"
		echo "  silent-background sleep 10       # Run sleep in the background"
		echo "  silent-background ./my-script    # Run a script silently"
		return 0
	fi

	if [[ $# -eq 0 ]]; then
		echo "❌ Error: No command specified"
		echo "Use --help for usage information"
		return 1
	fi

	if [[ -n $ZSH_VERSION ]]; then # zsh:  https://superuser.com/a/1285272/365890
		setopt NO_NOTIFY NO_MONITOR
		# We'd use &| to background and disown, but incompatible with bash, so:
		"$@" &
	elif [[ -n $BASH_VERSION ]]; then # bash: https://stackoverflow.com/a/27340076/5353461
		{ 2>&3 "$@" & } 3>&2 2>/dev/null
	else # Unknownness - just background it
		"$@" &
	fi
	disown &>/dev/null # Close STD{OUT,ERR} to prevent whine if job has already completed
}
