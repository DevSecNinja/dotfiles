#!/bin/sh

# -e: exit on error
# -u: exit on unset variables
set -eu

# Check if running in interactive mode
is_interactive() {
	# Return false (non-interactive) if:
	# - CI environment variable is set
	# - DEBIAN_FRONTEND is set to noninteractive
	# - Running in a devcontainer (REMOTE_CONTAINERS or CODESPACES env vars)
	# - stdin is not a terminal
	if [ "${CI:-}" = "true" ] ||
		[ "${DEBIAN_FRONTEND:-}" = "noninteractive" ] ||
		[ -n "${REMOTE_CONTAINERS:-}" ] ||
		[ -n "${CODESPACES:-}" ] ||
		! [ -t 0 ]; then
		return 1
	fi
	return 0
}

if ! chezmoi="$(command -v chezmoi)"; then
	echo "chezmoi not found, attempting to install..." >&2

	# Try brew first
	if command -v brew >/dev/null; then
		echo "Installing chezmoi with brew..." >&2
		brew install chezmoi
		chezmoi="$(command -v chezmoi)"
	# Try mise second
	elif command -v mise >/dev/null; then
		echo "Installing chezmoi with mise..." >&2
		mise use --global chezmoi@latest
		chezmoi="$(command -v chezmoi)"
	# Fall back to install script
	else
		bin_dir="${HOME}/.local/bin"
		chezmoi="${bin_dir}/chezmoi"
		echo "Installing chezmoi to '${chezmoi}'" >&2
		if command -v curl >/dev/null; then
			chezmoi_install_script="$(curl -fsLS https://get.chezmoi.io)"
		elif command -v wget >/dev/null; then
			chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
		else
			echo "To install chezmoi, you must have curl or wget installed." >&2
			exit 1
		fi
		sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
		unset chezmoi_install_script bin_dir
	fi
fi

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# Add --no-tty flag if not running interactively
if is_interactive; then
	set -- init --apply --source="${script_dir}"
else
	set -- init --apply --no-tty --source="${script_dir}"
fi

echo "Running 'chezmoi $*'" >&2
# exec: replace current process with chezmoi
exec "$chezmoi" "$@"
