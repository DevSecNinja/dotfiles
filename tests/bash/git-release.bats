#!/usr/bin/env bats
# Tests for git-release bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh"

	# Create a temporary test directory
	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	# Save original directory
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	# Change to test directory and initialize git repo
	cd "$TEST_DIR"
	git init -q -b main
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

@test "git-release: help option displays usage" {
	run git-release --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
	[[ "$output" =~ "major|minor|patch" ]]
	[[ "$output" =~ "Create and push a semantic version tag" ]]
}

@test "git-release: short help option displays usage" {
	run git-release -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
}

@test "git-release: fails when not in git repo" {
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"

	run git-release major
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a Git repository" ]]

	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git-release: shows usage when no arguments provided" {
	# Set up a fake origin remote so the up-to-date check is bypassed before
	# argument check (script checks git repo first, then prev tag, then args)
	run git-release
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-release" ]]
	[[ "$output" =~ "Use --help for more information" ]]
}

@test "git-release: shows starting tag when no previous tags exist" {
	# Create a fake origin so it doesn't fail on the fetch step
	# We'll trigger the no-args path which only goes through the prev tag check
	run git-release
	[ "$status" -eq 0 ]
	[[ "$output" =~ "No previous tags found. Starting at v0.0.0" ]]
}

@test "git-release: shows previous tag when one exists" {
	git tag -a v1.2.3 -m "Test tag"

	run git-release
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Previous release: v1.2.3" ]]
}

@test "git-release: fails when not on main branch" {
	git checkout -q -b feature-branch

	run git-release major
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must be on the 'main' branch" ]]
	[[ "$output" =~ "feature-branch" ]]
}

@test "git-release: fails when origin/main does not exist" {
	# We are on main but there's no origin remote
	run git-release major
	[ "$status" -ne 0 ]
}

@test "git-release: fails on unparseable previous tag" {
	# Create a malformed tag
	git tag -a "vfoo.bar.baz" -m "Bad tag"

	# Create a fake origin so the up-to-date check passes
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	run git-release major
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Could not parse previous tag" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: aborts when user declines confirmation (major bump)" {
	# Setup a bare remote for origin
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"

	# Pipe "n" as the response to the confirmation prompt
	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release major
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Create and push tag 'v2.0.0'" ]]
	[[ "$output" =~ "Aborted" ]]

	# Verify the tag was NOT created
	! git rev-parse v2.0.0 >/dev/null 2>&1

	rm -rf "$REMOTE_DIR"
}

@test "git-release: computes correct minor bump" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"

	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release minor
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Create and push tag 'v1.3.0'" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: computes correct patch bump" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"

	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release patch
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Create and push tag 'v1.2.4'" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: appends prerelease suffix" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"

	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release minor beta
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Create and push tag 'v1.3.0-beta'" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: fails when target tag already exists" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"
	git tag -a v1.2.4 -m "Existing next tag"

	run git-release patch
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Tag 'v1.2.4' already exists" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: prerelease alone does not bump numeric version" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	git tag -a v1.2.3 -m "Test tag"

	# Pass only a prerelease suffix as first arg
	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release rc1
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Create and push tag 'v1.2.3-rc1'" ]]

	rm -rf "$REMOTE_DIR"
}

@test "git-release: patch bump from prerelease keeps patch number" {
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare
	git remote add origin "$REMOTE_DIR"
	git push -q origin main

	# Previous tag has a prerelease suffix
	git tag -a v1.2.3-beta -m "Beta tag"

	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-release.sh'
		cd '$TEST_DIR'
		echo 'n' | git-release patch
	"
	[ "$status" -eq 1 ]
	# Patch should remain 3 because previous was a prerelease
	[[ "$output" =~ "Create and push tag 'v1.2.3'" ]]

	rm -rf "$REMOTE_DIR"
}
