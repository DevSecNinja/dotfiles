#!/bin/bash
# clipboard-copy - Copy stdin to the system clipboard, cross-platform
#
# Detects the first available clipboard tool in this order:
#   macOS    : pbcopy
#   Wayland  : wl-copy
#   X11      : xclip -selection clipboard, then xsel --clipboard --input
#   Windows  : clip.exe (WSL)
#
# Usage:
#   echo "hello" | clipboard-copy
#   clipboard-copy < file.txt
#   clipboard-copy --check       # exit 0 if a backend is available, 1 otherwise
#   clipboard-copy --tool        # print the backend that would be used
#
# Exit codes:
#   0  Success / backend found (with --check or --tool)
#   1  No clipboard backend available
#   2  Backend invocation failed

clipboard-copy() {
	local mode="copy"

	while [[ $# -gt 0 ]]; do
		case $1 in
		--check)
			mode="check"
			shift
			;;
		--tool)
			mode="tool"
			shift
			;;
		-h | --help)
			echo "Usage: clipboard-copy [--check|--tool]"
			echo "Copy stdin to the system clipboard."
			return 0
			;;
		*)
			echo "Unknown option: $1" >&2
			return 1
			;;
		esac
	done

	# Pick the first available backend. Order matters.
	local tool=""
	if [[ "$(uname)" == "Darwin" ]] && command -v pbcopy >/dev/null 2>&1; then
		tool="pbcopy"
	elif [[ -n "$WAYLAND_DISPLAY" ]] && command -v wl-copy >/dev/null 2>&1; then
		tool="wl-copy"
	elif command -v wl-copy >/dev/null 2>&1 && [[ -z "$DISPLAY" ]]; then
		tool="wl-copy"
	elif command -v xclip >/dev/null 2>&1; then
		tool="xclip"
	elif command -v xsel >/dev/null 2>&1; then
		tool="xsel"
	elif command -v clip.exe >/dev/null 2>&1; then
		tool="clip.exe"
	fi

	case "$mode" in
	check)
		[[ -n "$tool" ]] && return 0 || return 1
		;;
	tool)
		[[ -n "$tool" ]] || return 1
		echo "$tool"
		return 0
		;;
	esac

	if [[ -z "$tool" ]]; then
		echo "Error: no clipboard backend found (tried pbcopy, wl-copy, xclip, xsel, clip.exe)" >&2
		return 1
	fi

	case "$tool" in
	pbcopy) pbcopy ;;
	wl-copy) wl-copy ;;
	xclip) xclip -selection clipboard -in ;;
	xsel) xsel --clipboard --input ;;
	clip.exe) clip.exe ;;
	esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	clipboard-copy "$@"
fi
