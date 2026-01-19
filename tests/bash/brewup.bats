#!/usr/bin/env bats
# Tests for brewup bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/brewup.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	# Save original PATH
	ORIGINAL_PATH="$PATH"
	export ORIGINAL_PATH
}

# Teardown function runs after each test
teardown() {
	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi

	# Return to original directory
	cd "$ORIGINAL_DIR" || true

	# Restore original PATH
	PATH="$ORIGINAL_PATH"
}

@test "brewup: help option displays usage" {
	run brewup --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: brewup" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "Update Homebrew and all installed packages" ]]
}

@test "brewup: short help option displays usage" {
	run brewup -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: brewup" ]]
}

@test "brewup: fails when brew is not installed" {
	# Remove brew from PATH
	PATH="/usr/bin:/bin"

	run brewup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Homebrew is not installed or not in PATH" ]]
}

@test "brewup: unknown option returns error" {
	run brewup --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "brewup: dry-run displays planned actions" {
	# Create a mock brew command that reports outdated packages
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated)
		echo "package1 1.0.0 < 1.1.0"
		;;
	--version)
		echo "Homebrew 4.0.0"
		;;
	list)
		if [[ "$2" == "--formula" ]]; then
			echo "package1"
		elif [[ "$2" == "--cask" ]]; then
			echo "cask1"
		fi
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN MODE" ]]
	[[ "$output" =~ "Would update package lists" ]]
	[[ "$output" =~ "Would upgrade packages" ]]
	[[ "$output" =~ "Would clean up" ]]
}

@test "brewup: short dry-run option works" {
	# Create a mock brew command that reports outdated packages
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated)
		echo "package1 1.0.0 < 1.1.0"
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup -n
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN MODE" ]]
}

@test "brewup: exits early when all packages are up to date" {
	# Create a mock brew command that reports no outdated packages
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
if [[ "$1" == "outdated" ]]; then
	exit 0
fi
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "All packages are up to date" ]]
}

@test "brewup: displays outdated packages" {
	# Create a mock brew command that reports outdated packages
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated)
		echo "package1 1.0.0 < 1.1.0"
		echo "package2 2.0.0 < 2.1.0"
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Outdated packages that will be updated" ]]
	[[ "$output" =~ "package1" ]]
	[[ "$output" =~ "package2" ]]
}

@test "brewup: handles brew update failure" {
	# Create a mock brew command that fails on update
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated)
		echo "package1 1.0.0 < 1.1.0"
		;;
	update)
		exit 1
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to update Homebrew" ]]
}

@test "brewup: handles brew upgrade failure" {
	# Create a mock brew command that fails on upgrade
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated)
		echo "package1 1.0.0 < 1.1.0"
		;;
	update)
		exit 0
		;;
	upgrade)
		if [[ "$2" != "--cask" ]]; then
			exit 1
		fi
		exit 0
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Failed to upgrade packages" ]]
}

@test "brewup: continues after cask upgrade failures" {
	# Create a state file in TEST_DIR
	STATE_FILE="$TEST_DIR/brew-state"
	
	# Create a mock brew command that simulates cask upgrade issues
	cat >"$TEST_DIR/brew" <<EOF
#!/bin/bash
STATE_FILE="$STATE_FILE"
case "\$1" in
	outdated)
		if [ -f "\$STATE_FILE" ]; then
			exit 0
		else
			touch "\$STATE_FILE"
			echo "package1 1.0.0 < 1.1.0"
		fi
		;;
	update|upgrade)
		if [[ "\$2" == "--cask" ]]; then
			exit 1
		fi
		exit 0
		;;
	cleanup|--version)
		exit 0
		;;
	list)
		if [[ "\$2" == "--formula" ]]; then
			echo "package1"
		elif [[ "\$2" == "--cask" ]]; then
			echo "cask1"
		fi
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Some casks may have failed to upgrade" ]]
	[[ "$output" =~ "Homebrew update complete" ]]
}

@test "brewup: displays summary after successful update" {
	# Create a state file in TEST_DIR
	STATE_FILE="$TEST_DIR/brew-updated"
	
	# Create a mock brew command with full successful workflow
	cat >"$TEST_DIR/brew" <<EOF
#!/bin/bash
STATE_FILE="$STATE_FILE"
case "\$1" in
	outdated)
		if [ -f "\$STATE_FILE" ]; then
			exit 0
		else
			echo "package1 1.0.0 < 1.1.0"
		fi
		;;
	update|upgrade|cleanup)
		touch "\$STATE_FILE"
		exit 0
		;;
	--version)
		echo "Homebrew 4.0.0"
		exit 0
		;;
	list)
		if [[ "\$2" == "--formula" ]]; then
			echo "package1"
			echo "package2"
		elif [[ "\$2" == "--cask" ]]; then
			echo "cask1"
		fi
		exit 0
		;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run brewup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Homebrew summary" ]]
	[[ "$output" =~ "Installed packages:" ]]
	[[ "$output" =~ "Installed casks:" ]]
	[[ "$output" =~ "Homebrew update complete" ]]
}
