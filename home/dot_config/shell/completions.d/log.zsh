#!/bin/zsh
# shellcheck disable=SC1071
# Zsh completion for the `log` dispatcher (from log.sh).
# Completes the first argument with severities and kinds.

_log() {
	local -a items
	items=(
		'trace:Severity: detailed tracing (dim)'
		'debug:Severity: debug info (dim cyan)'
		'info:Severity: informational'
		'notice:Severity: notice (bold blue)'
		'warn:Severity: warning -> stderr (bold yellow)'
		'error:Severity: error -> stderr (bold red)'
		'fatal:Severity: fatal -> stderr (white on red)'
		'state:Kind: state (cyan)'
		'result:Kind: result (green)'
		'hint:Kind: hint (magenta)'
		'step:Kind: step (dim)'
		'banner:Kind: banner'
	)

	if ((CURRENT == 2)); then
		_describe -t levels 'log level/kind' items
	else
		_files
	fi
}

# `compdef` is provided by `compinit`, which (per ~/.zshrc) runs *after* this
# file is sourced from config.zsh. Register immediately if available, else
# defer registration until the first prompt (after compinit has run).
if ((${+functions[compdef]})); then
	compdef _log log
else
	autoload -Uz add-zsh-hook
	_log_register_compdef() {
		if ((${+functions[compdef]})); then
			compdef _log log
			add-zsh-hook -d precmd _log_register_compdef
			unfunction _log_register_compdef
		fi
	}
	add-zsh-hook precmd _log_register_compdef
fi
