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
