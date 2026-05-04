#!/usr/bin/env bats
# Tests for yk-ssh-copy-id

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-ssh-copy-id.sh"
	TEST_HOME="$(mktemp -d)"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_HOME TEST_BIN_DIR
	export ORIGINAL_HOME="$HOME"
	export ORIGINAL_PATH="$PATH"
	export HOME="$TEST_HOME"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	mkdir -p "$HOME/.ssh"

	# Mock ssh: record argv to .args, write stdin to .stdin, exit 0.
	# This lets tests inspect the remote command and the keys payload
	# without ever touching a real network.
	cat >"$TEST_BIN_DIR/ssh" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"${TEST_BIN_DIR:?}/ssh.args"
cat >"${TEST_BIN_DIR:?}/ssh.stdin"
# Echo a fake "yk-ssh-copy-id: ..." line so tests can see we ran.
echo "yk-ssh-copy-id: 1 added, 0 already present" >&2
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/ssh"
}

teardown() {
	[ -n "$ORIGINAL_HOME" ] && export HOME="$ORIGINAL_HOME"
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

@test "yk-ssh-copy-id: --help works" {
	run yk-ssh-copy-id --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Push YubiKey SSH pubkey" ]]
	[[ "$output" =~ "--check" ]]
	[[ "$output" =~ "--dry-run" ]]
}

@test "yk-ssh-copy-id: errors when no host given" {
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_12345.pub"
	run yk-ssh-copy-id
	[ "$status" -eq 1 ]
	[[ "$output" =~ "missing [user@]host" ]]
}

@test "yk-ssh-copy-id: errors when no YubiKey pubkey present" {
	run yk-ssh-copy-id user@host
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no YubiKey pubkey found" ]]
	[[ "$output" =~ "yk-enroll" ]]
}

@test "yk-ssh-copy-id: --identity rejects missing file" {
	run yk-ssh-copy-id --identity "$HOME/.ssh/nonexistent.pub" user@host
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--identity file not found" ]]
}

@test "yk-ssh-copy-id: rejects multiple host arguments" {
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_12345.pub"
	run yk-ssh-copy-id one@host two@host
	[ "$status" -eq 1 ]
	[[ "$output" =~ "only one [user@]host argument allowed" ]]
}

@test "yk-ssh-copy-id: --dry-run lists keys without invoking ssh" {
	echo "ssh-ed25519-sk AAAAfirst user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	echo "ssh-ed25519-sk AAAAsecond user@host" >"$HOME/.ssh/id_ed25519_sk_22.pub"
	run yk-ssh-copy-id --dry-run user@host
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Would push 2 pubkey(s)" ]]
	[[ "$output" =~ "id_ed25519_sk_11.pub" ]]
	[[ "$output" =~ "id_ed25519_sk_22.pub" ]]
	[[ "$output" =~ "AAAAfirst" ]]
	[[ "$output" =~ "AAAAsecond" ]]
	# ssh must NOT have been invoked.
	[ ! -f "$TEST_BIN_DIR/ssh.args" ]
}

@test "yk-ssh-copy-id: discovers per-serial keys (yk-enroll output)" {
	# Regression: must find id_ed25519_sk_<serial>.pub, not just legacy.
	echo "ssh-ed25519-sk AAAAfirst user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	echo "ssh-ed25519-sk AAAAsecond user@host" >"$HOME/.ssh/id_ed25519_sk_22.pub"
	run yk-ssh-copy-id user@host
	[ "$status" -eq 0 ]
	# Both keys appear in the payload sent to ssh.
	grep -q "AAAAfirst" "$TEST_BIN_DIR/ssh.stdin"
	grep -q "AAAAsecond" "$TEST_BIN_DIR/ssh.stdin"
}

@test "yk-ssh-copy-id: legacy un-suffixed file works when no per-serial" {
	echo "ssh-ed25519-sk AAAAlegacy user@host" >"$HOME/.ssh/id_ed25519_sk.pub"
	run yk-ssh-copy-id user@host
	[ "$status" -eq 0 ]
	grep -q "AAAAlegacy" "$TEST_BIN_DIR/ssh.stdin"
}

@test "yk-ssh-copy-id: passes -p port to ssh" {
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	run yk-ssh-copy-id -p 2222 user@host
	[ "$status" -eq 0 ]
	grep -qE '^2222$' "$TEST_BIN_DIR/ssh.args"
}

@test "yk-ssh-copy-id: --identity pushes only the specified key" {
	echo "ssh-ed25519-sk AAAAfirst user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	echo "ssh-ed25519-sk AAAAsecond user@host" >"$HOME/.ssh/other.pub"
	run yk-ssh-copy-id --identity "$HOME/.ssh/other.pub" user@host
	[ "$status" -eq 0 ]
	grep -q "AAAAsecond" "$TEST_BIN_DIR/ssh.stdin"
	! grep -q "AAAAfirst" "$TEST_BIN_DIR/ssh.stdin"
}

@test "yk-ssh-copy-id: --check sends the check script (no install)" {
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	run yk-ssh-copy-id --check user@host
	[ "$status" -eq 0 ]
	# Remote command (last positional arg sent to ssh) must include the
	# check-mode marker (echo "[OK]"/"[MISS]"). The install script does
	# not echo those.
	grep -q '\[OK\]' "$TEST_BIN_DIR/ssh.args"
	grep -q '\[MISS\]' "$TEST_BIN_DIR/ssh.args"
	# And install-only markers must NOT be there.
	! grep -q 'umask 077' "$TEST_BIN_DIR/ssh.args"
}

@test "yk-ssh-copy-id: install script enforces ~/.ssh permissions and dedupes" {
	# Regression-guard: the remote install script must chmod 700 ~/.ssh,
	# chmod 600 ~/.ssh/authorized_keys, and skip lines already present.
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_11.pub"
	run yk-ssh-copy-id user@host
	[ "$status" -eq 0 ]
	grep -qF 'chmod 700 ~/.ssh' "$TEST_BIN_DIR/ssh.args"
	grep -qF 'chmod 600 ~/.ssh/authorized_keys' "$TEST_BIN_DIR/ssh.args"
	grep -qF 'grep -qFx --' "$TEST_BIN_DIR/ssh.args"
	grep -qF 'umask 077' "$TEST_BIN_DIR/ssh.args"
}
