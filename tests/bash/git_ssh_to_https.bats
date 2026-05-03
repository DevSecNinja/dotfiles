#!/usr/bin/env bats
# Tests for git_ssh_to_https fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/git_ssh_to_https.fish"
	export FUNCTION_PATH

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	cd "$TEST_DIR" || return
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

@test "git_ssh_to_https: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "git_ssh_to_https: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "git_ssh_to_https: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish --no-config -c "source '$FUNCTION_PATH'; git_ssh_to_https --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git_ssh_to_https" ]]
	[[ "$output" =~ "--dry-run" ]]
}

@test "git_ssh_to_https: exits when origin is already HTTPS" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin https://github.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_ssh_to_https"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "already using HTTPS format" ]]
}

@test "git_ssh_to_https: converts GitHub SSH to HTTPS" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin git@github.com:user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_ssh_to_https"
	[ "$status" -eq 0 ]
	[[ "$output" == *"https://github.com/user/repo.git"* ]]

	new_url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$new_url" = "https://github.com/user/repo.git" ]
}

@test "git_ssh_to_https: converts ssh URL format to HTTPS" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin ssh://git@gitlab.com/user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_ssh_to_https"
	[ "$status" -eq 0 ]
	[[ "$output" == *"https://gitlab.com/user/repo.git"* ]]

	new_url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$new_url" = "https://gitlab.com/user/repo.git" ]
}

@test "git_ssh_to_https: dry-run shows conversion without applying" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin git@github.com:user/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_ssh_to_https --dry-run"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
	[[ "$output" =~ "Would convert to HTTPS" ]]

	url=$(git -C "$TEST_DIR" remote get-url origin)
	[ "$url" = "git@github.com:user/repo.git" ]
}

@test "git_ssh_to_https: fails on unsupported URL format" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	git remote add origin ftp://example.com/repo.git
	run fish --no-config -c "source '$FUNCTION_PATH'; cd '$TEST_DIR'; git_ssh_to_https"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unsupported URL format" ]]
}
