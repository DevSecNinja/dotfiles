#!/usr/bin/env bats
# Tests for find-broken-symlinks bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/find-broken-symlinks.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR
}

# Teardown function runs after each test
teardown() {
	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi

	# Return to original directory
	cd "$ORIGINAL_DIR" || true
}

@test "find-broken-symlinks: help option displays usage" {
	run find-broken-symlinks --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: find-broken-symlinks" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "--verbose" ]]
	[[ "$output" =~ "--yes" ]]
	[[ "$output" =~ "--recursive" ]]
}

@test "find-broken-symlinks: detects broken symlinks" {
	# Create test files and symlinks
	touch "$TEST_DIR/real-file.txt"
	ln -s "$TEST_DIR/real-file.txt" "$TEST_DIR/good-link"
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link1"
	ln -s "/path/to/nowhere" "$TEST_DIR/broken-link2"

	# Run with dry-run to check detection
	run find-broken-symlinks --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Found 2 broken symlink(s)" ]]
	[[ "$output" =~ "broken-link1" ]]
	[[ "$output" =~ "broken-link2" ]]
	[[ ! "$output" =~ "good-link" ]]
}

@test "find-broken-symlinks: dry-run does not remove symlinks" {
	# Create broken symlinks
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link"

	# Run with dry-run
	run find-broken-symlinks --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "[DRY RUN]" ]]

	# Verify symlink still exists
	[ -L "$TEST_DIR/broken-link" ]
}

@test "find-broken-symlinks: removes broken symlinks with --yes flag" {
	# Create test files and symlinks
	touch "$TEST_DIR/real-file.txt"
	ln -s "$TEST_DIR/real-file.txt" "$TEST_DIR/good-link"
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link"

	# Run with --yes flag to auto-confirm
	run find-broken-symlinks --yes "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Successfully removed 1 broken symlink(s)" ]]

	# Verify broken symlink is removed
	[ ! -e "$TEST_DIR/broken-link" ]
	[ ! -L "$TEST_DIR/broken-link" ]

	# Verify good symlink still exists
	[ -L "$TEST_DIR/good-link" ]
	[ -e "$TEST_DIR/good-link" ]
}

@test "find-broken-symlinks: verbose mode provides detailed output" {
	# Create broken symlink
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link"

	# Run with verbose and dry-run
	run find-broken-symlinks --verbose --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Running find-broken-symlinks with arguments" ]]
	[[ "$output" =~ "Verbose: true" ]]
	[[ "$output" =~ "Dry run: true" ]]
}

@test "find-broken-symlinks: handles no broken symlinks" {
	# Create only good symlinks
	touch "$TEST_DIR/real-file.txt"
	ln -s "$TEST_DIR/real-file.txt" "$TEST_DIR/good-link"

	# Run function
	run find-broken-symlinks "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "No broken symlinks found" ]]
}

@test "find-broken-symlinks: fails on nonexistent directory" {
	run find-broken-symlinks "/nonexistent/path/that/does/not/exist"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Directory does not exist" ]]
}

@test "find-broken-symlinks: uses current directory when no path specified" {
	# Change to test directory
	cd "$TEST_DIR"

	# Create broken symlink
	ln -s "nonexistent.txt" "broken-link"

	# Run without specifying directory
	run find-broken-symlinks --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Found 1 broken symlink(s)" ]]
}

@test "find-broken-symlinks: non-recursive by default (only finds in current directory)" {
	# Create directory structure
	mkdir -p "$TEST_DIR/subdir1/subdir2"

	# Create broken symlinks at different levels
	ln -s "$TEST_DIR/nonexistent1.txt" "$TEST_DIR/broken-link1"
	ln -s "$TEST_DIR/nonexistent2.txt" "$TEST_DIR/subdir1/broken-link2"
	ln -s "$TEST_DIR/nonexistent3.txt" "$TEST_DIR/subdir1/subdir2/broken-link3"

	# Run function without recursive flag
	run find-broken-symlinks --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "non-recursive" ]]
	[[ "$output" =~ "Found 1 broken symlink(s)" ]]
	[[ "$output" =~ "broken-link1" ]]
	[[ ! "$output" =~ "broken-link2" ]]
	[[ ! "$output" =~ "broken-link3" ]]
}

