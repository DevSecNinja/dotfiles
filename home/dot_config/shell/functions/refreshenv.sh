#!/bin/bash
# refreshenv - Reload the current shell to refresh environment variables

refreshenv() {
	local shell
	shell=$(ps -p $$ -ocomm=) || return 1
	if [ -z "$shell" ]; then
		echo "refreshenv: could not determine current shell" >&2
		return 1
	fi
	exec "${shell}"
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	refreshenv "$@"
fi
