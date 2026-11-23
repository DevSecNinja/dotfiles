#!/usr/bin/env bash
#
# Deletes untagged versions of a GHCR container package once they are older
# than the cut-off, without breaking multi-arch images
# (.github/workflows/cleanup-packages.yaml).
#
# A version is kept when it is tagged, newer than the cut-off, referenced by
# the manifest index of a kept version (per-platform images and buildx
# attestations, followed through nested indexes), or a referrer whose
# `subject` is kept (registry-pushed build provenance). Every manifest is read
# from the registry first; if any read fails, nothing is deleted.
#
# Deletes only with DRY_RUN=false; anything else only lists what would go.
#
# Env: GH_TOKEN (packages: write to delete, read to list), IMAGE_NAME,
# REGISTRY_OWNER (default: the lowercase repository owner), CUT_OFF_DAYS
# (default 7), DRY_RUN (default true). NOW (epoch seconds) is for tests.

set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN is required}"
: "${IMAGE_NAME:?IMAGE_NAME is required}"
owner="${REGISTRY_OWNER:-${GITHUB_REPOSITORY_OWNER:-}}"
owner="${owner,,}"
: "${owner:?REGISTRY_OWNER or GITHUB_REPOSITORY_OWNER is required}"
cut_off_days="${CUT_OFF_DAYS:-7}"
dry_run="${DRY_RUN:-true}"
now="${NOW:-$(date -u +%s)}"
cut_off=$((now - cut_off_days * 86400))
versions_api="/user/packages/container/${IMAGE_NAME}/versions"
accept="application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json"
accept="${accept},application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json"

fail() {
    echo "::error::$*; nothing was deleted."
    exit 1
}

versions="$(gh api --paginate "${versions_api}?per_page=100" | jq -s 'add // []')" ||
    fail "Could not list the versions of ${IMAGE_NAME}"

if ! token="$(curl -fsS -u "token:${GH_TOKEN}" \
    "https://ghcr.io/token?scope=repository:${owner}/${IMAGE_NAME}:pull" | jq -er '.token')"; then
    fail "Could not get a registry token for ghcr.io/${owner}/${IMAGE_NAME}"
fi

declare -A manifests=()
# Reads the manifest of digest $1 into manifests[$1].
read_manifest() {
    local digest="$1"
    [ -n "${manifests[${digest}]+set}" ] && return 0
    local body
    if ! body="$(curl -fsS -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
        "https://ghcr.io/v2/${owner}/${IMAGE_NAME}/manifests/${digest}")"; then
        fail "Could not read the manifest of ${digest}"
    fi
    manifests["${digest}"]="${body}"
}

declare -A protected=()
# Protects digest $1 and, through manifest indexes, everything it references.
protect() {
    local queue=("$1") digest child
    while [ "${#queue[@]}" -gt 0 ]; do
        digest="${queue[0]}"
        queue=("${queue[@]:1}")
        [ -n "${protected[${digest}]+set}" ] && continue
        protected["${digest}"]=1
        read_manifest "${digest}"
        while IFS= read -r child; do
            [ -n "${child}" ] && queue+=("${child}")
        done < <(jq -r '.manifests[]?.digest' <<<"${manifests[${digest}]}")
    done
}

# Kept roots: tagged versions and versions newer than the cut-off.
while IFS= read -r digest; do
    protect "${digest}"
done < <(jq -r --argjson cut_off "${cut_off}" '.[]
    | select((.metadata.container.tags | length) > 0 or (.updated_at | fromdateiso8601) >= $cut_off)
    | .name' <<<"${versions}")

# Candidates: untagged and older than the cut-off, as "id digest updated_at" lines.
candidates="$(jq -r --argjson cut_off "${cut_off}" '.[]
    | select((.metadata.container.tags | length) == 0 and (.updated_at | fromdateiso8601) < $cut_off)
    | "\(.id) \(.name) \(.updated_at)"' <<<"${versions}")"

# A candidate whose subject is protected (an attestation or signature of a
# kept image) is protected too; repeat until nothing changes.
changed=true
while [ "${changed}" = true ]; do
    changed=false
    while read -r _ digest _; do
        [ -z "${digest}" ] && continue
        [ -n "${protected[${digest}]+set}" ] && continue
        read_manifest "${digest}"
        subject="$(jq -r '.subject.digest // empty' <<<"${manifests[${digest}]}")"
        if [ -n "${subject}" ] && [ -n "${protected[${subject}]+set}" ]; then
            protect "${digest}"
            changed=true
        fi
    done <<<"${candidates}"
done

deletable=()
while read -r id digest updated; do
    [ -z "${digest}" ] && continue
    [ -n "${protected[${digest}]+set}" ] && continue
    deletable+=("${id} ${digest} ${updated}")
done <<<"${candidates}"

echo "${IMAGE_NAME}: $(jq 'length' <<<"${versions}") versions, ${#protected[@]} kept or referenced," \
    "${#deletable[@]} untagged and unreferenced older than ${cut_off_days} days."

for entry in "${deletable[@]}"; do
    read -r id digest updated <<<"${entry}"
    if [ "${dry_run}" = "false" ]; then
        echo "- delete ${digest} (version ${id}, updated ${updated})"
        gh api --method DELETE "${versions_api}/${id}" >/dev/null
    else
        echo "- would delete ${digest} (version ${id}, updated ${updated})"
    fi
done
