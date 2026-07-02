#!/usr/bin/env bats
# Tests for the copilot-ssh bash/zsh function

setup() {
	# Load the function under test
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/copilot-ssh.sh"

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_PATH="$PATH"
	export ORIGINAL_PATH
	# Default: helper is configured; individual tests override as needed.
	export OP_COPILOT_ENVIRONMENT_ID="ENV-TEST"
}

teardown() {
	PATH="$ORIGINAL_PATH"
	unset OP_COPILOT_ENVIRONMENT_ID
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

# A stub `ssh` that reports the arguments it received and the tokens that were
# exported into its environment (i.e. what SendEnv would forward).
_stub_ssh() {
	cat >"$TEST_DIR/ssh" <<'EOF'
#!/bin/bash
echo "SSH_ARGS: $*"
echo "FWD_COPILOT=${COPILOT_GITHUB_TOKEN:-<unset>}"
echo "FWD_GH=${GH_TOKEN:-<unset>}"
EOF
	chmod +x "$TEST_DIR/ssh"
}

# A stub `op` emulating `op run --environment ID --no-masking -- <cmd...>`.
# $1 = COPILOT_GITHUB_TOKEN value, $2 = GH_TOKEN value, $3 = "1" to fail.
_stub_op() {
	local copilot="$1" gh="$2" fail="${3:-0}"
	cat >"$TEST_DIR/op" <<EOF
#!/bin/bash
if [ "$fail" = "1" ]; then exit 3; fi
export COPILOT_GITHUB_TOKEN='$copilot'
export GH_TOKEN='$gh'
while [ "\$1" != "--" ] && [ \$# -gt 0 ]; do shift; done
shift
exec "\$@"
EOF
	chmod +x "$TEST_DIR/op"
}

@test "copilot-ssh: help option displays usage" {
	run copilot-ssh --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: copilot-ssh" ]]
	[[ "$output" =~ "COPILOT_GITHUB_TOKEN" ]]
}

@test "copilot-ssh: short help option displays usage" {
	run copilot-ssh -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: copilot-ssh" ]]
}

@test "copilot-ssh: falls back to plain ssh when op is not installed" {
	_stub_ssh
	# PATH without op (stub dir has only ssh); real op excluded.
	PATH="$TEST_DIR:/usr/bin:/bin"
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "'op' (1Password CLI) not found" ]]
	[[ "$output" =~ "SSH_ARGS: myhost" ]]
	# No token should be forwarded in the fallback path.
	[[ ! "$output" =~ "SendEnv" ]]
}

@test "copilot-ssh: falls back to plain ssh when Environment ID is unset" {
	_stub_ssh
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	unset OP_COPILOT_ENVIRONMENT_ID
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "OP_COPILOT_ENVIRONMENT_ID is not set" ]]
	[[ "$output" =~ "SSH_ARGS: myhost" ]]
	[[ ! "$output" =~ "SendEnv" ]]
}

@test "copilot-ssh: forwards both tokens when present" {
	_stub_ssh
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -o SendEnv=COPILOT_GITHUB_TOKEN -o SendEnv=GH_TOKEN myhost" ]]
	[[ "$output" =~ "FWD_COPILOT=ctok" ]]
	[[ "$output" =~ "FWD_GH=gtok" ]]
}

@test "copilot-ssh: forwards only COPILOT_GITHUB_TOKEN when GH_TOKEN is empty" {
	_stub_ssh
	_stub_op "ctok" ""
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -o SendEnv=COPILOT_GITHUB_TOKEN myhost" ]]
	[[ ! "$output" =~ "SendEnv=GH_TOKEN" ]]
	[[ "$output" =~ "FWD_COPILOT=ctok" ]]
}

@test "copilot-ssh: passes through extra ssh arguments" {
	_stub_ssh
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh -A -p 2222 myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "-A -p 2222 myhost" ]]
}

@test "copilot-ssh: errors when COPILOT_GITHUB_TOKEN is missing from the Environment" {
	_stub_ssh
	_stub_op "" ""
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "COPILOT_GITHUB_TOKEN not found" ]]
	# ssh must not be invoked on the error path.
	[[ ! "$output" =~ "SSH_ARGS:" ]]
}

@test "copilot-ssh: errors with a dedicated message when op run fails" {
	_stub_ssh
	_stub_op "ctok" "gtok" "1"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "failed to read tokens" ]]
	[[ ! "$output" =~ "SSH_ARGS:" ]]
}
