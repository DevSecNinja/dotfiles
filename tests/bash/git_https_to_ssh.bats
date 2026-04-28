#!/usr/bin/env bats
# Tests for git_https_to_ssh fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/git_https_to_ssh.fish"
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

@test "git_https_to_ssh: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "git_https_to_ssh: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "git_https_to_ssh: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_https_to_ssh --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_https_to_ssh" ]]
	[[ "$output" =~ "--dry-run" ]]
}

@test "git_https_to_ssh: short help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_https_to_ssh -h"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_https_to_ssh" ]]
}

@test "git_https_to_ssh: unknown option returns error" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_https_to_ssh --invalid-option"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "git_https_to_ssh: fails when not in git repo" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"
	run fish --no-config -c "source '$FUNCTION_PATH'; git_https_to_ssh"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a git repository" ]]
	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git_https_to_ssh: fails when no origin remote exists" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No origin remote found" ]]
}

@test "git_https_to_ssh: exits when origin is already SSH" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin git@github.com:user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "already using SSH format" ]]
}

@test "git_https_to_ssh: converts GitHub HTTPS to SSH" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://github.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Converting to SSH: git@github.com:user/repo.git" ]]

	new_url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$new_url" = "git@github.com:user/repo.git" ]
}

@test "git_https_to_ssh: dry-run shows conversion without applying" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://github.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh --dry-run"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
	[[ "$output" =~ "Would convert to SSH" ]]

	# URL should NOT be changed
	url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$url" = "https://github.com/user/repo.git" ]
}

@test "git_https_to_ssh: short dry-run option works" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://github.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh -n"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
}

@test "git_https_to_ssh: converts GitLab HTTPS to SSH" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://gitlab.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "git@gitlab.com:user/repo.git" ]]

	new_url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$new_url" = "git@gitlab.com:user/repo.git" ]
}

@test "git_https_to_ssh: converts Bitbucket HTTPS to SSH" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://bitbucket.org/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_https_to_ssh"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "git@bitbucket.org:user/repo.git" ]]

	new_url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$new_url" = "git@bitbucket.org:user/repo.git" ]
}
