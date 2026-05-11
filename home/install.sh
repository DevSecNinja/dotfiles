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
	log_hint() { printf '%s\n' "$*" >&2; }
	log_state() { printf '%s\n' "$*" >&2; }
fi

read_required_chezmoi_version() {
	version_file="${script_dir}/.chezmoiversion"
	if [ -f "$version_file" ]; then
		tr -d '[:space:]' <"$version_file"
	fi
}

chezmoi_version() {
	# Handle both "chezmoi version X.Y.Z" and "chezmoi X.Y.Z" output formats.
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

find_chezmoi() {
	if command -v chezmoi >/dev/null 2>&1; then
		command -v chezmoi
	elif [ -x "${HOME}/.local/bin/chezmoi" ]; then
		printf '%s\n' "${HOME}/.local/bin/chezmoi"
	fi
}

use_required_chezmoi_version() {
	chezmoi="$(find_chezmoi || true)"
	use_required_chezmoi_binary "${chezmoi:-}" "$1"
}

use_required_chezmoi_binary() {
	chezmoi="$1"
	[ -x "${chezmoi:-}" ] || return 1

	required_version="$2"
	installed_chezmoi_version="$(chezmoi_version "$chezmoi")"
	if [ -n "$installed_chezmoi_version" ] && version_at_least "$installed_chezmoi_version" "$required_version"; then
		return 0
	fi

	return 1
}

install_required_chezmoi_with_package_manager() {
	required_version="$1"

	if command -v mise >/dev/null 2>&1; then
		log_state "Installing chezmoi ${required_version} with mise"
		MISE_YES=1 mise use --global "chezmoi@${required_version}" || log_warn "mise could not install chezmoi ${required_version}; its registry may need updating"
		mise_chezmoi="$(MISE_YES=1 mise which chezmoi 2>/dev/null || true)"
		if use_required_chezmoi_binary "$mise_chezmoi" "$required_version"; then
			return 0
		fi
	fi

	if command -v brew >/dev/null 2>&1; then
		log_state "Installing chezmoi ${required_version} with Homebrew"
		if brew list chezmoi >/dev/null 2>&1; then
			brew upgrade chezmoi || log_warn "Homebrew could not upgrade chezmoi to the required version"
		else
			brew install chezmoi || log_warn "Homebrew could not install chezmoi to the required version"
		fi
		if use_required_chezmoi_version "$required_version"; then
			return 0
		fi
	fi

	log_error "No supported package manager provided chezmoi ${required_version} or later."
	log_hint "Update package manager metadata (for example, 'mise plugins update' or 'brew update') and re-run this installer."
	exit 1
}

install_latest_chezmoi() {
	# Try brew first
	if command -v brew >/dev/null; then
		log_state "Installing chezmoi with brew..."
		brew install chezmoi
		chezmoi="$(command -v chezmoi)"
	# Try mise second
	elif command -v mise >/dev/null; then
		log_state "Installing chezmoi with mise..."
		MISE_YES=1 mise use --global chezmoi@latest
		chezmoi="$(MISE_YES=1 mise which chezmoi 2>/dev/null || find_chezmoi)"
	# Fall back to install script when the repository does not pin a version
	else
		bin_dir="${HOME}/.local/bin"
		chezmoi="${bin_dir}/chezmoi"
		log_state "Installing latest chezmoi to '${chezmoi}'"
		if command -v curl >/dev/null; then
			chezmoi_install_script="$(curl -fsLS https://get.chezmoi.io)"
		elif command -v wget >/dev/null; then
			chezmoi_install_script="$(wget -qO- https://get.chezmoi.io)"
		else
			log_error "To install chezmoi, you must have curl or wget installed."
			exit 1
		fi
		sh -c "${chezmoi_install_script}" -- -b "${bin_dir}"
		unset chezmoi_install_script bin_dir
	fi
}

required_chezmoi_version="$(read_required_chezmoi_version)"

if ! chezmoi="$(find_chezmoi)"; then
	# Check if chezmoi is already installed at the expected fallback path but not in PATH
	# (e.g. in a prebuilt devcontainer image where ~/.local/bin is not yet in PATH)
	log_warn "chezmoi not found, attempting to install..."
fi

if [ -x "${chezmoi:-}" ] && [ -n "$required_chezmoi_version" ]; then
	installed_chezmoi_version="$(chezmoi_version "$chezmoi")"
	if [ -z "$installed_chezmoi_version" ] || ! version_at_least "$installed_chezmoi_version" "$required_chezmoi_version"; then
		log_warn "chezmoi ${installed_chezmoi_version:-unknown} is older than required ${required_chezmoi_version}"
		install_required_chezmoi_with_package_manager "$required_chezmoi_version"
	fi
	unset installed_chezmoi_version
fi

if ! [ -x "${chezmoi:-}" ]; then
	if [ -n "$required_chezmoi_version" ]; then
		install_required_chezmoi_with_package_manager "$required_chezmoi_version"
	else
		install_latest_chezmoi
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
