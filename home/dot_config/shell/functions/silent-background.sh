#!/bin/bash

# Run the command given by "$@" in the background
# https://superuser.com/a/1334617
silent-background() {
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
