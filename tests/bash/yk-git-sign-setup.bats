#!/usr/bin/env bats
# Tests for yk-git-sign-setup

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/yk-git-sign-setup.sh"
	TEST_HOME="$(mktemp -d)"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_HOME TEST_BIN_DIR
	export ORIGINAL_HOME="$HOME"
	export ORIGINAL_PATH="$PATH"
	export HOME="$TEST_HOME"
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	export ALLOWED_SIGNERS_FILE="$TEST_HOME/.config/git/allowed_signers"

	# Stub git config: store/retrieve key=value pairs in TEST_BIN_DIR/_git_cfg
	cat >"$TEST_BIN_DIR/git" <<'EOF'
#!/bin/bash
cfg="${TEST_BIN_DIR}/_git_cfg"
[ -f "$cfg" ] || : >"$cfg"
case "$1 $2" in
	"config --get")
		grep -E "^${3}=" "$cfg" | tail -n1 | cut -d= -f2-
		;;
	"config --add")
		echo "$3=$4" >>"$cfg"
		;;
	*)
		exit 0
		;;
esac
EOF
	chmod +x "$TEST_BIN_DIR/git"
}

teardown() {
	[ -n "$ORIGINAL_HOME" ] && export HOME="$ORIGINAL_HOME"
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
	unset ALLOWED_SIGNERS_FILE
}

set_git_cfg() {
	echo "$1=$2" >>"$TEST_BIN_DIR/_git_cfg"
}

@test "yk-git-sign-setup: --check fails when nothing configured" {
	run yk-git-sign-setup --check
	[ "$status" -eq 1 ]
	[[ "$output" =~ "ssh signing: OFF" ]]
}

@test "yk-git-sign-setup: --check passes when fully configured" {
	set_git_cfg gpg.format ssh
	set_git_cfg commit.gpgsign true
	set_git_cfg user.signingkey "$TEST_HOME/.ssh/id_ed25519_sk.pub"
	run yk-git-sign-setup --check
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ssh signing: ON" ]]
}

@test "yk-git-sign-setup: errors when no key present" {
	set_git_cfg user.email "me@example.com"
	run yk-git-sign-setup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no public key found" ]]
	[[ "$output" =~ "yk-enroll" ]]
}

@test "yk-git-sign-setup: errors without user.email" {
	mkdir -p "$TEST_HOME/.ssh"
	echo "ssh-ed25519-sk AAAAtest" >"$TEST_HOME/.ssh/id_ed25519_sk.pub"
	run yk-git-sign-setup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "user.email is not set" ]]
}

@test "yk-git-sign-setup: verifies all per-serial pubkeys (yk-enroll output)" {
	# Regression: yk-enroll writes id_ed25519_sk_<serial>.pub. The setup
	# helper must check every per-serial file, not just the legacy
	# un-suffixed one. Self-key writes are owned by chezmoi (see
	# allowed_signers.tmpl) — this helper only verifies presence.
	set_git_cfg user.email "me@example.com"
	set_git_cfg gpg.format ssh
	set_git_cfg commit.gpgsign true
	set_git_cfg user.signingkey "$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/.config/git"
	echo "ssh-ed25519-sk AAAAfirst user@host" >"$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	echo "ssh-ed25519-sk AAAAsecond user@host" >"$TEST_HOME/.ssh/id_ed25519_sk_22.pub"
	# Pre-populate as chezmoi would have.
	printf 'me@example.com ssh-ed25519-sk AAAAfirst user@host\nme@example.com ssh-ed25519-sk AAAAsecond user@host\n' >"$ALLOWED_SIGNERS_FILE"
	run yk-git-sign-setup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Already registered" ]]
	# Required-next-step nudge mentions BOTH gh ssh-key add commands.
	[[ "$output" =~ "--type signing" ]]
}

@test "yk-git-sign-setup: warns when self-key missing from allowed_signers" {
	# Self keys are managed by chezmoi. If they're missing, yk-git-sign-setup
	# should NOT write them itself (that would cause chezmoi drift). It
	# should print a hint pointing at chezmoi apply.
	set_git_cfg user.email "me@example.com"
	set_git_cfg gpg.format ssh
	set_git_cfg commit.gpgsign true
	set_git_cfg user.signingkey "$TEST_HOME/.ssh/id_ed25519_sk.pub"
	mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/.config/git"
	echo "ssh-ed25519-sk AAAAtest user@host" >"$TEST_HOME/.ssh/id_ed25519_sk.pub"
	: >"$ALLOWED_SIGNERS_FILE"
	run yk-git-sign-setup
	[[ "$output" =~ "Missing from allowed_signers" ]]
	[[ "$output" =~ "chezmoi apply" ]]
	# Should NOT have written the key itself.
	run grep -q "AAAAtest" "$ALLOWED_SIGNERS_FILE"
	[ "$status" -ne 0 ]
}

@test "yk-git-sign-setup: idempotent — never writes self-keys to allowed_signers" {
	# Even called many times, yk-git-sign-setup must not append self keys
	# to allowed_signers (that file is owned by chezmoi).
	set_git_cfg user.email "me@example.com"
	set_git_cfg gpg.format ssh
	set_git_cfg commit.gpgsign true
	set_git_cfg user.signingkey "$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/.config/git"
	echo "ssh-ed25519-sk AAAAtest user@host" >"$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	# Pre-populate as chezmoi would have.
	echo "me@example.com ssh-ed25519-sk AAAAtest user@host" >"$ALLOWED_SIGNERS_FILE"
	yk-git-sign-setup >/dev/null
	yk-git-sign-setup >/dev/null
	run yk-git-sign-setup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Already registered" ]]
	# Single entry only (no duplicates appended by helper).
	[ "$(grep -c "ssh-ed25519-sk AAAAtest" "$ALLOWED_SIGNERS_FILE")" -eq 1 ]
}

@test "yk-git-sign-setup: --check exits non-zero even after register if config not wired" {
	# Regression: previously the helper printed a hint but exited 0 when
	# user wasn't using chezmoi-managed config. Setup mode should propagate
	# the failure so callers know signing isn't actually working yet.
	set_git_cfg user.email "me@example.com"
	# Note: gpg.format/commit.gpgsign/user.signingkey deliberately NOT set.
	mkdir -p "$TEST_HOME/.ssh" "$TEST_HOME/.config/git"
	echo "ssh-ed25519-sk AAAAtest user@host" >"$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	echo "me@example.com ssh-ed25519-sk AAAAtest user@host" >"$ALLOWED_SIGNERS_FILE"
	run yk-git-sign-setup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Hint:" ]]
	[[ "$output" =~ "useYubiKey" ]]
}

@test "yk-git-sign-setup: --add requires --principal" {
	echo "ssh-ed25519 AAAAcoworker" >"$TEST_HOME/co.pub"
	run yk-git-sign-setup --add "$TEST_HOME/co.pub"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--principal" ]]
}

@test "yk-git-sign-setup: --add appends a coworker key" {
	echo "ssh-ed25519 AAAAcoworker coworker@example.com" >"$TEST_HOME/co.pub"
	run yk-git-sign-setup --add "$TEST_HOME/co.pub" --principal coworker@example.com
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Added principal coworker@example.com" ]]
	grep -q "coworker@example.com ssh-ed25519 AAAAcoworker" "$ALLOWED_SIGNERS_FILE"
}

@test "yk-git-sign-setup: --add missing file errors" {
	run yk-git-sign-setup --add "$TEST_HOME/nope.pub" --principal who@example.com
	[ "$status" -eq 1 ]
	[[ "$output" =~ "not found" ]]
}
