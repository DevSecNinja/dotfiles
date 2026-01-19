#!/usr/bin/env bats
# Tests for file-set-execution-bit bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/file-set-execution-bit.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	# Change to test directory and initialize git repo
	cd "$TEST_DIR"
	git init -q
	git config user.email "test@example.com"
	git config user.name "Test User"
	# Create an initial commit so HEAD exists
	touch .gitkeep
	git add .gitkeep
	git commit -q -m "Initial commit"
}

# Teardown function runs after each test
teardown() {
	# Return to original directory
	cd "$ORIGINAL_DIR" || true

	# Clean up test directory
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "file-set-execution-bit: help option displays usage" {
	run file-set-execution-bit --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: file-set-execution-bit" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "--all" ]]
	[[ "$output" =~ "Ensure executable permissions on shell scripts" ]]
}

@test "file-set-execution-bit: short help option displays usage" {
	run file-set-execution-bit -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: file-set-execution-bit" ]]
}

@test "file-set-execution-bit: fails when not in git repo (without --all)" {
	# Create a fresh non-git directory outside TEST_DIR
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"

	run file-set-execution-bit
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a git repository" ]]

	# Cleanup
	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "file-set-execution-bit: unknown option returns error" {
	run file-set-execution-bit --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "file-set-execution-bit: makes non-executable shell scripts executable" {
	# Create a non-executable shell script
	echo "#!/bin/bash" >script.sh
	git add script.sh

	# Verify it's not executable
	[ ! -x script.sh ]

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Making executable: script.sh" ]]

	# Verify it's now executable
	[ -x script.sh ]
}

@test "file-set-execution-bit: dry-run shows changes without applying them" {
	# Create a non-executable shell script
	echo "#!/bin/bash" >script.sh
	git add script.sh

	run file-set-execution-bit --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Dry run mode: no changes will be made" ]]
	[[ "$output" =~ "Would make executable: script.sh" ]]

	# Verify it's still not executable
	[ ! -x script.sh ]
}

@test "file-set-execution-bit: short dry-run option works" {
	# Create a non-executable shell script
	echo "#!/bin/bash" >script.sh
	git add script.sh

	run file-set-execution-bit -n
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Dry run mode" ]]
	[[ "$output" =~ "Would make executable: script.sh" ]]
}

@test "file-set-execution-bit: handles already executable scripts" {
	# Create an already executable shell script
	echo "#!/bin/bash" >script.sh
	chmod +x script.sh
	git add script.sh

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Already executable: script.sh" ]]
}

@test "file-set-execution-bit: processes both staged and unstaged files" {
	# Create staged file
	echo "#!/bin/bash" >staged.sh
	git add staged.sh

	# Create unstaged file
	echo "#!/bin/bash" >unstaged.sh

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Making executable: staged.sh" ]]
	[[ "$output" =~ "Making executable: unstaged.sh" ]]

	# Verify both are executable
	[ -x staged.sh ]
	[ -x unstaged.sh ]
}

@test "file-set-execution-bit: handles .bash extension files" {
	# Create a .bash file
	echo "#!/bin/bash" >script.bash
	git add script.bash

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Making executable: script.bash" ]]
	[ -x script.bash ]
}

@test "file-set-execution-bit: --all mode works without git repo" {
	cd "$ORIGINAL_DIR"
	mkdir -p "$TEST_DIR/nogit"
	cd "$TEST_DIR/nogit"

	# Create shell scripts
	echo "#!/bin/bash" >script1.sh
	echo "#!/bin/bash" >script2.sh

	run file-set-execution-bit --all
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Checking all files in current directory" ]]
	[[ "$output" =~ "Making executable: script1.sh" ]]
	[[ "$output" =~ "Making executable: script2.sh" ]]

	[ -x script1.sh ]
	[ -x script2.sh ]
}

@test "file-set-execution-bit: short --all option works" {
	echo "#!/bin/bash" >script.sh

	run file-set-execution-bit -a
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Checking all files in current directory" ]]
}

@test "file-set-execution-bit: --all mode finds scripts recursively" {
	# Create directory structure
	mkdir -p subdir1/subdir2

	# Create scripts at different levels
	echo "#!/bin/bash" >script1.sh
	echo "#!/bin/bash" >subdir1/script2.sh
	echo "#!/bin/bash" >subdir1/subdir2/script3.sh

	run file-set-execution-bit --all
	[ "$status" -eq 0 ]
	[[ "$output" =~ "script1.sh" ]]
	[[ "$output" =~ "subdir1/script2.sh" ]]
	[[ "$output" =~ "subdir1/subdir2/script3.sh" ]]

	[ -x script1.sh ]
	[ -x subdir1/script2.sh ]
	[ -x subdir1/subdir2/script3.sh ]
}

@test "file-set-execution-bit: updates git index for tracked files" {
	# Create and add a shell script without executable bit
	echo "#!/bin/bash" >script.sh
	chmod -x script.sh
	git add script.sh
	git commit -q -m "Add script"

	# Now modify the file to trigger diff-index
	echo "# comment" >>script.sh

	# Run function
	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Making executable: script.sh" ]]

	# Verify git index is updated
	[ -x script.sh ]
}

@test "file-set-execution-bit: reports when no files need changes" {
	# Create already executable scripts
	echo "#!/bin/bash" >script1.sh
	chmod +x script1.sh
	git add script1.sh

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "All shell scripts already have correct permissions" ]]
}

@test "file-set-execution-bit: handles no files found" {
	# Empty repository
	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "No files found to check" ]]
}

@test "file-set-execution-bit: ignores non-shell script files" {
	# Create various file types
	echo "content" >readme.md
	echo "content" >script.py
	echo "#!/bin/bash" >script.sh

	git add .

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "script.sh" ]]
	[[ ! "$output" =~ "readme.md" ]]
	[[ ! "$output" =~ "script.py" ]]
}

@test "file-set-execution-bit: combines dry-run and all flags" {
	cd "$ORIGINAL_DIR"
	mkdir -p "$TEST_DIR/nogit"
	cd "$TEST_DIR/nogit"

	echo "#!/bin/bash" >script.sh

	run file-set-execution-bit --dry-run --all
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Dry run mode" ]]
	[[ "$output" =~ "Checking all files in current directory" ]]
	[[ "$output" =~ "Would make executable: script.sh" ]]

	[ ! -x script.sh ]
}

@test "file-set-execution-bit: handles untracked files in git mode" {
	# Create an untracked shell script
	echo "#!/bin/bash" >untracked.sh

	run file-set-execution-bit
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Making executable: untracked.sh" ]]
	[ -x untracked.sh ]
}

@test "file-set-execution-bit: processes multiple files correctly" {
	# Create multiple shell scripts
	for i in {1..5}; do
		echo "#!/bin/bash" >"script${i}.sh"
	done
	git add .

	run file-set-execution-bit
	[ "$status" -eq 0 ]

	# Verify all are executable
	for i in {1..5}; do
		[ -x "script${i}.sh" ]
	done
}
