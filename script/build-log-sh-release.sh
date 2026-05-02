#!/usr/bin/env bash
# build-log-sh-release.sh - Package log.sh as a release tarball.
#
# Usage:
#   script/build-log-sh-release.sh [VERSION] [OUTPUT_DIR]
#
# When VERSION is not provided, it is read from the most recent git tag (or
# defaults to "v0.0.0-dev"). OUTPUT_DIR defaults to ./dist.
#
# Produces in OUTPUT_DIR:
#   log.sh                       - raw library file (for direct curl)
#   log.sh.sha256                - sha256 of log.sh
#   install-log-sh.sh            - installer for prefix-style installs
#   install-log-sh.sh.sha256     - sha256 of install-log-sh.sh
#   log-sh-<version>.tar.gz      - tarball with library + completions + LICENSE
#   log-sh-<version>.tar.gz.sha256
#
# The tarball layout is:
#   log-sh-<version>/
#     log.sh
#     install-log-sh.sh
#     LICENSE
#     README.md             (consumption snippet, generated)
#     completions/
#       log.fish
#       log.bash
#       log.zsh
#
# Exit codes: 0 success, non-zero on any failure (set -euo pipefail).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

version="${1:-}"
outdir="${2:-${REPO_ROOT}/dist}"

if [ -z "$version" ]; then
	if version="$(git describe --tags --abbrev=0 2>/dev/null)"; then
		:
	else
		version="v0.0.0-dev"
	fi
fi

case "$version" in
v*) ;;
*) version="v${version}" ;;
esac

src_log="${REPO_ROOT}/home/dot_config/shell/functions/log.sh"
src_installer="${REPO_ROOT}/script/install-log-sh.sh"
src_license="${REPO_ROOT}/LICENSE"
src_fish="${REPO_ROOT}/home/dot_config/fish/completions/log.fish"
src_bash="${REPO_ROOT}/home/dot_config/shell/completions.d/log.bash"
src_zsh="${REPO_ROOT}/home/dot_config/shell/completions.d/log.zsh"

for f in "$src_log" "$src_installer" "$src_license" "$src_fish" "$src_bash" "$src_zsh"; do
	if [ ! -f "$f" ]; then
		printf 'error: required source file missing: %s\n' "$f" >&2
		exit 1
	fi
done

mkdir -p "$outdir"
rm -f \
	"${outdir}/log.sh" \
	"${outdir}/log.sh.sha256" \
	"${outdir}/install-log-sh.sh" \
	"${outdir}/install-log-sh.sh.sha256" \
	"${outdir}/log-sh-${version}.tar.gz" \
	"${outdir}/log-sh-${version}.tar.gz.sha256"

# Raw single-file asset (for direct `curl ... -o scripts/lib/log.sh`).
cp "$src_log" "${outdir}/log.sh"
cp "$src_installer" "${outdir}/install-log-sh.sh"
chmod 0644 "${outdir}/log.sh"
chmod 0755 "${outdir}/install-log-sh.sh"

# Tarball with companion files.
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
pkgdir="${stage}/log-sh-${version}"
mkdir -p "${pkgdir}/completions"

cp "$src_log" "${pkgdir}/log.sh"
cp "$src_installer" "${pkgdir}/install-log-sh.sh"
cp "$src_license" "${pkgdir}/LICENSE"
cp "$src_fish" "${pkgdir}/completions/log.fish"
cp "$src_bash" "${pkgdir}/completions/log.bash"
cp "$src_zsh" "${pkgdir}/completions/log.zsh"

cat >"${pkgdir}/README.md" <<EOF
# log-sh ${version}

Reusable POSIX shell logging library extracted from
[DevSecNinja/dotfiles](https://github.com/DevSecNinja/dotfiles).

## Install

Prefix install (library + completions):

\`\`\`sh
tmp="\$(mktemp -d)"
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/${version}/install-log-sh.sh \\
  -o "\$tmp/install-log-sh.sh"
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/${version}/install-log-sh.sh.sha256 \\
  -o "\$tmp/install-log-sh.sh.sha256"
( cd "\$tmp" && sha256sum -c install-log-sh.sh.sha256 )
sh "\$tmp/install-log-sh.sh" --version ${version} --prefix "\$HOME/.local"
rm -rf "\$tmp"
\`\`\`

Vendored single file:

\`\`\`sh
mkdir -p scripts/lib
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/${version}/log.sh \\
  -o scripts/lib/log.sh
curl -fsSL https://github.com/DevSecNinja/dotfiles/releases/download/${version}/log.sh.sha256 \\
  -o scripts/lib/log.sh.sha256
( cd scripts/lib && sha256sum -c log.sh.sha256 )
\`\`\`

## Use

\`\`\`sh
. scripts/lib/log.sh
LOG_TAG=myscript
log_info "starting"
log_state "Phase 1"
log_result "all green"
\`\`\`

See the full reference in
[docs/logging.md](https://github.com/DevSecNinja/dotfiles/blob/${version}/docs/logging.md).
EOF

# Reproducible-ish tarball: pin owner/mtime to the source file's mtime.
mtime="$(date -u -r "$src_log" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null ||
	date -u '+%Y-%m-%dT%H:%M:%SZ')"

tar \
	--owner=0 --group=0 --numeric-owner \
	--mtime="$mtime" \
	--sort=name \
	-C "$stage" \
	-czf "${outdir}/log-sh-${version}.tar.gz" \
	"log-sh-${version}"

# sha256 sidecars.
(cd "$outdir" && sha256sum "log.sh" >"log.sh.sha256")
(cd "$outdir" && sha256sum "install-log-sh.sh" >"install-log-sh.sh.sha256")
(cd "$outdir" && sha256sum "log-sh-${version}.tar.gz" \
	>"log-sh-${version}.tar.gz.sha256")

printf 'Built release artifacts for %s in %s:\n' "$version" "$outdir"
ls -1 \
	"${outdir}/log.sh" \
	"${outdir}/log.sh.sha256" \
	"${outdir}/install-log-sh.sh" \
	"${outdir}/install-log-sh.sh.sha256" \
	"${outdir}/log-sh-${version}.tar.gz" \
	"${outdir}/log-sh-${version}.tar.gz.sha256"
