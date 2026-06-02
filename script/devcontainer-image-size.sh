#!/usr/bin/env bash
# Emit a Markdown "Image size" section for a published (multi-arch)
# devcontainer image. Sizes are the compressed download sizes summed from the
# OCI/Docker manifest (config + layers), matching the bytes a client pulls.

set -euo pipefail

image_ref="${1:-}"
if [ -z "$image_ref" ]; then
	echo "usage: devcontainer-image-size.sh <image-ref>" >&2
	exit 1
fi

# Repository portion of the reference (without tag), used to address the
# per-platform manifests by digest.
image_name="${image_ref%%@*}"
image_name="${image_name%:*}"

human_size() {
	awk -v bytes="${1:-0}" 'BEGIN {
		if (bytes + 0 <= 0) { printf "unknown"; exit }
		split("B KB MB GB TB", units, " ")
		i = 1
		size = bytes
		while (size >= 1024 && i < 5) { size /= 1024; i++ }
		printf "%.1f %s", size, units[i]
	}'
}

# Sum config + layer sizes from a single-platform manifest JSON on stdin.
manifest_bytes() {
	jq '[.config.size // 0] + [(.layers // [])[].size] | add // 0'
}

manifest_layers() {
	jq '(.layers // []) | length'
}

emit_line() {
	local platform="$1" bytes="$2" layers="$3"
	local noun="layers"
	[ "$layers" = "1" ] && noun="layer"
	printf -- "- \`%s\`: %s compressed (%s %s)\n" \
		"$platform" "$(human_size "$bytes")" "$layers" "$noun"
}

printf '## Image size\n\n'

list_json="$(docker manifest inspect "$image_ref")"

if printf '%s' "$list_json" | jq -e '.manifests' >/dev/null 2>&1; then
	while IFS=$'\t' read -r digest os arch variant; do
		[ -n "$digest" ] || continue
		platform="${os}/${arch}"
		if [ -n "$variant" ] && [ "$variant" != "null" ]; then
			platform="${platform}/${variant}"
		fi
		plat_json="$(docker manifest inspect "${image_name}@${digest}")"
		bytes="$(printf '%s' "$plat_json" | manifest_bytes)"
		layers="$(printf '%s' "$plat_json" | manifest_layers)"
		emit_line "$platform" "$bytes" "$layers"
	done < <(printf '%s' "$list_json" | jq -r '
		.manifests[]
		| select(.platform.os != "unknown" and .platform.architecture != "unknown")
		| [.digest, .platform.os, .platform.architecture, (.platform.variant // "")]
		| @tsv')
else
	bytes="$(printf '%s' "$list_json" | manifest_bytes)"
	layers="$(printf '%s' "$list_json" | manifest_layers)"
	emit_line "single-arch" "$bytes" "$layers"
fi
