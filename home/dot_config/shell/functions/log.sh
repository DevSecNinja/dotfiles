#!/bin/sh
# log - Small reusable shell logging library.
#
# Source this file from Bash, Zsh, or POSIX sh scripts, or execute it directly:
#
#   # Bash/Zsh/sh
#   . "${HOME}/.config/shell/functions/log.sh"
#   LOG_LEVEL="${LOG_LEVEL:-INFO}"      # TRACE, DEBUG, INFO, NOTICE, WARN, ERROR, FATAL
#   LOG_TAG="my-script"                # logger(1) tag and terminal prefix
#   LOG_JOURNAL="auto"                 # auto, always, never
#   log INFO "starting work"
#   log_warn "continuing with a fallback"
#   log_error "failed to connect"
#
#   # Fish users can call the script through the generated Fish wrapper from
#   # config.fish, or run it directly:
#   #   log INFO "message from fish"
#   #   ~/.config/shell/functions/log.sh WARN "standalone message"
#
# Output behavior:
#   - INFO/NOTICE/DEBUG/TRACE messages go to stdout.
#   - WARN/ERROR/FATAL messages go to stderr.
#   - Timestamps are UTC ISO-8601 by default. Tests may set LOG_TIMESTAMP.
#   - No emoji is emitted. UTF-8 is not required for the default format.
#   - Color is used only when LOG_COLOR=always, or LOG_COLOR=auto with a TTY
#     stdout/stderr and a non-dumb TERM. NO_COLOR disables color.
#   - logger(1) integration is automatic when a syslog/journal socket appears
#     available. Set LOG_JOURNAL=always or never to override detection.
#   - File logging is disabled unless LOG_FILE is set with LOG_FILE_MAX_BYTES
#     or LOG_FILE_TTL_DAYS, so logs have an explicit rotation/lifetime policy.
#
# Bats/testing hooks:
#   LOG_TIMESTAMP fixes the timestamp.
#   LOG_LOGGER_COMMAND points at a stub logger executable.
#   LOG_JOURNAL=always forces the logger path to run.
#   LOG_COLOR=never keeps assertions free of ANSI escapes.

LOG_DEFAULT_LEVEL="${LOG_DEFAULT_LEVEL:-INFO}"

log__upper_level() {
	case "$1" in
	trace | TRACE) printf '%s\n' "TRACE" ;;
	debug | DEBUG) printf '%s\n' "DEBUG" ;;
	info | INFO | "") printf '%s\n' "INFO" ;;
	notice | NOTICE) printf '%s\n' "NOTICE" ;;
	warn | warning | WARN | WARNING) printf '%s\n' "WARN" ;;
	error | err | ERROR | ERR) printf '%s\n' "ERROR" ;;
	fatal | crit | critical | FATAL | CRIT | CRITICAL) printf '%s\n' "FATAL" ;;
	*) return 1 ;;
	esac
}

log__level_number() {
	case "$1" in
	TRACE) printf '%s\n' 10 ;;
	DEBUG) printf '%s\n' 20 ;;
	INFO) printf '%s\n' 30 ;;
	NOTICE) printf '%s\n' 35 ;;
	WARN) printf '%s\n' 40 ;;
	ERROR) printf '%s\n' 50 ;;
	FATAL) printf '%s\n' 60 ;;
	*) printf '%s\n' 30 ;;
	esac
}

log__priority() {
	case "$1" in
	TRACE | DEBUG) printf '%s\n' "debug" ;;
	INFO) printf '%s\n' "info" ;;
	NOTICE) printf '%s\n' "notice" ;;
	WARN) printf '%s\n' "warning" ;;
	ERROR) printf '%s\n' "err" ;;
	FATAL) printf '%s\n' "crit" ;;
	*) printf '%s\n' "info" ;;
	esac
}

log__color() {
	case "$1" in
	TRACE) printf '\033[2m' ;;
	DEBUG) printf '\033[36m' ;;
	INFO) printf '\033[32m' ;;
	NOTICE) printf '\033[34m' ;;
	WARN) printf '\033[33m' ;;
	ERROR | FATAL) printf '\033[31m' ;;
	*) printf '%s' "" ;;
	esac
}

log__use_color() {
	test -z "${NO_COLOR:-}" || return 1

	case "${LOG_COLOR:-auto}" in
	always | true | 1) return 0 ;;
	never | false | 0) return 1 ;;
	auto | "") ;;
	*) return 1 ;;
	esac

	test -t 1 || return 1
	test -t "$1" || return 1

	case "${TERM:-}" in
	"" | dumb) return 1 ;;
	*) return 0 ;;
	esac
}

log__timestamp() {
	if test -n "${LOG_TIMESTAMP:-}"; then
		printf '%s\n' "$LOG_TIMESTAMP"
	elif command -v date >/dev/null 2>&1; then
		date -u '+%Y-%m-%dT%H:%M:%SZ'
	else
		printf '%s\n' "0000-00-00T00:00:00Z"
	fi
}

log_level_enabled() {
	log__requested_level=$(log__upper_level "${1:-INFO}") || log__requested_level="INFO"
	log__minimum_level=$(log__upper_level "${LOG_LEVEL:-${LOG_MIN_LEVEL:-$LOG_DEFAULT_LEVEL}}") || log__minimum_level="$LOG_DEFAULT_LEVEL"

	test "$(log__level_number "$log__requested_level")" -ge "$(log__level_number "$log__minimum_level")"
}

