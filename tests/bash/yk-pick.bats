#!/usr/bin/env bats
# Tests for yk-pick

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-pick.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

mock_ykman_serials() {
	# Args: each YubiKey serial as a separate parameter.
	local lines=""
	for s in "$@"; do
		lines+="$s"$'\n'
		printf -v lines '%s' "$lines"  # noop, keeps shellcheck quiet
	done
	printf '%s' "$lines" >"$TEST_BIN_DIR/_serials"
	cat >"$TEST_BIN_DIR/ykman" <<EOF
#!/bin/bash
[ "\$1 \$2" = "list --serials" ] && cat "$TEST_BIN_DIR/_serials"
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
}

@test "yk-pick: errors when no key" {
	mock_ykman_serials
	run yk-pick
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no YubiKey detected" ]]
}

@test "yk-pick: returns single serial" {
	mock_ykman_serials 12345
	run yk-pick
	[ "$status" -eq 0 ]
	[ "$output" = "12345" ]
}

@test "yk-pick: --first returns first of many" {
	mock_ykman_serials 11 22 33
	run yk-pick --first
	[ "$status" -eq 0 ]
	[ "$output" = "11" ]
}

@test "yk-pick: errors on multiple without fzf" {
	mock_ykman_serials 11 22
	# The `[[ -t 0 ]]` guard inside yk-pick is false under bats (stdin is piped),
	# so the function errors out regardless of fzf availability.
	run yk-pick
	[ "$status" -eq 1 ]
	[[ "$output" =~ "multiple YubiKeys connected" ]]
}
