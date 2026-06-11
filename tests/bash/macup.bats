#!/usr/bin/env bats
# Tests for macup bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/macup.sh"

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
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
	cd "$ORIGINAL_DIR" || true
	PATH="$ORIGINAL_PATH"
}

# Helper: create a mock brew that reports everything up to date so the
# Homebrew step is a no-op during tests.
make_brew_uptodate() {
	cat >"$TEST_DIR/brew" <<'EOF'
#!/bin/bash
case "$1" in
	outdated) exit 0 ;;
	--version) echo "Homebrew 4.0.0" ;;
	list) ;;
esac
exit 0
EOF
	chmod +x "$TEST_DIR/brew"
}

# Helper: create a mock softwareupdate. Pass the desired `-l` output as $1.
make_softwareupdate() {
	local list_output="$1"
	cat >"$TEST_DIR/softwareupdate" <<EOF
#!/bin/bash
if [[ "\$1" == "-l" || "\$1" == "--list" ]]; then
	cat <<'LIST'
$list_output
LIST
	exit 0
fi
if [[ "\$1" == "-i" || "\$1" == "--install" ]]; then
	echo "INSTALL_CALLED: \$*"
	exit 0
fi
exit 0
EOF
	chmod +x "$TEST_DIR/softwareupdate"
}

# Helper: mock sudo so it simply runs the wrapped command. A bare `sudo -v`
# (credential priming) succeeds without doing anything.
make_sudo_passthrough() {
	cat >"$TEST_DIR/sudo" <<'EOF'
#!/bin/bash
if [[ "$1" == "-v" ]]; then
	exit 0
fi
exec "$@"
EOF
	chmod +x "$TEST_DIR/sudo"
}

# Helper: create a mock mas. Pass the desired `outdated` output as $1.
make_mas() {
	local outdated_output="$1"
	cat >"$TEST_DIR/mas" <<EOF
#!/bin/bash
if [[ "\$1" == "outdated" ]]; then
	cat <<'OUT'
$outdated_output
OUT
	exit 0
fi
if [[ "\$1" == "upgrade" ]]; then
	echo "MAS_UPGRADE_CALLED"
	exit 0
fi
exit 0
EOF
	chmod +x "$TEST_DIR/mas"
}

@test "macup: help option displays usage" {
	run macup --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: macup" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "--all" ]]
	[[ "$output" =~ "--restart" ]]
	[[ "$output" =~ "--yes" ]]
}

@test "macup: short help option displays usage" {
	run macup -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: macup" ]]
}

@test "macup: fails when softwareupdate is not installed" {
	PATH="/usr/bin:/bin"
	run macup
	[ "$status" -eq 1 ]
	[[ "$output" =~ "softwareupdate" ]]
	[[ "$output" =~ "only works on macOS" ]]
}

@test "macup: unknown option returns error" {
	run macup --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "macup: reports when no Apple updates are available" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "No Apple software updates available" ]]
}

@test "macup: dry-run lists updates and planned action" {
	make_brew_uptodate
	make_softwareupdate "* Label: macOS Tahoe 26.5.1-25F80
	Title: macOS Tahoe 26.5.1, Version: 26.5.1, Recommended: YES, Action: restart,"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN MODE" ]]
	[[ "$output" =~ "macOS Tahoe 26.5.1-25F80" ]]
	[[ "$output" =~ "recommended updates" ]]
	[[ "$output" =~ "softwareupdate -i -r" ]]
}

@test "macup: dry-run with --all shows all-scope command" {
	make_brew_uptodate
	make_softwareupdate "* Label: Some Update-1.0"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --dry-run --all
	[ "$status" -eq 0 ]
	[[ "$output" =~ "all updates" ]]
	[[ "$output" =~ "softwareupdate -i -a" ]]
}

@test "macup: dry-run with --restart includes -R" {
	make_brew_uptodate
	make_softwareupdate "* Label: Some Update-1.0"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --dry-run --restart
	[ "$status" -eq 0 ]
	[[ "$output" =~ "softwareupdate -i -r -R" ]]
}

@test "macup: --yes installs recommended updates without prompting" {
	make_brew_uptodate
	make_softwareupdate "* Label: Some Update-1.0"
	make_sudo_passthrough
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --yes
	[ "$status" -eq 0 ]
	[[ "$output" =~ "INSTALL_CALLED: -i -r" ]]
	[[ "$output" =~ "Apple software updates complete" ]]
}

@test "macup: --yes --all --restart installs all with restart" {
	make_brew_uptodate
	make_softwareupdate "* Label: Some Update-1.0"
	make_sudo_passthrough
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --yes --all --restart
	[ "$status" -eq 0 ]
	[[ "$output" =~ "INSTALL_CALLED: -i -a -R" ]]
}

@test "macup: runs the Homebrew step via brewup" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Step 1/3: Homebrew" ]]
	[[ "$output" =~ "All packages are up to date" ]]
}

@test "macup: skips Mac App Store step when mas is not installed" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Step 2/3: Mac App Store" ]]
	[[ "$output" =~ "'mas' not installed" ]]
}

@test "macup: reports when Mac App Store apps are up to date" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	make_mas ""
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "All Mac App Store apps are up to date" ]]
}

@test "macup: upgrades outdated Mac App Store apps" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	make_mas "497799835 Xcode (26.5)"
	make_sudo_passthrough
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Outdated Mac App Store apps" ]]
	[[ "$output" =~ "Xcode" ]]
	[[ "$output" =~ "MAS_UPGRADE_CALLED" ]]
}

@test "macup: dry-run lists but does not upgrade Mac App Store apps" {
	make_brew_uptodate
	make_softwareupdate "No new software available."
	make_mas "497799835 Xcode (26.5)"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Would upgrade them with: sudo mas upgrade" ]]
	[[ ! "$output" =~ "MAS_UPGRADE_CALLED" ]]
}

@test "macup: prompts for sudo only once across mas and softwareupdate" {
	make_brew_uptodate
	make_mas "497799835 Xcode (26.5)"
	make_softwareupdate "* Label: Some Update-1.0"

	# Mock sudo so each `sudo -v` (credential prime) appends to a counter file.
	cat >"$TEST_DIR/sudo" <<EOF
#!/bin/bash
if [[ "\$1" == "-v" ]]; then
	echo "prime" >>"$TEST_DIR/sudo_v_calls"
	exit 0
fi
exec "\$@"
EOF
	chmod +x "$TEST_DIR/sudo"
	PATH="$TEST_DIR:$ORIGINAL_PATH"

	run macup --yes
	[ "$status" -eq 0 ]
	# Both sudo-requiring steps ran...
	[[ "$output" =~ "MAS_UPGRADE_CALLED" ]]
	[[ "$output" =~ "INSTALL_CALLED: -i -r" ]]
	# ...but the password was primed exactly once.
	[ "$(wc -l <"$TEST_DIR/sudo_v_calls" | tr -d ' ')" -eq 1 ]
}
