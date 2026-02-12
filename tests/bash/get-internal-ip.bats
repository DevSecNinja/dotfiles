#!/usr/bin/env bats
# Tests for get_internal_ip fish function

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	# Path to fish function
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/get_internal_ip.fish"
	export FUNCTION_PATH

	# Create a temporary directory for mock commands
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
}

# Teardown function runs after each test
teardown() {
	# Restore PATH first
	if [ -n "$ORIGINAL_PATH" ]; then
		export PATH="$ORIGINAL_PATH"
	fi

	# Clean up test directory
	if [ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ]; then
		rm -rf "$TEST_BIN_DIR"
	fi
}

@test "get-internal-ip: fish command is available" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed (requires manual installation for test)"
	fi

	run fish --version
	[ "$status" -eq 0 ]
}

@test "get-internal-ip: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "get-internal-ip: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "get-internal-ip: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	run fish --no-config -c "source '$FUNCTION_PATH'; get_internal_ip --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: get_internal_ip" ]]
	[[ "$output" =~ "--verbose" ]]
	[[ "$output" =~ "Get your local/internal IP address" ]]
	[[ "$output" =~ "macOS" ]]
	[[ "$output" =~ "Linux" ]]
}

@test "get-internal-ip: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	run fish --no-config -c "source '$FUNCTION_PATH'; get_internal_ip -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: get_internal_ip" ]]
}

@test "get-internal-ip: unknown option returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	run fish --no-config -c "source '$FUNCTION_PATH'; get_internal_ip --invalid-option"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use 'get_internal_ip --help' for usage information" ]]
}

@test "get-internal-ip: succeeds with mocked hostname on Linux" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname that returns Linux
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create a mock hostname that returns an IP
	cat >"$TEST_BIN_DIR/hostname" <<'EOF'
#!/bin/bash
if [ "$1" = "-I" ]; then
	echo "192.168.1.100 172.17.0.1"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/hostname"

	# Create mock awk
	cat >"$TEST_BIN_DIR/awk" <<'EOF'
#!/bin/bash
read input
echo "$input" | /usr/bin/awk "$@"
EOF
	chmod +x "$TEST_BIN_DIR/awk"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 0 ]
	[ "$output" = "192.168.1.100" ]
}

@test "get-internal-ip: verbose mode shows additional output on Linux" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create mock commands
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	cat >"$TEST_BIN_DIR/hostname" <<'EOF'
#!/bin/bash
if [ "$1" = "-I" ]; then
	echo "192.168.1.100"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/hostname"

	cat >"$TEST_BIN_DIR/awk" <<'EOF'
#!/bin/bash
read input
echo "$input" | /usr/bin/awk "$@"
EOF
	chmod +x "$TEST_BIN_DIR/awk"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip --verbose"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Retrieving internal IP address" ]]
	[[ "$output" =~ "Successfully retrieved internal IP address" ]]
	[[ "$output" =~ "Internal IP: 192.168.1.100" ]]
}

@test "get-internal-ip: short verbose option works" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create mock commands
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	cat >"$TEST_BIN_DIR/hostname" <<'EOF'
#!/bin/bash
if [ "$1" = "-I" ]; then
	echo "192.168.1.100"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/hostname"

	cat >"$TEST_BIN_DIR/awk" <<'EOF'
#!/bin/bash
read input
echo "$input" | /usr/bin/awk "$@"
EOF
	chmod +x "$TEST_BIN_DIR/awk"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip -v"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Retrieving internal IP address" ]]
}

@test "get-internal-ip: falls back to ip command when hostname unavailable" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname that returns Linux
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create a mock ip command
	cat >"$TEST_BIN_DIR/ip" <<'EOF'
#!/bin/bash
if [ "$1" = "route" ] && [ "$2" = "get" ]; then
	echo "1.1.1.1 via 192.168.1.1 dev eth0 src 192.168.1.50 uid 1000"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/ip"

	# Create mock awk
	cat >"$TEST_BIN_DIR/awk" <<'EOF'
#!/bin/bash
read input
echo "$input" | /usr/bin/awk "$@"
EOF
	chmod +x "$TEST_BIN_DIR/awk"

	# Create mock command to make command -v work properly in fish
	cat >"$TEST_BIN_DIR/command" <<'EOF'
#!/bin/bash
/usr/bin/command "$@"
EOF
	chmod +x "$TEST_BIN_DIR/command"

	# Only use test bin directory in PATH (don't include ORIGINAL_PATH)
	# This ensures hostname is not found
	# Note: We set PATH only inside fish, not in bash environment

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 0 ]
	[ "$output" = "192.168.1.50" ]
}

@test "get-internal-ip: succeeds with mocked ipconfig on macOS (en0)" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname that returns Darwin
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Darwin"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create a mock ipconfig
	cat >"$TEST_BIN_DIR/ipconfig" <<'EOF'
#!/bin/bash
if [ "$1" = "getifaddr" ] && [ "$2" = "en0" ]; then
	echo "192.168.1.10"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/ipconfig"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 0 ]
	[ "$output" = "192.168.1.10" ]
}

@test "get-internal-ip: falls back to en1 when en0 unavailable on macOS" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname that returns Darwin
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Darwin"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create a mock ipconfig that fails for en0 but works for en1
	cat >"$TEST_BIN_DIR/ipconfig" <<'EOF'
#!/bin/bash
if [ "$1" = "getifaddr" ] && [ "$2" = "en0" ]; then
	exit 1curl
elif [ "$1" = "getifaddr" ] && [ "$2" = "en1" ]; then
	echo "192.168.1.20"
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/ipconfig"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 0 ]
	[ "$output" = "192.168.1.20" ]
}

@test "get-internal-ip: fails when no suitable command found" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname that returns Linux
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create mock command for fish built-in command
	cat >"$TEST_BIN_DIR/command" <<'EOF'
#!/bin/bash
/usr/bin/command "$@"
EOF
	chmod +x "$TEST_BIN_DIR/command"

	# Don't create hostname or ip commands - simulate they're unavailable
	# Only use test bin directory in PATH
	# Note: We set PATH only inside fish, not in bash environment

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unable to determine internal IP address" ]]
}

@test "get-internal-ip: fails when commands return empty result" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Create a mock uname
	cat >"$TEST_BIN_DIR/uname" <<'EOF'
#!/bin/bash
echo "Linux"
exit 0
EOF
	chmod +x "$TEST_BIN_DIR/uname"

	# Create a mock hostname that returns empty
	cat >"$TEST_BIN_DIR/hostname" <<'EOF'
#!/bin/bash
if [ "$1" = "-I" ]; then
	exit 0
fi
exit 1
EOF
	chmod +x "$TEST_BIN_DIR/hostname"

	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"

	run fish --no-config -c "set -gx PATH '$TEST_BIN_DIR' '$ORIGINAL_PATH'; source '$FUNCTION_PATH'; get_internal_ip"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to retrieve internal IP address" ]]
}

@test "get-internal-ip: integration test with real commands (optional)" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Try to get real internal IP - this should work on most systems
	run fish --no-config -c "source '$FUNCTION_PATH'; get_internal_ip"

	# Check that we got a result (though we can't validate the exact IP)
	if [ "$status" -eq 0 ]; then
		# Should have some output that looks like an IP (IPv4 or IPv6)
		[[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
			[[ "$output" =~ [0-9a-f:]+ ]]
	else
		# If it fails, it might be a network configuration issue
		skip "Unable to detect internal IP on this system"
	fi
}
