#!/usr/bin/env bash
# Generate a human-readable manifest for the prebuilt devcontainer image.

set -euo pipefail

output_dir="${1:-/usr/local/share/dotfiles-devcontainer}"
manifest_file="${output_dir}/manifest.md"
release_notes_file="${output_dir}/release-notes.md"

image_version="${DOTFILES_DEVCONTAINER_VERSION:-latest}"
image_revision="${DOTFILES_DEVCONTAINER_REVISION:-unknown}"
generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
os_name="unknown"

if [ -r /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	os_name="${PRETTY_NAME:-${NAME:-unknown}}"
fi

clean_inline() {
	printf '%s' "${1:-unknown}" | tr -d '[:cntrl:]' | sed "s/\`/'/g"
}

tool_version() {
	local label="$1"
	local command_name="$2"
	shift 2
	local version

	if ! command -v "$command_name" >/dev/null 2>&1; then
		return 0
	fi

	version="$("$@" 2>&1 | head -n 1 || true)"
	if [ -z "$version" ]; then
		version="installed at $(command -v "$command_name")"
	fi

	printf -- "- \`%s\`: %s\n" "$(clean_inline "$label")" "$(clean_inline "$version")"
}

write_key_tools() {
	tool_version "Bash" bash bash --version
	tool_version "Fish" fish fish --version
	tool_version "Git" git git --version
	tool_version "Git LFS" git-lfs git-lfs --version
	tool_version "GitHub CLI" gh gh --version
	tool_version "Chezmoi" chezmoi chezmoi --version
	tool_version "mise" mise mise --version
	tool_version "jq" jq jq --version
	tool_version "PowerShell" pwsh pwsh --version
	tool_version "Python" python3 python3 --version
	tool_version "pip" pip3 pip3 --version
	tool_version "Node.js" node node --version
	tool_version "npm" npm npm --version
	tool_version "Task" task task --version
	tool_version "ShellCheck" shellcheck shellcheck --version
}

write_apt_packages() {
	if ! command -v dpkg-query >/dev/null 2>&1; then
		printf '_No dpkg package database found._\n'
		return 0
	fi

	dpkg-query -W -f='- `${binary:Package}`: ${Version}\n' 2>/dev/null | LC_ALL=C sort
}

write_homebrew_packages() {
	local brew_bin=""

	if command -v brew >/dev/null 2>&1; then
		brew_bin="$(command -v brew)"
	elif [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
		brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
	fi

	if [ -z "$brew_bin" ]; then
		printf '_Homebrew is not installed._\n'
		return 0
	fi

	local brew_packages
	brew_packages="$(mktemp)"

	if ! "$brew_bin" list --versions >"$brew_packages" 2>/dev/null; then
		printf '_Homebrew package list is unavailable._\n'
		rm -f "$brew_packages"
		return 0
	fi

	if [ ! -s "$brew_packages" ]; then
		printf '_No Homebrew packages installed._\n'
		rm -f "$brew_packages"
		return 0
	fi

	LC_ALL=C sort "$brew_packages" | while IFS= read -r package; do
		printf -- "- \`%s\`\n" "$(clean_inline "$package")"
	done
	rm -f "$brew_packages"
}

write_mise_tools() {
	if ! command -v mise >/dev/null 2>&1; then
		printf '_mise is not installed._\n'
		return 0
	fi

	if ! MISE_YES=1 mise ls --current 2>/dev/null; then
		printf '_mise tool list is unavailable._\n'
		return 0
	fi
}

mkdir -p "$output_dir"

{
	printf '# Devcontainer release notes\n\n'
	printf -- "- Image version: \`%s\`\n" "$(clean_inline "$image_version")"
	printf -- "- Image revision: \`%s\`\n" "$(clean_inline "$image_revision")"
	printf -- "- Base OS: \`%s\`\n" "$(clean_inline "$os_name")"
	printf -- "- Generated at: \`%s\`\n\n" "$(clean_inline "$generated_at")"
	printf '## Key tools\n\n'
	write_key_tools
	printf "\nFull package inventory: \`/usr/local/share/dotfiles-devcontainer/manifest.md\`\n"
} >"$release_notes_file"

{
	printf '# Devcontainer software manifest\n\n'
	printf -- "- Image version: \`%s\`\n" "$(clean_inline "$image_version")"
	printf -- "- Image revision: \`%s\`\n" "$(clean_inline "$image_revision")"
	printf -- "- Base OS: \`%s\`\n" "$(clean_inline "$os_name")"
	printf -- "- Generated at: \`%s\`\n\n" "$(clean_inline "$generated_at")"
	printf '## Key tools\n\n'
	write_key_tools
	printf '\n## mise tools\n\n'
	printf '```text\n'
	write_mise_tools
	printf '```\n\n'
	printf '## Homebrew packages\n\n'
	write_homebrew_packages
	printf '\n## APT packages\n\n'
	write_apt_packages
} >"$manifest_file"

printf 'Wrote devcontainer software manifest to %s\n' "$output_dir"
