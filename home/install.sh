#!/bin/sh

# -e: exit on error
# -u: exit on unset variables
set -eu

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

if [ -f "${script_dir}/dot_config/shell/functions/log.sh" ]; then
	# shellcheck source=home/dot_config/shell/functions/log.sh
	. "${script_dir}/dot_config/shell/functions/log.sh"
	LOG_TAG="install"
else
	log_warn() { printf '%s\n' "$*" >&2; }
	log_error() { printf '%s\n' "$*" >&2; }
	log_state() { printf '%s\n' "$*" >&2; }
fi

read_required_chezmoi_version() {
	version_file="${script_dir}/.chezmoiversion"
	if [ -f "$version_file" ]; then
		tr -d '[:space:]' <"$version_file"
	fi
}

chezmoi_version() {
	"$1" --version 2>/dev/null | sed -n 's/^chezmoi version \([0-9][^ ]*\).*/\1/p; s/^chezmoi \([0-9][^ ]*\).*/\1/p' | head -n 1
}

version_at_least() {
	awk -v have="$1" -v need="$2" '
		BEGIN {
			split(have, h, ".")
			split(need, n, ".")
			for (i = 1; i <= 3; i++) {
				hv = h[i] + 0
				nv = n[i] + 0
				if (hv > nv) exit 0
				if (hv < nv) exit 1
			}
			exit 0
		}
	'
}

install_chezmoi_from_release() {
	required_version="$1"
	bin_dir="${HOME}/.local/bin"
	chezmoi="${bin_dir}/chezmoi"

	if [ -n "$required_version" ]; then
		log_state "Installing chezmoi ${required_version} to '${chezmoi}'"
	else
		log_state "Installing latest chezmoi to '${chezmoi}'"
	fi

	if command -v curl >/dev/null; then
		chezmoi_install_script="$(curl -fsLS https://get.chezmoi.io)"
	elif command -v wget >/dev/null; then
		chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
	else
		log_error "To install chezmoi, you must have curl or wget installed."
		exit 1
	fi

	if [ -n "$required_version" ]; then
		sh -c "${chezmoi_install_script}" -- -b "${bin_dir}" -t "v${required_version}"
	else
		sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
	fi
	unset chezmoi_install_script bin_dir required_version
}

required_chezmoi_version="$(read_required_chezmoi_version)"

if ! chezmoi="$(command -v chezmoi)"; then
	# Check if chezmoi is already installed at the expected fallback path but not in PATH
	# (e.g. in a prebuilt devcontainer image where ~/.local/bin is not yet in PATH)
	if [ -x "${HOME}/.local/bin/chezmoi" ]; then
		chezmoi="${HOME}/.local/bin/chezmoi"
	else
		log_warn "chezmoi not found, attempting to install..."
	fi
fi

if [ -x "${chezmoi:-}" ] && [ -n "$required_chezmoi_version" ]; then
	installed_chezmoi_version="$(chezmoi_version "$chezmoi")"
	if [ -z "$installed_chezmoi_version" ] || ! version_at_least "$installed_chezmoi_version" "$required_chezmoi_version"; then
		log_warn "chezmoi ${installed_chezmoi_version:-unknown} is older than required ${required_chezmoi_version}"
		install_chezmoi_from_release "$required_chezmoi_version"
	fi
	unset installed_chezmoi_version
fi

if ! [ -x "${chezmoi:-}" ]; then
	if [ -n "$required_chezmoi_version" ]; then
		install_chezmoi_from_release "$required_chezmoi_version"
	# Try brew first
	elif command -v brew >/dev/null; then
		log_state "Installing chezmoi with brew..."
		brew install chezmoi
		chezmoi="$(command -v chezmoi)"
	# Try mise second
	elif command -v mise >/dev/null; then
		log_state "Installing chezmoi with mise..."
		mise use --global chezmoi@latest
		chezmoi="$(command -v chezmoi)"
	# Fall back to install script
	else
		install_chezmoi_from_release ""
	fi
fi

# Check if running in non-interactive environment
# - stdin is not a TTY
# - CI environment variables are set
# - Running inside a devcontainer or Codespace
is_non_interactive=false
if [ ! -t 0 ] || [ "${CI:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${TF_BUILD:-}" = "true" ] || [ "${REMOTE_CONTAINERS:-}" = "true" ] || [ "${CODESPACES:-}" = "true" ]; then
	is_non_interactive=true
fi

# Build chezmoi arguments
set -- init --apply

# Add --no-tty and --force flags for non-interactive environments
# --no-tty: prevent TTY input prompts
# --force: overwrite modified managed files without prompting
if [ "$is_non_interactive" = true ]; then
	set -- "$@" --no-tty --force
fi

set -- "$@" --source="${script_dir}"

log_state "Running 'chezmoi $*'"
# exec: replace current process with chezmoi
exec "$chezmoi" "$@"
