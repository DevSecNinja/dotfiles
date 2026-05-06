#!/usr/bin/env bats
# Tests for the `pubkey` shell function (defined in dot_config/shell/aliases.sh)

setup() {
	# pubkey is defined in aliases.sh as a function; source it.
	# shellcheck disable=SC1091
	. "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/aliases.sh"
	TEST_HOME="$(mktemp -d)"
	export TEST_HOME
	export ORIGINAL_HOME="$HOME"
	export HOME="$TEST_HOME"
	mkdir -p "$HOME/.ssh"
}

teardown() {
	[ -n "$ORIGINAL_HOME" ] && export HOME="$ORIGINAL_HOME"
	[ -n "$TEST_HOME" ] && [ -d "$TEST_HOME" ] && rm -rf "$TEST_HOME"
}

@test "pubkey: errors when no key present" {
	run pubkey
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No SSH public key found" ]]
}

@test "pubkey: picks per-serial id_ed25519_sk_<serial>.pub" {
	# Regression: yk-enroll writes id_ed25519_sk_<serial>.pub. The legacy
	# discovery only knew about id_ed25519_sk.pub (no suffix), so users
	# with a freshly-enrolled YubiKey saw "No SSH public key found".
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_12345.pub"
	run pubkey
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ssh-ed25519-sk AAAAtest" ]]
}

@test "pubkey: picks legacy un-suffixed id_ed25519_sk.pub when no per-serial files" {
	echo "ssh-ed25519-sk AAAAlegacy user@host" >"$HOME/.ssh/id_ed25519_sk.pub"
	run pubkey
	[ "$status" -eq 0 ]
	[[ "$output" =~ "AAAAlegacy" ]]
}

@test "pubkey: prefers FIDO2 ed25519-sk over non-FIDO2 ed25519" {
	echo "ssh-ed25519-sk AAAAfido user@host" >"$HOME/.ssh/id_ed25519_sk_12345.pub"
	echo "ssh-ed25519 AAAAplain user@host" >"$HOME/.ssh/id_ed25519.pub"
	run pubkey
	[ "$status" -eq 0 ]
	[[ "$output" =~ "AAAAfido" ]]
	[[ ! "$output" =~ "AAAAplain" ]]
}

@test "pubkey: works under zsh (no NOMATCH error on unmatched globs)" {
	# Regression: zsh's NOMATCH option made `for x in ~/.ssh/id_ecdsa_sk_*.pub`
	# abort the whole function with "no matches found" the moment one
	# pattern didn't match. find-based discovery avoids this.
	if ! command -v zsh >/dev/null 2>&1; then
		skip "zsh not installed"
	fi
	echo "ssh-ed25519-sk AAAAtest user@host" >"$HOME/.ssh/id_ed25519_sk_12345.pub"
	run zsh -c "
		HOME='$TEST_HOME'
		. '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/aliases.sh'
		pubkey
	"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "AAAAtest" ]]
	[[ ! "$output" =~ "no matches found" ]]
}
