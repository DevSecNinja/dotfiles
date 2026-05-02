#!/usr/bin/env bats
# Tests for script/build-log-sh-release.sh

load 'helpers/common'

setup() {
	common_setup
	BUILD_SCRIPT="$REPO_ROOT/script/build-log-sh-release.sh"
	export BUILD_SCRIPT
	OUTDIR="$(mktemp -d)"
	export OUTDIR
}

teardown() {
	[ -n "${OUTDIR:-}" ] && rm -rf "$OUTDIR"
	common_teardown
}

@test "build script: has valid bash syntax" {
	run bash -n "$BUILD_SCRIPT"
	assert_success
}

@test "build script: is executable" {
	assert_file_executable "$BUILD_SCRIPT"
}

@test "build script: produces all expected artifacts" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	assert_file_exists "$OUTDIR/log.sh"
	assert_file_exists "$OUTDIR/log.sh.sha256"
	assert_file_exists "$OUTDIR/install-log-sh.sh"
	assert_file_exists "$OUTDIR/install-log-sh.sh.sha256"
	assert_file_exists "$OUTDIR/log-sh-v9.9.9.tar.gz"
	assert_file_exists "$OUTDIR/log-sh-v9.9.9.tar.gz.sha256"
}

@test "build script: prepends 'v' when version lacks prefix" {
	run "$BUILD_SCRIPT" 1.2.3 "$OUTDIR"
	assert_success
	assert_file_exists "$OUTDIR/log-sh-v1.2.3.tar.gz"
}

@test "build script: produced log.sh matches source byte-for-byte" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	run cmp "$OUTDIR/log.sh" "$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	assert_success
}

@test "build script: log.sh.sha256 verifies" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	run bash -c "cd '$OUTDIR' && sha256sum -c log.sh.sha256"
	assert_success
}

@test "build script: tarball sha256 verifies" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	run bash -c "cd '$OUTDIR' && sha256sum -c 'log-sh-v9.9.9.tar.gz.sha256'"
	assert_success
}

@test "build script: installer sha256 verifies" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	run bash -c "cd '$OUTDIR' && sha256sum -c install-log-sh.sh.sha256"
	assert_success
}

@test "build script: tarball contains library, installer, completions, README, LICENSE" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	run tar -tzf "$OUTDIR/log-sh-v9.9.9.tar.gz"
	assert_success
	assert_output --partial "log-sh-v9.9.9/log.sh"
	assert_output --partial "log-sh-v9.9.9/install-log-sh.sh"
	assert_output --partial "log-sh-v9.9.9/LICENSE"
	assert_output --partial "log-sh-v9.9.9/README.md"
	assert_output --partial "log-sh-v9.9.9/completions/log.fish"
	assert_output --partial "log-sh-v9.9.9/completions/log.bash"
	assert_output --partial "log-sh-v9.9.9/completions/log.zsh"
}

@test "build script: README inside tarball references the version" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	extract="$(mktemp -d)"
	tar -xzf "$OUTDIR/log-sh-v9.9.9.tar.gz" -C "$extract"
	run grep -F "v9.9.9" "$extract/log-sh-v9.9.9/README.md"
	assert_success
	rm -rf "$extract"
}

@test "build script: extracted shell scripts have valid sh and bash syntax" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	extract="$(mktemp -d)"
	tar -xzf "$OUTDIR/log-sh-v9.9.9.tar.gz" -C "$extract"
	run sh -n "$extract/log-sh-v9.9.9/log.sh"
	assert_success
	run sh -n "$extract/log-sh-v9.9.9/install-log-sh.sh"
	assert_success
	run bash -n "$extract/log-sh-v9.9.9/log.sh"
	assert_success
	run bash -n "$extract/log-sh-v9.9.9/install-log-sh.sh"
	assert_success
	rm -rf "$extract"
}

@test "installer: installs library and completions from local release assets" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	prefix="$(mktemp -d)"
	run "$OUTDIR/install-log-sh.sh" --version v9.9.9 --prefix "$prefix" --base-url "$OUTDIR"
	assert_success
	assert_file_exists "$prefix/lib/log-sh/log.sh"
	assert_file_exists "$prefix/share/bash-completion/completions/log"
	assert_file_exists "$prefix/share/zsh/site-functions/_log"
	assert_file_exists "$prefix/share/fish/vendor_completions.d/log.fish"
	assert_file_exists "$prefix/share/doc/log-sh/README.md"
	assert_file_exists "$prefix/share/licenses/log-sh/LICENSE"
	run cmp "$prefix/lib/log-sh/log.sh" "$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	assert_success
	rm -rf "$prefix"
}

@test "installer: prepends 'v' when version lacks prefix" {
	run "$BUILD_SCRIPT" v9.9.9 "$OUTDIR"
	assert_success
	prefix="$(mktemp -d)"
	run "$OUTDIR/install-log-sh.sh" --version 9.9.9 --prefix "$prefix" --base-url "$OUTDIR"
	assert_success
	assert_output --partial "Installed log.sh v9.9.9"
	rm -rf "$prefix"
}
