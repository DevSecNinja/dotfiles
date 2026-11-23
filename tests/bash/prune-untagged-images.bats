#!/usr/bin/env bats
# Tests for .github/scripts/prune-untagged-images.sh, which
# .github/workflows/cleanup-packages.yaml runs to prune untagged GHCR
# versions without breaking multi-arch images. gh and curl are stubbed.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SCRIPT="${REPO_ROOT}/.github/scripts/prune-untagged-images.sh"
	FIXTURES="$(mktemp -d)"
	export FIXTURES
	mkdir -p "${FIXTURES}/bin" "${FIXTURES}/manifests"
	: >"${FIXTURES}/deletes"

	cat >"${FIXTURES}/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "api --paginate" ]; then
	cat "${FIXTURES}/versions.json"
elif [ "$1 $2 $3" = "api --method DELETE" ]; then
	echo "$4" >>"${FIXTURES}/deletes"
else
	echo "unexpected gh $*" >&2
	exit 1
fi
EOF
	cat >"${FIXTURES}/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${*: -1}"
case "${url}" in
*/token\?*)
	[ -n "${TOKEN_FAIL:-}" ] && exit 22
	echo '{"token": "registry-token"}'
	;;
*/manifests/*)
	digest="${url##*/}"
	file="${FIXTURES}/manifests/${digest/:/_}.json"
	[ -f "${file}" ] || exit 22
	cat "${file}"
	;;
*) exit 22 ;;
esac
EOF
	chmod +x "${FIXTURES}/bin/gh" "${FIXTURES}/bin/curl"

	# Now is 2026-11-23T00:00:00Z; the 7-day cut-off is 2026-11-16.
	export NOW=1795392000 GH_TOKEN=token IMAGE_NAME=dotfiles-devcontainer REGISTRY_OWNER=DevSecNinja
	old="2026-11-01T00:00:00Z"
	recent="2026-11-20T00:00:00Z"
	# Version 7 comes before the attestation it signs (6), so protecting it
	# needs a second pass.
	cat >"${FIXTURES}/versions.json" <<EOF
[
  {"id": 1, "name": "sha256:latest", "updated_at": "${old}", "metadata": {"container": {"tags": ["latest"]}}},
  {"id": 2, "name": "sha256:amd64", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 3, "name": "sha256:arm64-index", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 4, "name": "sha256:arm64", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 5, "name": "sha256:buildx-attestation", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 7, "name": "sha256:signature", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 6, "name": "sha256:provenance", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 8, "name": "sha256:orphan", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 9, "name": "sha256:orphan-index", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 10, "name": "sha256:orphan-child", "updated_at": "${old}", "metadata": {"container": {"tags": []}}},
  {"id": 11, "name": "sha256:in-flight", "updated_at": "${recent}", "metadata": {"container": {"tags": []}}},
  {"id": 12, "name": "sha256:in-flight-child", "updated_at": "${old}", "metadata": {"container": {"tags": []}}}
]
EOF

	index sha256:latest sha256:amd64 sha256:arm64-index sha256:buildx-attestation
	manifest sha256:amd64
	index sha256:arm64-index sha256:arm64
	manifest sha256:arm64
	manifest sha256:buildx-attestation
	manifest sha256:provenance sha256:latest
	manifest sha256:signature sha256:provenance
	manifest sha256:orphan
	index sha256:orphan-index sha256:orphan-child
	manifest sha256:orphan-child
	index sha256:in-flight sha256:in-flight-child
	manifest sha256:in-flight-child
}

teardown() {
	rm -rf "${FIXTURES}"
}

# Writes an image index $1 that references the digests $2...
index() {
	local digest="$1"
	shift
	printf '%s\n' "$@" | jq -R '{digest: .}' | jq -s '{mediaType: "application/vnd.oci.image.index.v1+json", manifests: .}' \
		>"${FIXTURES}/manifests/${digest/:/_}.json"
}

# Writes an image manifest $1, with subject $2 if given.
manifest() {
	jq -n --arg subject "${2:-}" '{mediaType: "application/vnd.oci.image.manifest.v1+json"}
		+ if $subject == "" then {} else {subject: {digest: $subject}} end' >"${FIXTURES}/manifests/${1/:/_}.json"
}

prune() {
	PATH="${FIXTURES}/bin:${PATH}" bash "${SCRIPT}"
}

@test "prune-untagged-images: deletes only old, untagged, unreferenced versions" {
	DRY_RUN=false run prune
	[ "$status" -eq 0 ]
	[ "$(sort "${FIXTURES}/deletes")" = "$(printf '%s\n' \
		/user/packages/container/dotfiles-devcontainer/versions/10 \
		/user/packages/container/dotfiles-devcontainer/versions/8 \
		/user/packages/container/dotfiles-devcontainer/versions/9)" ]
	[[ "$output" == *"12 versions, 9 kept or referenced, 3 untagged and unreferenced older than 7 days."* ]]
	[[ "$output" == *"- delete sha256:orphan (version 8, updated 2026-11-01T00:00:00Z)"* ]]
}

@test "prune-untagged-images: dry run is the default" {
	run prune
	[ "$status" -eq 0 ]
	[ ! -s "${FIXTURES}/deletes" ]
	[[ "$output" == *"- would delete sha256:orphan-index (version 9, updated 2026-11-01T00:00:00Z)"* ]]
}

@test "prune-untagged-images: only DRY_RUN=false deletes" {
	DRY_RUN=no run prune
	[ "$status" -eq 0 ]
	[ ! -s "${FIXTURES}/deletes" ]
}

@test "prune-untagged-images: an unreadable index of a kept image deletes nothing" {
	rm "${FIXTURES}/manifests/sha256_latest.json"
	DRY_RUN=false run prune
	[ "$status" -ne 0 ]
	[ ! -s "${FIXTURES}/deletes" ]
	[[ "$output" == *"::error::Could not read the manifest of sha256:latest; nothing was deleted."* ]]
}

@test "prune-untagged-images: an unreadable candidate deletes nothing" {
	rm "${FIXTURES}/manifests/sha256_orphan.json"
	DRY_RUN=false run prune
	[ "$status" -ne 0 ]
	[ ! -s "${FIXTURES}/deletes" ]
}

@test "prune-untagged-images: no registry token deletes nothing" {
	TOKEN_FAIL=1 DRY_RUN=false run prune
	[ "$status" -ne 0 ]
	[ ! -s "${FIXTURES}/deletes" ]
	[[ "$output" == *"::error::Could not get a registry token for ghcr.io/devsecninja/dotfiles-devcontainer"* ]]
}