@test "find-broken-symlinks: recursively finds broken symlinks with --recursive flag" {
	# Create directory structure
	mkdir -p "$TEST_DIR/subdir1/subdir2"

	# Create broken symlinks at different levels
	ln -s "$TEST_DIR/nonexistent1.txt" "$TEST_DIR/broken-link1"
	ln -s "$TEST_DIR/nonexistent2.txt" "$TEST_DIR/subdir1/broken-link2"
	ln -s "$TEST_DIR/nonexistent3.txt" "$TEST_DIR/subdir1/subdir2/broken-link3"

	# Run function with recursive flag
	run find-broken-symlinks --recursive --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "recursively" ]]
	[[ "$output" =~ "Found 3 broken symlink(s)" ]]
	[[ "$output" =~ "broken-link1" ]]
	[[ "$output" =~ "broken-link2" ]]
	[[ "$output" =~ "broken-link3" ]]
}

@test "find-broken-symlinks: short form -r flag works for recursive search" {
	# Create directory structure
	mkdir -p "$TEST_DIR/subdir1"

	# Create broken symlinks at different levels
	ln -s "$TEST_DIR/nonexistent1.txt" "$TEST_DIR/broken-link1"
	ln -s "$TEST_DIR/nonexistent2.txt" "$TEST_DIR/subdir1/broken-link2"

	# Run function with short form -r flag
	run find-broken-symlinks -r --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "recursively" ]]
	[[ "$output" =~ "Found 2 broken symlink(s)" ]]
	[[ "$output" =~ "broken-link1" ]]
	[[ "$output" =~ "broken-link2" ]]
}

@test "find-broken-symlinks: preserves working symlinks while removing broken ones" {
	# Create mixed symlinks
	touch "$TEST_DIR/real-file.txt"
	ln -s "$TEST_DIR/real-file.txt" "$TEST_DIR/good-link1"
	ln -s "$TEST_DIR/nonexistent1.txt" "$TEST_DIR/broken-link1"
	ln -s "$TEST_DIR/real-file.txt" "$TEST_DIR/good-link2"
	ln -s "$TEST_DIR/nonexistent2.txt" "$TEST_DIR/broken-link2"

	# Count initial symlinks
	initial_count=$(find "$TEST_DIR" -type l | wc -l)
	[ "$initial_count" -eq 4 ]

	# Remove broken symlinks
	run find-broken-symlinks --yes "$TEST_DIR"
	[ "$status" -eq 0 ]

	# Verify only good symlinks remain
	remaining_count=$(find "$TEST_DIR" -type l | wc -l)
	[ "$remaining_count" -eq 2 ]

	# Verify good symlinks still work
	[ -e "$TEST_DIR/good-link1" ]
	[ -e "$TEST_DIR/good-link2" ]
}

@test "find-broken-symlinks: reports correct counts with verbose output" {
	# Create broken symlinks
	ln -s "$TEST_DIR/nonexistent1.txt" "$TEST_DIR/broken-link1"
	ln -s "$TEST_DIR/nonexistent2.txt" "$TEST_DIR/broken-link2"
	ln -s "$TEST_DIR/nonexistent3.txt" "$TEST_DIR/broken-link3"

	# Run with verbose and yes flags
	run find-broken-symlinks --verbose --yes "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Recursive: false" ]]
	[[ "$output" =~ "Total found: 3" ]]
	[[ "$output" =~ "Removed: 3" ]]
	[[ "$output" =~ "Failed: 0" ]]
}

@test "find-broken-symlinks: handles symlinks with special characters in names" {
	# Create symlinks with special characters
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken link with spaces"
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link-with-dashes"
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken_link_with_underscores"

	# Run function
	run find-broken-symlinks --yes "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Successfully removed 3 broken symlink(s)" ]]

	# Verify all are removed
	[ ! -e "$TEST_DIR/broken link with spaces" ]
	[ ! -e "$TEST_DIR/broken-link-with-dashes" ]
	[ ! -e "$TEST_DIR/broken_link_with_underscores" ]
}

@test "find-broken-symlinks: combines multiple flags correctly" {
	# Create broken symlink
	ln -s "$TEST_DIR/nonexistent.txt" "$TEST_DIR/broken-link"

	# Run with multiple flags
	run find-broken-symlinks --verbose --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Verbose: true" ]]
	[[ "$output" =~ "Dry run: true" ]]
	[[ "$output" =~ "[DRY RUN]" ]]

	# Verify symlink still exists (dry-run)
	[ -L "$TEST_DIR/broken-link" ]
}

@test "find-broken-symlinks: displays target paths for broken symlinks" {
	# Create broken symlinks with different targets
	ln -s "/absolute/path/to/nowhere" "$TEST_DIR/broken-absolute"
	ln -s "relative/path/nowhere" "$TEST_DIR/broken-relative"

	# Run function
	run find-broken-symlinks --dry-run "$TEST_DIR"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "/absolute/path/to/nowhere" ]]
	[[ "$output" =~ "relative/path/nowhere" ]]
}
