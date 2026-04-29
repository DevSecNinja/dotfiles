#!/bin/bash
# Bash completion for the `log` dispatcher (from log.sh).
# Completes the first argument with severities and kinds.

_log_completion() {
	local cur
	cur="${COMP_WORDS[COMP_CWORD]}"

	if [[ ${COMP_CWORD} -eq 1 ]]; then
		local levels="trace debug info notice warn error fatal state result hint step banner"
		# shellcheck disable=SC2207
		COMPREPLY=($(compgen -W "${levels}" -- "${cur}"))
		return 0
	fi

	# After the level/kind, fall back to filename completion so paths used in
	# messages (e.g. log info "/var/log/foo") still complete naturally.
	# shellcheck disable=SC2207
	COMPREPLY=($(compgen -f -- "${cur}"))
}

complete -F _log_completion log
