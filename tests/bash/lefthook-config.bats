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
	grep -q "shellcheck -x --exclude=SC2310,SC2311,SC2312 {staged_files}" "$LEFTHOOK_CONFIG"
	grep -q "shfmt --write {staged_files}" "$LEFTHOOK_CONFIG"
}

@test "lefthook-config: shfmt indentation is left to .editorconfig" {
	# Shell scripts follow the centrally synced .editorconfig (4 spaces). An
	# explicit indent flag would make shfmt ignore .editorconfig and silently
	# reindent every file it touches.
	! grep -qE "shfmt -i [0-9]" "$LEFTHOOK_CONFIG"
	grep -q "indent_size = 4" "$REPO_ROOT/.editorconfig"
}

@test "lefthook-config: silent shell tools report successful execution" {
	grep -q "\[OK\] shellcheck checked matching shell scripts" "$LEFTHOOK_CONFIG"
	grep -q "\[OK\] shfmt checked/formatted matching shell scripts" "$LEFTHOOK_CONFIG"
}
