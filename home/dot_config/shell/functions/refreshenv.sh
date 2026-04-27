#!/bin/bash
# refreshenv - Reload the current shell to refresh environment variables

refreshenv() {
	local shell
	shell=$(ps -p $$ -ocomm=) && exec "${shell}"
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	refreshenv "$@"
fi
