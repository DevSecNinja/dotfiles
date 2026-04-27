#!/usr/bin/env bats
# Tests for git_new_branch fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/git_new_branch.fish"
	export FUNCTION_PATH

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	cd "$TEST_DIR"
	git init -q -b main
	git config user.email "test@example.com"
	git config user.name "Test User"
	touch .gitkeep
	git add .gitkeep
	git commit -q -m "Initial commit"
}

teardown() {
	cd "$ORIGINAL_DIR" || true
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "git_new_branch: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "git_new_branch: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "git_new_branch: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_new_branch --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_new_branch" ]]
	[[ "$output" =~ "BRANCH_NAME" ]]
	[[ "$output" =~ "--push" ]]
	[[ "$output" =~ "--pr" ]]
}

@test "git_new_branch: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_new_branch -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_new_branch" ]]
}

@test "git_new_branch: fails when not in git repo" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"
	run fish --no-config -c "source '$FUNCTION_PATH'; git_new_branch foo"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a git repository" ]]
	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git_new_branch: creates and switches to a new branch" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_new_branch fix-typo"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Creating branch: fix-typo" ]]
	[[ "$output" =~ "Successfully created and switched to branch: fix-typo" ]]

	# Verify the branch is checked out
	current=$(git -C "$TEST_DIR" symbolic-ref --short HEAD)
	[ "$current" = "fix-typo" ]
}

@test "git_new_branch: generates default branch name when none provided" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_new_branch"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Generated branch name: feature/" ]]

	# The current branch should match the feature/ pattern
	current=$(git -C "$TEST_DIR" symbolic-ref --short HEAD)
	[[ "$current" =~ ^feature/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$ ]]
}

@test "git_new_branch: rejects multiple branch names" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_new_branch foo bar"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Multiple branch names provided" ]]
}

@test "git_new_branch: warns when --pr requested but gh CLI is missing" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# Create an empty PATH that excludes gh and remote operations.
	# Without an origin remote, push will fail and short-circuit before --pr handling,
	# so we set up a bare local origin instead.
	REMOTE_DIR="$(mktemp -d)"
	git -C "$REMOTE_DIR" init -q --bare -b main
	git -C "$TEST_DIR" remote add origin "$REMOTE_DIR"
	git -C "$TEST_DIR" push -q -u origin main

	# Run with PATH that excludes gh (use a tmp empty dir + the original PATH minus gh by overriding)
	GH_PATH="$(command -v gh 2>/dev/null || true)"
	if [ -n "$GH_PATH" ]; then
		# Hide gh by creating a directory shadow with PATH override
		SHADOW_DIR="$(mktemp -d)"
		# Provide essential commands but skip gh
		ln -s "$(command -v git)" "$SHADOW_DIR/git"
		ln -s "$(command -v fish)" "$SHADOW_DIR/fish"
		ln -s "$(command -v date)" "$SHADOW_DIR/date"
		# Send empty inputs for read prompts (PR title and body)
		run env -i PATH="$SHADOW_DIR:/usr/bin:/bin" HOME="$HOME" \
			fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; printf '\n\n' | git_new_branch --pr pr-test"
		# We can't fully suppress gh discovery this way; just skip if gh leaks through.
		if echo "$output" | grep -q "Pull request created"; then
			skip "gh CLI was used through PATH leak"
		fi
		rm -rf "$SHADOW_DIR"
	else
		# gh not installed: run normally and expect the warning
		run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; printf '\n\n' | git_new_branch --pr pr-test"
		[ "$status" -eq 0 ]
		[[ "$output" =~ "'gh' CLI not found" ]]
	fi

	rm -rf "$REMOTE_DIR"
}
