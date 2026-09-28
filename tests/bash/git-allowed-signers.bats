#!/usr/bin/env bats

setup() {
	command -v chezmoi >/dev/null 2>&1 || skip "Chezmoi not installed"
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home"
	TEST_CONFIG="$BATS_TEST_TMPDIR/chezmoi.yaml"
	OP_KEY="ssh-ed25519 AAAA1password 1Password"
	mkdir -p "$TEST_HOME/.ssh"
	printf 'data: {}\n' >"$TEST_CONFIG"
	# Resolve shims before changing HOME so mise does not re-bootstrap in fixtures.
	CHEZMOI_BIN="$(chezmoi --config "$TEST_CONFIG" execute-template '{{ .chezmoi.executable }}')"
}

render_signers() {
	local use_yubikey="$1" signing_key="${2-$OP_KEY}"
	cat >"$TEST_CONFIG" <<EOF
data:
  email: "test@example.com"
  useYubiKey: $use_yubikey
  gitSigningKey: "$signing_key"
EOF
	HOME="$TEST_HOME" "$CHEZMOI_BIN" --config "$TEST_CONFIG" --destination "$TEST_HOME" execute-template \
		<"$REPO_ROOT/home/dot_config/git/allowed_signers.tmpl"
}

signer_entries() {
	printf '%s\n' "$output" | awk 'NF && $1 !~ /^#/'
}

@test "allowed-signers: all enrolled and legacy YubiKey keys survive switching signing modes" {
	local ed1="sk-ssh-ed25519@openssh.com AAAAfirst first"
	local ed2="sk-ssh-ed25519@openssh.com AAAAsecond second"
	local ec="sk-ecdsa-sha2-nistp256@openssh.com AAAAecdsa ecdsa"
	local legacy_ed="sk-ssh-ed25519@openssh.com AAAAlegacyEd legacy-ed"
	local legacy_ec="sk-ecdsa-sha2-nistp256@openssh.com AAAAlegacyEc legacy-ec"
	printf '%s\n' "$ed1" >"$TEST_HOME/.ssh/id_ed25519_sk_11.pub"
	printf '%s\n' "$ed2" >"$TEST_HOME/.ssh/id_ed25519_sk_22.pub"
	printf '%s\n' "$ec" >"$TEST_HOME/.ssh/id_ecdsa_sk_33.pub"
	printf '%s\n' "$legacy_ed" >"$TEST_HOME/.ssh/id_ed25519_sk.pub"
	printf '%s\n' "$legacy_ec" >"$TEST_HOME/.ssh/id_ecdsa_sk.pub"

	local expected mode
	expected="$(printf 'test@example.com %s\n' "$ed1" "$ed2" "$ec" "$legacy_ed" "$legacy_ec" "$OP_KEY")"
	for mode in true false true; do
		run render_signers "$mode"
		[ "$status" -eq 0 ]
		[ "$(signer_entries)" = "$expected" ]
		[[ "$output" != *"No FIDO2 SSH pubkey"* ]]
	done
}

@test "allowed-signers: YubiKey keys remain when no 1Password key is configured" {
	local key="sk-ssh-ed25519@openssh.com AAAAretained retained" mode
	printf '%s\n' "$key" >"$TEST_HOME/.ssh/id_ed25519_sk_11.pub"

	for mode in false true; do
		run render_signers "$mode" ""
		[ "$status" -eq 0 ]
		[ "$(signer_entries)" = "test@example.com $key" ]
	done
}

@test "allowed-signers: 1Password key remains trusted in either signing mode without YubiKey files" {
	local mode
	for mode in false true; do
		run render_signers "$mode"
		[ "$status" -eq 0 ]
		[ "$(signer_entries)" = "test@example.com $OP_KEY" ]
	done
}

@test "allowed-signers: missing YubiKey guidance is shown only when YubiKey signing is selected" {
	run render_signers true
	[ "$status" -eq 0 ]
	[[ "$output" == *"No FIDO2 SSH pubkey found yet"* ]]

	run render_signers false
	[ "$status" -eq 0 ]
	[[ "$output" != *"No FIDO2 SSH pubkey"* ]]
}

@test "allowed-signers: no keys produces no malformed signer entries" {
	local mode
	for mode in false true; do
		run render_signers "$mode" ""
		[ "$status" -eq 0 ]
		[ -z "$(signer_entries)" ]
	done
}
