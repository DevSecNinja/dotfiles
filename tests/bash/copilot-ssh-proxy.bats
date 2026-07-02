#!/usr/bin/env bats
# Tests for copilot-ssh-proxy.sh (VS Code remote.SSH.path ssh drop-in)

setup() {
	PROXY="${BATS_TEST_DIRNAME}/../../home/dot_local/bin/executable_copilot-ssh-proxy.sh"
	export PROXY

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_PATH="$PATH"
	export ORIGINAL_PATH

	# Stub `ssh`: report args + the tokens present in its environment.
	cat >"$TEST_DIR/ssh" <<'EOF'
#!/bin/bash
echo "SSH_ARGS: $*"
echo "FWD_COPILOT=${COPILOT_GITHUB_TOKEN:-<unset>}"
echo "FWD_GH=${GH_TOKEN:-<unset>}"
EOF
	chmod +x "$TEST_DIR/ssh"

	export OP_COPILOT_ENVIRONMENT_ID="ENV-TEST"
}

teardown() {
	PATH="$ORIGINAL_PATH"
	unset OP_COPILOT_ENVIRONMENT_ID COPILOT_SSH_HOST_PATTERN
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

# Stub `op` that records invocation and emulates `op run ... -- <cmd>`.
# $1 = COPILOT_GITHUB_TOKEN value, $2 = GH_TOKEN value.
_stub_op() {
	cat >"$TEST_DIR/op" <<EOF
#!/bin/bash
touch "$TEST_DIR/op_was_called"
export COPILOT_GITHUB_TOKEN='$1'
export GH_TOKEN='$2'
while [ "\$1" != "--" ] && [ \$# -gt 0 ]; do shift; done
shift
exec "\$@"
EOF
	chmod +x "$TEST_DIR/op"
}

@test "copilot-ssh-proxy: forwards both tokens for a matching host" {
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run bash "$PROXY" -T svldev bash
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -o SendEnv=COPILOT_GITHUB_TOKEN -o SendEnv=GH_TOKEN -T svldev bash" ]]
	[[ "$output" =~ "FWD_COPILOT=ctok" ]]
	[[ "$output" =~ "FWD_GH=gtok" ]]
}

@test "copilot-ssh-proxy: forwards only COPILOT_GITHUB_TOKEN when GH_TOKEN is empty" {
	_stub_op "ctok" ""
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run bash "$PROXY" svldev
	[ "$status" -eq 0 ]
	[[ "$output" =~ "-o SendEnv=COPILOT_GITHUB_TOKEN svldev" ]]
	[[ ! "$output" =~ "SendEnv=GH_TOKEN" ]]
}

@test "copilot-ssh-proxy: non-matching host uses plain ssh and does not call op" {
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run bash "$PROXY" -T example.com bash
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -T example.com bash" ]]
	[[ ! "$output" =~ "SendEnv" ]]
	[ ! -f "$TEST_DIR/op_was_called" ]
}

@test "copilot-ssh-proxy: ssh -V (no destination) does not call op" {
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run bash "$PROXY" -V
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -V" ]]
	[ ! -f "$TEST_DIR/op_was_called" ]
}

@test "copilot-ssh-proxy: falls back to plain ssh when op is not installed" {
	# Only the ssh stub is on PATH; no op.
	PATH="$TEST_DIR:/usr/bin:/bin"
	run bash "$PROXY" svldev
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: svldev" ]]
	[[ ! "$output" =~ "SendEnv" ]]
}

@test "copilot-ssh-proxy: honours a custom COPILOT_SSH_HOST_PATTERN" {
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	export COPILOT_SSH_HOST_PATTERN="myhost"
	run bash "$PROXY" myhost.internal
	[ "$status" -eq 0 ]
	[[ "$output" =~ "-o SendEnv=COPILOT_GITHUB_TOKEN" ]]
	[[ "$output" =~ "FWD_COPILOT=ctok" ]]
}
