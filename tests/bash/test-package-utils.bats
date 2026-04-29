#!/usr/bin/env bats
# Tests for reusable package lookup helpers used by chezmoi scripts.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	PACKAGE_UTILS="$REPO_ROOT/home/.chezmoiscripts/lib/package-utils.sh"
	PACKAGES_FILE="$REPO_ROOT/home/.chezmoidata/packages.yaml"
	export PACKAGE_UTILS PACKAGES_FILE
}

@test "package-utils: helper has valid bash syntax" {
	run bash -n "$PACKAGE_UTILS"
	[ "$status" -eq 0 ]
}

@test "package-utils: mise is required for full Linux installs" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_required_for_install_type mise full linux \"$PACKAGES_FILE\""
	[ "$status" -eq 0 ]
}

@test "package-utils: mise is not required for light Linux installs" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_required_for_install_type mise light linux \"$PACKAGES_FILE\""
	[ "$status" -eq 1 ]
}

@test "package-utils: mise is required for full macOS installs" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_required_for_install_type mise full darwin \"$PACKAGES_FILE\""
	[ "$status" -eq 0 ]
}

@test "package-utils: Windows package IDs can match by package suffix" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_required_for_install_type mise full windows \"$PACKAGES_FILE\""
	[ "$status" -eq 0 ]
}

@test "package-utils: package ID suffix matcher handles dotted IDs" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_name_matches mise jdx.mise"
	[ "$status" -eq 0 ]
}

@test "package-utils: WSL uses Linux package definitions" {
	run bash -c "source \"$PACKAGE_UTILS\" && package_required_for_install_type mise full wsl \"$PACKAGES_FILE\""
	[ "$status" -eq 0 ]
}
