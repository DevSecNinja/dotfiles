#!/bin/bash
# mcd - Create a directory and cd into it

mcd() {
	if [ $# -ne 1 ]; then
		echo "Usage: mcd <directory>" >&2
		return 1
	fi

	mkdir -p "$1" && cd "$1" || return 1
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	mcd "$@"
fi
