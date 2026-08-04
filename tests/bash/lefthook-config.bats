#!/usr/bin/env bats
# Tests for Lefthook configuration.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	LEFTHOOK_CONFIG="$REPO_ROOT/.lefthook.toml"
	export LEFTHOOK_CONFIG
}

@test "lefthook-config: config exists" {
	[ -f "$LEFTHOOK_CONFIG" ]
}

@test "lefthook-config: pre-commit shell commands are configured" {
	grep -q "\[pre-commit.commands.shellcheck\]" "$LEFTHOOK_CONFIG"
	grep -q "\[pre-commit.commands.shfmt\]" "$LEFTHOOK_CONFIG"
	grep -q "\[pre-commit.commands.file-set-execution-bit\]" "$LEFTHOOK_CONFIG"
}

@test "lefthook-config: shellcheck and shfmt run on staged shell files" {
	grep -q "shellcheck -x {staged_files}" "$LEFTHOOK_CONFIG"
	grep -q "shfmt -i 0 --write {staged_files}" "$LEFTHOOK_CONFIG"
}

@test "lefthook-config: shfmt pins tab indentation" {
	# Without an explicit indent flag shfmt reads .editorconfig, which asks for
	# 4 spaces and would reindent every (tab-indented) script in the tree on
	# the first commit that touches it.
	grep -q "shfmt -i 0 " "$LEFTHOOK_CONFIG"
}

@test "lefthook-config: silent shell tools report successful execution" {
	grep -q "\[OK\] shellcheck checked matching shell scripts" "$LEFTHOOK_CONFIG"
	grep -q "\[OK\] shfmt checked/formatted matching shell scripts" "$LEFTHOOK_CONFIG"
}
