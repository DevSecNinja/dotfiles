#!/bin/bash
# Reusable helpers for checking packages defined in .chezmoidata/packages.yaml.

detect_dotfiles_platform() {
	case "$(uname -s 2>/dev/null)" in
	Darwin)
		echo "darwin"
		;;
	Linux)
		if [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
			echo "wsl"
		else
			echo "linux"
		fi
		;;
	CYGWIN* | MINGW* | MSYS*)
		echo "windows"
		;;
	*)
		uname -s 2>/dev/null | tr '[:upper:]' '[:lower:]'
		;;
	esac
}

detect_dotfiles_install_type() {
	if [ -n "${CHEZMOI_INSTALL_TYPE:-}" ]; then
		echo "$CHEZMOI_INSTALL_TYPE"
		return 0
	fi

	if [ -n "${INSTALL_TYPE:-}" ]; then
		echo "$INSTALL_TYPE"
		return 0
	fi

	local hostname_value
	hostname_value="$(hostname 2>/dev/null || echo "")"

	case "$hostname_value" in
	SVLDEV*)
		echo "full"
		;;
	SVL*)
		echo "light"
		;;
	*)
		if [ -n "${CODESPACES:-}" ] || [ -n "${REMOTE_CONTAINERS:-}" ]; then
			echo "full"
		elif [ -n "${CI:-}" ]; then
			echo "light"
		else
			echo "full"
		fi
		;;
	esac
}

find_dotfiles_packages_file() {
	# Search priority:
	# 1. explicit environment overrides,
	# 2. known dotfiles/Chezmoi source directories,
	# 3. chezmoi source-path,
	# 4. path relative to this helper.
	if [ -n "${DOTFILES_PACKAGES_FILE:-}" ] && [ -f "$DOTFILES_PACKAGES_FILE" ]; then
		echo "$DOTFILES_PACKAGES_FILE"
		return 0
	fi

	if [ -n "${DOTFILES_ROOT:-}" ] && [ -f "$DOTFILES_ROOT/home/.chezmoidata/packages.yaml" ]; then
		echo "$DOTFILES_ROOT/home/.chezmoidata/packages.yaml"
		return 0
	fi

	if [ -n "${CHEZMOI_SOURCE_DIR:-}" ] && [ -f "$CHEZMOI_SOURCE_DIR/.chezmoidata/packages.yaml" ]; then
		echo "$CHEZMOI_SOURCE_DIR/.chezmoidata/packages.yaml"
		return 0
	fi

	if command -v chezmoi >/dev/null 2>&1; then
		local source_dir
		source_dir="$(chezmoi source-path 2>/dev/null || true)"
		if [ -n "$source_dir" ] && [ -f "$source_dir/.chezmoidata/packages.yaml" ]; then
			echo "$source_dir/.chezmoidata/packages.yaml"
			return 0
		fi
	fi

	local helper_dir
	helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
	if [ -f "$helper_dir/../../.chezmoidata/packages.yaml" ]; then
		echo "$helper_dir/../../.chezmoidata/packages.yaml"
		return 0
	fi

	return 1
}

normalize_package_name() {
	local package="$1"
	printf '%s' "$package" |
		sed -e 's/[[:space:]]#.*$//' \
			-e 's/^[[:space:]]*-[[:space:]]*//' \
			-e 's/^[[:space:]]*//' \
			-e 's/[[:space:]]*$//' \
			-e "s/^[\"']//" \
			-e "s/[\"']$//" |
		tr '[:upper:]' '[:lower:]'
}

package_id_suffix_matches() {
	local requested="$1"
	local candidate="$2"

	# Match package-manager IDs by suffix, such as "jdx.mise" for "mise".
	[ "$candidate" != "${candidate##*.}" ] && [ "${candidate##*.}" = "$requested" ]
}

package_name_matches() {
	local requested candidate
	requested="$(normalize_package_name "$1")"
	candidate="$(normalize_package_name "$2")"

	# Some package managers use reverse-DNS IDs, for example "jdx.mise".
	[ "$candidate" = "$requested" ] || package_id_suffix_matches "$requested" "$candidate"
}

packages_for_install_type() {
	local packages_file="$1"
	local platform="$2"
	local install_type="$3"

	awk -v platform="$platform" -v install_type="$install_type" '
		function indent(line) {
			match(line, /[^ ]/)
			return RSTART ? RSTART - 1 : length(line)
		}
		function wanted_mode(mode) {
			if (install_type == "full") {
				return mode == "light" || mode == "full"
			}
			return mode == install_type
		}
		{
			line = $0
			line_indent = indent(line)

			if (line ~ "^[[:space:]]{2}" platform ":[[:space:]]*$") {
				in_platform = 1
				platform_indent = line_indent
				next
			}

			if (in_platform && line_indent <= platform_indent && line !~ "^[[:space:]]*$") {
				in_platform = 0
				in_mode = 0
			}

			if (!in_platform) {
				next
			}

			if (line ~ "^[[:space:]]+(light|full):[[:space:]]*$") {
				mode = line
				sub(/^[[:space:]]+/, "", mode)
				sub(/:.*/, "", mode)
				in_mode = wanted_mode(mode)
				mode_indent = line_indent
				next
			}

			if (in_mode && line_indent <= mode_indent && line !~ "^[[:space:]]*-[[:space:]]+") {
				in_mode = 0
			}

			if (in_mode && line ~ "^[[:space:]]*-[[:space:]]+") {
				item = line
				sub(/^[[:space:]]*-[[:space:]]+/, "", item)
				sub(/[[:space:]]+#.*/, "", item)
				gsub(/^[[:space:]]+|[[:space:]]+$/, "", item)
				gsub(/^["\047]|["\047]$/, "", item)
				print item
			}
		}
	' "$packages_file"
}

package_required_for_install_type() {
	local package="$1"
	local install_type="${2:-$(detect_dotfiles_install_type)}"
	local platform="${3:-$(detect_dotfiles_platform)}"
	local packages_file="${4:-}"

	if [ "$platform" = "wsl" ]; then
		platform="linux"
	fi

	if [ -z "$packages_file" ]; then
		packages_file="$(find_dotfiles_packages_file)" || return 1
	fi

	[ -f "$packages_file" ] || return 1

	local candidate
	while IFS= read -r candidate; do
		if package_name_matches "$package" "$candidate"; then
			return 0
		fi
	done < <(packages_for_install_type "$packages_file" "$platform" "$install_type")

	return 1
}

package_required_for_current_install() {
	package_required_for_install_type "$1" "$(detect_dotfiles_install_type)" "$(detect_dotfiles_platform)" "${2:-}"
}

mise_required_for_current_install() {
	package_required_for_current_install "mise" "${1:-}"
}
