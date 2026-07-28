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

# --- pre-flight reachability check -----------------------------------------

# A stub `ssh` that also answers `ssh -G` with a resolved host/port, so the
# pre-flight check has something to probe.
_stub_ssh_config() {
	local host="$1" port="$2"
	cat >"$TEST_DIR/ssh" <<EOF
#!/bin/bash
if [ "\$1" = "-G" ]; then
	echo "user someone"
	echo "hostname ${host}"
	echo "port ${port}"
	exit 0
fi
echo "SSH_ARGS: \$*"
EOF
	chmod +x "$TEST_DIR/ssh"
}

# A stub `nc` used as the TCP probe; $1 is the exit code it reports.
_stub_nc() {
	cat >"$TEST_DIR/nc" <<EOF
#!/bin/bash
exit ${1}
EOF
	chmod +x "$TEST_DIR/nc"
}

# A stub `az`: $1 is the TSV emitted by \`az vm list\` (may be empty).
_stub_az() {
	cat >"$TEST_DIR/az" <<EOF
#!/bin/bash
case "\$2" in
list) printf '%s' '$1' ;;
start) echo "AZ_START: \$*" ;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/az"
}

# Build a PATH containing only the stubs plus the handful of real tools the
# helper needs, so a command can be made genuinely absent. `/usr/bin:/bin` is
# not enough for that: GitHub Actions runners ship the Azure CLI in /usr/bin.
_minimal_path() {
	local tool
	for tool in awk sed grep cat wc tr date sleep rm mkdir chmod; do
		if command -v "$tool" >/dev/null 2>&1; then
			ln -sf "$(command -v "$tool")" "$TEST_DIR/$tool"
		fi
	done
	PATH="$TEST_DIR"
}

@test "copilot-ssh: pre-flight resolves host and port from ssh -G" {
	_stub_ssh_config "vm01.example.com" "2222"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run _copilot_ssh_resolve myhost
	[ "$status" -eq 0 ]
	[[ "$output" == "vm01.example.com	2222" ]]
}

@test "copilot-ssh: pre-flight aborts when the host is unreachable and az is absent" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_op "ctok" "gtok"
	# PATH with the stubs but genuinely without az.
	_minimal_path
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "vm01.example.com:22 is not reachable" ]]
	[[ "$output" =~ "install the Azure CLI" ]]
	[[ ! "$output" =~ "SSH_ARGS:" ]]
}

@test "copilot-ssh: pre-flight is skipped via COPILOT_SSH_SKIP_PREFLIGHT" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	COPILOT_SSH_SKIP_PREFLIGHT=1 run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS:" ]]
	[[ ! "$output" =~ "not reachable" ]]
}

@test "copilot-ssh: pre-flight passes straight through when the port answers" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 0
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "SSH_ARGS: -o SendEnv=COPILOT_GITHUB_TOKEN" ]]
	[[ ! "$output" =~ "not reachable" ]]
}

@test "copilot-ssh: azure lookup matches the short name of an FQDN host" {
	_stub_az "vm01	rg-dev	VM deallocated"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run _copilot_ssh_az_lookup "vm01.example.com"
	[ "$status" -eq 0 ]
	[[ "$output" == "vm01	rg-dev	VM deallocated" ]]
}

@test "copilot-ssh: azure lookup matches on the resolved IP address" {
	_stub_az "othervm	rg-dev	VM running	20.1.2.3	10.0.0.4"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run _copilot_ssh_az_lookup "10.0.0.4"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "othervm" ]]
}

@test "copilot-ssh: reports when the VM runs but the port is closed" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_az "vm01	rg-dev	VM running"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "is running but vm01.example.com:22 is unreachable" ]]
	[[ ! "$output" =~ "SSH_ARGS:" ]]
}

@test "copilot-ssh: reports a stopped VM and does not start it without confirmation" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_az "vm01	rg-dev	VM deallocated"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	# Not a TTY under bats, so the confirmation prompt answers "no".
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Azure VM 'vm01' (resource group rg-dev) is VM deallocated" ]]
	[[ "$output" =~ "not starting the VM" ]]
	[[ ! "$output" =~ "AZ_START:" ]]
}

@test "copilot-ssh: starts a stopped VM when confirmed and then connects" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_az "vm01	rg-dev	VM stopped"
	_stub_op "ctok" "gtok"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	# Simulate an interactive "yes" and a host that comes back up.
	_copilot_ssh_confirm() { return 0; }
	_copilot_ssh_wait_for_ssh() { return 0; }
	run copilot-ssh myhost
	[ "$status" -eq 0 ]
	[[ "$output" =~ "started 'vm01'" ]]
	[[ "$output" =~ "SSH_ARGS: -o SendEnv=COPILOT_GITHUB_TOKEN" ]]
}

@test "copilot-ssh: aborts when several Azure VMs match the host" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_az "vm01	rg-a	VM stopped
vm01	rg-b	VM stopped"
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "several Azure VMs match" ]]
	[[ ! "$output" =~ "AZ_START:" ]]
}

@test "copilot-ssh: reports when no Azure VM matches the host" {
	_stub_ssh_config "vm01.example.com" "22"
	_stub_nc 1
	_stub_az ""
	PATH="$TEST_DIR:$ORIGINAL_PATH"
	run copilot-ssh myhost
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no Azure VM matches 'vm01.example.com'" ]]
}

@test "copilot-ssh: wait loop bails out immediately when nothing can probe" {
	# No nc and no timeout/bash on PATH: the probe is undetermined, so waiting
	# must not spin for the full COPILOT_SSH_START_TIMEOUT.
	_minimal_path
	local start elapsed
	start="$(date +%s)"
	COPILOT_SSH_START_TIMEOUT=60 run _copilot_ssh_wait_for_ssh vm01.example.com 22
	elapsed=$(($(date +%s) - start))
	[ "$status" -eq 0 ]
	[[ "$output" =~ "cannot probe" ]]
	[ "$elapsed" -lt 10 ]
}
