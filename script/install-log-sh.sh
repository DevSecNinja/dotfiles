#!/bin/sh
# install-log-sh.sh - Install log.sh from DevSecNinja/dotfiles releases.
#
# Usage:
#   install-log-sh.sh [--version vX.Y.Z] [--prefix PREFIX]
#
# Defaults:
#   --version  latest GitHub Release
#   --prefix   $HOME/.local

set -eu

repo="DevSecNinja/dotfiles"
version="${LOG_SH_VERSION:-}"
prefix="${PREFIX:-${HOME:-.}/.local}"
base_url="${LOG_SH_BASE_URL:-}"

usage() {
	cat <<'EOF'
Usage: install-log-sh.sh [OPTIONS]

Install the packaged log.sh release tarball.

Options:
  -v, --version VERSION   Release tag to install (default: latest)
  -p, --prefix PREFIX     Install prefix (default: $HOME/.local)
      --base-url URL      Release asset base URL or local directory
  -h, --help              Show this help

Installs:
  PREFIX/lib/log-sh/log.sh
  PREFIX/share/bash-completion/completions/log
  PREFIX/share/zsh/site-functions/_log
  PREFIX/share/fish/vendor_completions.d/log.fish
  PREFIX/share/doc/log-sh/README.md
  PREFIX/share/licenses/log-sh/LICENSE
EOF
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

download() {
	src=$1
	dest=$2

	case "$src" in
	http://* | https://*)
		if command -v curl >/dev/null 2>&1; then
			curl -fsSL "$src" -o "$dest"
		elif command -v wget >/dev/null 2>&1; then
			wget -O "$dest" "$src"
		else
			die "curl or wget is required to download $src"
		fi
		;;
	file://*)
		cp "${src#file://}" "$dest"
		;;
	*)
		if [ -f "$src" ]; then
			cp "$src" "$dest"
		else
			die "unsupported URL or missing local file: $src"
		fi
		;;
	esac
}

while [ "$#" -gt 0 ]; do
	case "$1" in
	-v | --version)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		version=$2
		shift 2
		;;
	-p | --prefix)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		prefix=$2
		shift 2
		;;
	--base-url)
		[ "$#" -ge 2 ] || die "$1 requires a value"
		base_url=$2
		shift 2
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		die "unknown option: $1"
		;;
	esac
done

tmp="$(mktemp -d "${TMPDIR:-/tmp}/log-sh-install.XXXXXX")" ||
	die "could not create temporary directory"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

if [ -z "$version" ]; then
	latest_json="${tmp}/latest.json"
	download "https://api.github.com/repos/${repo}/releases/latest" "$latest_json" ||
		die "could not download latest release metadata for ${repo}"
	if command -v jq >/dev/null 2>&1; then
		version="$(jq -r '.tag_name // empty' "$latest_json")"
	else
		version="$(awk -F '"' '/"tag_name"[[:space:]]*:/ { print $4; exit }' "$latest_json")"
	fi
	[ -n "$version" ] || die "could not determine latest release tag"
fi

case "$version" in
v*) ;;
*) version="v${version}" ;;
esac

if [ -z "$base_url" ]; then
	base_url="https://github.com/${repo}/releases/download/${version}"
fi

asset="log-sh-${version}.tar.gz"
download "${base_url%/}/${asset}" "${tmp}/${asset}" ||
	die "could not download ${asset}"
download "${base_url%/}/${asset}.sha256" "${tmp}/${asset}.sha256" ||
	die "could not download ${asset}.sha256"

if command -v sha256sum >/dev/null 2>&1; then
	(cd "$tmp" && sha256sum -c "${asset}.sha256") ||
		die "checksum verification failed for ${asset}"
elif command -v shasum >/dev/null 2>&1; then
	(cd "$tmp" && shasum -a 256 -c "${asset}.sha256") ||
		die "checksum verification failed for ${asset}"
else
	die "sha256sum or shasum is required to verify ${asset}"
fi

tar -xzf "${tmp}/${asset}" -C "$tmp" ||
	die "could not extract ${asset}"
pkgdir="${tmp}/log-sh-${version}"
[ -d "$pkgdir" ] ||
	die "release archive did not contain the expected top-level ${pkgdir##*/} directory"

mkdir -p \
	"${prefix}/lib/log-sh" \
	"${prefix}/share/bash-completion/completions" \
	"${prefix}/share/zsh/site-functions" \
	"${prefix}/share/fish/vendor_completions.d" \
	"${prefix}/share/doc/log-sh" \
	"${prefix}/share/licenses/log-sh"

cp "${pkgdir}/log.sh" "${prefix}/lib/log-sh/log.sh"
cp "${pkgdir}/completions/log.bash" "${prefix}/share/bash-completion/completions/log"
cp "${pkgdir}/completions/log.zsh" "${prefix}/share/zsh/site-functions/_log"
cp "${pkgdir}/completions/log.fish" "${prefix}/share/fish/vendor_completions.d/log.fish"
cp "${pkgdir}/README.md" "${prefix}/share/doc/log-sh/README.md"
cp "${pkgdir}/LICENSE" "${prefix}/share/licenses/log-sh/LICENSE"

chmod 0644 \
	"${prefix}/lib/log-sh/log.sh" \
	"${prefix}/share/bash-completion/completions/log" \
	"${prefix}/share/zsh/site-functions/_log" \
	"${prefix}/share/fish/vendor_completions.d/log.fish" \
	"${prefix}/share/doc/log-sh/README.md" \
	"${prefix}/share/licenses/log-sh/LICENSE"

printf 'Installed log.sh %s to %s\n' "$version" "$prefix"
printf 'Source it with: . "%s/lib/log-sh/log.sh"\n' "$prefix"
