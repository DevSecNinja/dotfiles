#!/usr/bin/env bats
# Tests for devcontainer configuration validation

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "validate-devcontainer: Dockerfile removes Homebrew cache during prebuild" {
	dockerfile="$REPO_ROOT/.devcontainer/Dockerfile"

	[ -f "$dockerfile" ]
	run grep -F 'brew cleanup --prune=all -s' "$dockerfile"
	[ "$status" -eq 0 ]

	run grep -F 'rm -rf "${HOME}/.cache/Homebrew"' "$dockerfile"
	[ "$status" -eq 0 ]
}

@test "validate-devcontainer: prebuild uses cooldown and retry instead of build secrets" {
	dockerfile="$REPO_ROOT/.devcontainer/Dockerfile"
	prebuild_config="$REPO_ROOT/.devcontainer/devcontainer-prebuild.json"
	workflow="$REPO_ROOT/.github/workflows/devcontainer-prebuild.yaml"

	[ -f "$dockerfile" ]
	[ -f "$prebuild_config" ]
	[ -f "$workflow" ]

	run grep -F 'RUN --mount=type=secret,id=GITHUB_TOKEN' "$dockerfile"
	[ "$status" -ne 0 ]

	run grep -F 'id=GITHUB_TOKEN,env=GITHUB_TOKEN' "$prebuild_config"
	[ "$status" -ne 0 ]

	run grep -F 'PREBUILD_COOLDOWN_HOURS: 6' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'workflow_file="${GITHUB_WORKFLOW_REF#${GITHUB_REPOSITORY}/.github/workflows/}"' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'Could not derive workflow file name from GITHUB_WORKFLOW_REF' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'repos/${GITHUB_REPOSITORY}/actions/workflows/${workflow_file}/runs?branch=${GITHUB_REF_NAME}&event=push&status=success&per_page=1' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'Could not query previous prebuild runs' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'datetime.now(timezone.utc)' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'if [ "$within_cooldown" = "true" ]; then' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'id: prebuild-attempt-1' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'continue-on-error: true' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'id: prebuild-attempt-2' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F "if: \${{ !cancelled() && steps.prebuild-attempt-1.outcome != 'success' }}" "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'Verify prebuild succeeded' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'Devcontainer prebuild failed after retry' "$workflow"
	[ "$status" -eq 0 ]
}

@test "validate-devcontainer: prebuild image includes release-specific OCI metadata" {
	dockerfile="$REPO_ROOT/.devcontainer/Dockerfile"
	prebuild_config="$REPO_ROOT/.devcontainer/devcontainer-prebuild.json"
	workflow="$REPO_ROOT/.github/workflows/devcontainer-prebuild.yaml"

	[ -f "$dockerfile" ]
	[ -f "$prebuild_config" ]
	[ -f "$workflow" ]

	run grep -F 'ARG DOTFILES_DEVCONTAINER_VERSION=latest' "$dockerfile"
	[ "$status" -eq 0 ]

	run grep -F 'org.opencontainers.image.version="${DOTFILES_DEVCONTAINER_VERSION}"' "$dockerfile"
	[ "$status" -eq 0 ]

	run grep -F '"DOTFILES_DEVCONTAINER_VERSION": "${localEnv:DOTFILES_DEVCONTAINER_VERSION}"' "$prebuild_config"
	[ "$status" -eq 0 ]

	run grep -F "DOTFILES_DEVCONTAINER_VERSION: \${{ github.ref_type == 'tag' && github.ref_name || 'latest' }}" "$workflow"
	[ "$status" -eq 0 ]
}

@test "validate-devcontainer: release prebuild publishes only the v-prefixed version tag" {
	workflow="$REPO_ROOT/.github/workflows/devcontainer-prebuild.yaml"

	[ -f "$workflow" ]
	run grep -F 'docker manifest create "${IMAGE}:${VERSION}"' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F 'version-no-v' "$workflow"
	[ "$status" -ne 0 ]

	run grep -F 'VERSION_NO_V' "$workflow"
	[ "$status" -ne 0 ]
}

@test "validate-devcontainer: prebuild image includes generated package manifest" {
	dockerfile="$REPO_ROOT/.devcontainer/Dockerfile"
	workflow="$REPO_ROOT/.github/workflows/devcontainer-prebuild.yaml"
	script="$REPO_ROOT/script/devcontainer-software-manifest.sh"

	[ -f "$dockerfile" ]
	[ -f "$workflow" ]
	[ -x "$script" ]

	run grep -F 'script/devcontainer-software-manifest.sh' "$dockerfile"
	[ "$status" -eq 0 ]

	run grep -cF 'script/devcontainer-software-manifest.sh' "$workflow"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]

	run grep -F 'manifest_dir=/usr/local/share/dotfiles-devcontainer' "$dockerfile"
	[ "$status" -eq 0 ]

	run grep -F 'Export devcontainer release notes' "$workflow"
	[ "$status" -eq 0 ]

	run grep -F "VERSION: \${{ steps.release.outputs.version || 'latest' }}" "$workflow"
	[ "$status" -eq 0 ]

	run grep -F "devcontainer-\${{ steps.release.outputs.version || 'latest' }}-software-manifest" "$workflow"
	[ "$status" -eq 0 ]
}

@test "validate-devcontainer: package manifest script emits release notes and package inventory" {
	script="$REPO_ROOT/script/devcontainer-software-manifest.sh"
	outdir="${BATS_TEST_TMPDIR}/devcontainer-manifest"

	run "$script" "$outdir"
	[ "$status" -eq 0 ]

	[ -f "$outdir/release-notes.md" ]
	[ -f "$outdir/manifest.md" ]

	run grep -F '# Devcontainer release notes' "$outdir/release-notes.md"
	[ "$status" -eq 0 ]

	run grep -F '## Key tools' "$outdir/release-notes.md"
	[ "$status" -eq 0 ]

	run grep -F '## APT packages' "$outdir/manifest.md"
	[ "$status" -eq 0 ]
}
