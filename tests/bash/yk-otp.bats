#!/usr/bin/env bats
# Tests for yk-otp

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-otp.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

mock_ykman() {
	# Args: lines for `oath accounts code` (one per arg).
	local payload=""
	for line in "$@"; do
		payload+="$line"$'\n'
	done
	printf '%s' "$payload" >"$TEST_BIN_DIR/_oath_code"
	cat >"$TEST_BIN_DIR/ykman" <<'EOF'
#!/bin/bash
# Skip --device <serial> if present
if [ "$1" = "--device" ]; then shift 2; fi
case "$1 $2 $3" in
	"oath accounts code"|"oath accounts code "*)
		filter="$4"
		if [ -n "$filter" ]; then
			grep -i "$filter" "$TEST_BIN_DIR/_oath_code" || true
		else
			cat "$TEST_BIN_DIR/_oath_code"
		fi
		;;
	"oath accounts list")
		awk '{$NF=""; sub(/[[:space:]]+$/,""); print}' "$TEST_BIN_DIR/_oath_code"
		;;
esac
EOF
	chmod +x "$TEST_BIN_DIR/ykman"
}

@test "yk-otp: errors when ykman missing" {
	export PATH=/nonexistent
	run yk-otp
	[ "$status" -eq 1 ]
	[[ "$output" =~ "'ykman' not found" ]]
}

@test "yk-otp: errors when no accounts" {
	mock_ykman
	run yk-otp
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no OATH accounts" ]]
}

@test "yk-otp: prints code for sole match" {
	mock_ykman "GitHub:me@example.com 123456"
	run yk-otp
	[ "$status" -eq 0 ]
	[[ "$output" =~ "GitHub:me@example.com: 123456" ]]
}

@test "yk-otp: filter narrows to one match" {
	mock_ykman "GitHub:me 111111" "GitLab:me 222222"
	run yk-otp GitHub
	[ "$status" -eq 0 ]
	[[ "$output" =~ "GitHub:me: 111111" ]]
}

@test "yk-otp: --no-copy still prints" {
	mock_ykman "AWS:root 654321"
	run yk-otp --no-copy
	[ "$status" -eq 0 ]
	[[ "$output" =~ "AWS:root: 654321" ]]
	[[ ! "$output" =~ "copied" ]]
}

@test "yk-otp: rejects bogus output" {
	mock_ykman "Account something_not_a_code"
	run yk-otp
	[ "$status" -eq 1 ]
	[[ "$output" =~ "failed to obtain a code" ]]
}

@test "yk-otp: --list lists account names" {
	mock_ykman "GitHub:me 111111" "GitLab:me 222222"
	run yk-otp --list
	[ "$status" -eq 0 ]
	[[ "$output" =~ "GitHub:me" ]]
	[[ "$output" =~ "GitLab:me" ]]
}

@test "yk-otp: errors on multiple matches without fzf" {
	mock_ykman "GitHub:a 111111" "GitHub:b 222222"
	run yk-otp GitHub
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple accounts match" || "$output" =~ "more specific filter" ]]
}