log_set_level() {
	log__new_level=$(log__upper_level "${1:-}") || return 1
	LOG_LEVEL="$log__new_level"
	export LOG_LEVEL
}

log__stdio_fd() {
	case "$1" in
	WARN | ERROR | FATAL) printf '%s\n' 2 ;;
	*) printf '%s\n' 1 ;;
	esac
}

log__journal_available() {
	case "${LOG_JOURNAL:-auto}" in
	never | false | 0) return 1 ;;
	esac

	log__logger_command="${LOG_LOGGER_COMMAND:-logger}"
	command -v "$log__logger_command" >/dev/null 2>&1 || return 1

	case "${LOG_JOURNAL:-auto}" in
	always | true | 1) return 0 ;;
	esac

	test -S /run/systemd/journal/socket ||
		test -S /dev/log ||
		test -S /var/run/syslog ||
		test -S /var/run/log ||
		test -n "${JOURNAL_STREAM:-}" ||
		test -n "${INVOCATION_ID:-}"
}

log__write_journal() {
	log__journal_available || return 0

	log__logger_command="${LOG_LOGGER_COMMAND:-logger}"
	log__logger_tag="${LOG_TAG:-${0##*/}}"
	log__logger_priority=$(log__priority "$1")
	log__logger_message="$1 $2"

	"$log__logger_command" -t "$log__logger_tag" -p "user.$log__logger_priority" -- "$log__logger_message" >/dev/null 2>&1 ||
		"$log__logger_command" -t "$log__logger_tag" -p "user.$log__logger_priority" "$log__logger_message" >/dev/null 2>&1 ||
		:
}

log__file_enabled() {
	test -n "${LOG_FILE:-}" || return 1
	test -n "${LOG_FILE_MAX_BYTES:-}" || test -n "${LOG_FILE_TTL_DAYS:-}"
}

log__prepare_file() {
	log__file_enabled || return 1

	log__file_dir=$(dirname "$LOG_FILE" 2>/dev/null) || return 1
	test -d "$log__file_dir" || mkdir -p "$log__file_dir" 2>/dev/null || return 1

	if test -n "${LOG_FILE_TTL_DAYS:-}" && test -f "$LOG_FILE" && command -v find >/dev/null 2>&1; then
		find "$LOG_FILE" -type f -mtime +"$LOG_FILE_TTL_DAYS" -exec rm -f {} \; 2>/dev/null || :
	fi

	if test -n "${LOG_FILE_MAX_BYTES:-}" && test -f "$LOG_FILE" && command -v wc >/dev/null 2>&1; then
		log__file_size=$(wc -c <"$LOG_FILE" 2>/dev/null | tr -d ' ')
		case "$log__file_size:$LOG_FILE_MAX_BYTES" in
		*[!0123456789:]* | :* | *:) return 0 ;;
		esac
		if test "$log__file_size" -ge "$LOG_FILE_MAX_BYTES" 2>/dev/null; then
			mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || :
		fi
	fi
}

log__write_file() {
	log__prepare_file || return 0
	printf '%s\n' "$1" >>"$LOG_FILE" 2>/dev/null || :
}

log__write_stdio() {
	test "${LOG_TO_STDIO:-1}" = "0" && return 0

	log__write_fd=$(log__stdio_fd "$1")
	log__write_line="$2"

	if log__use_color "$log__write_fd"; then
		log__write_reset=$(printf '\033[0m')
		log__write_color=$(log__color "$1")
		if test "$log__write_fd" = 2; then
			printf '%s%s%s\n' "$log__write_color" "$log__write_line" "$log__write_reset" >&2
		else
			printf '%s%s%s\n' "$log__write_color" "$log__write_line" "$log__write_reset"
		fi
	else
		if test "$log__write_fd" = 2; then
			printf '%s\n' "$log__write_line" >&2
		else
			printf '%s\n' "$log__write_line"
		fi
	fi
}

log() {
	log__input_level=$(log__upper_level "${1:-}") && shift || log__input_level="INFO"
	log__message="$*"

	test -n "$log__message" || log__message="-"
	log_level_enabled "$log__input_level" || return 0

	log__tag="${LOG_TAG:-${0##*/}}"
	log__line="$(log__timestamp) $log__input_level $log__tag: $log__message"

	log__write_stdio "$log__input_level" "$log__line"
	log__write_file "$log__line"
	log__write_journal "$log__input_level" "$log__message"
}

log_trace() {
	log TRACE "$@"
}

log_debug() {
	log DEBUG "$@"
}

log_info() {
	log INFO "$@"
}

log_notice() {
	log NOTICE "$@"
}

log_warn() {
	log WARN "$@"
}

log_error() {
	log ERROR "$@"
}

log_fatal() {
	log FATAL "$@"
}

log__is_sourced() {
	if test -n "${ZSH_EVAL_CONTEXT:-}"; then
		case "$ZSH_EVAL_CONTEXT" in
		*:file:*) return 0 ;;
		*:file) return 0 ;;
		esac
	fi

	# shellcheck disable=SC3028 # BASH_SOURCE is intentionally used only inside Bash.
	if test -n "${BASH_VERSION:-}" && test -n "${BASH_SOURCE:-}"; then
		test "${BASH_SOURCE:-$0}" != "$0"
		return
	fi

	return 1
}

if ! log__is_sourced && test "${0##*/}" = "log.sh"; then
	log "$@"
fi
