#!/usr/bin/env bats
# Tests for git-ssh-to-https bash function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-ssh-to-https.sh"

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_DIR="$(pwd)"
	export ORIGINAL_DIR

	cd "$TEST_DIR" || return
	git init -q
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

@test "git-ssh-to-https: help option displays usage" {
	run git-ssh-to-https --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-ssh-to-https" ]]
	[[ "$output" =~ "--dry-run" ]]
	[[ "$output" =~ "Convert Git origin remote from SSH to HTTPS" ]]
}

@test "git-ssh-to-https: unknown option returns error" {
	run git-ssh-to-https --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
	[[ "$output" =~ "Use --help for usage information" ]]
}

@test "git-ssh-to-https: fails when not in git repo" {
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"

	run git-ssh-to-https
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a git repository" ]]

	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git-ssh-to-https: fails when no origin remote exists" {
	run git-ssh-to-https
	[ "$status" -eq 1 ]
	[[ "$output" =~ "No origin remote found" ]]
}

@test "git-ssh-to-https: exits when origin is already HTTPS" {
	git remote add origin https://github.com/user/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Origin is already using HTTPS format" ]]
}

@test "git-ssh-to-https: converts GitHub SSH to HTTPS" {
	git remote add origin git@github.com:user/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"Converting to HTTPS: https://github.com/user/repo.git"* ]]
	[[ "$output" =~ "Successfully converted" ]]

	local new_url
	new_url=$(git remote get-url origin)
	[ "$new_url" = "https://github.com/user/repo.git" ]
}

@test "git-ssh-to-https: converts GitHub SSH without .git suffix" {
	git remote add origin git@github.com:user/repo

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"Converting to HTTPS: https://github.com/user/repo.git"* ]]

	local new_url
	new_url=$(git remote get-url origin)
	[ "$new_url" = "https://github.com/user/repo.git" ]
}

@test "git-ssh-to-https: converts ssh URL format to HTTPS" {
	git remote add origin ssh://git@gitlab.com/user/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"Converting to HTTPS: https://gitlab.com/user/repo.git"* ]]

	local new_url
	new_url=$(git remote get-url origin)
	[ "$new_url" = "https://gitlab.com/user/repo.git" ]
}

@test "git-ssh-to-https: dry-run shows conversion without applying" {
	git remote add origin git@github.com:user/repo.git

	run git-ssh-to-https --dry-run
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
	[[ "$output" == *"Would convert to HTTPS: https://github.com/user/repo.git"* ]]

	local url
	url=$(git remote get-url origin)
	[ "$url" = "git@github.com:user/repo.git" ]
}

@test "git-ssh-to-https: short dry-run option works" {
	git remote add origin git@github.com:user/repo.git

	run git-ssh-to-https -n
	[ "$status" -eq 0 ]
	[[ "$output" =~ "DRY RUN" ]]
}

@test "git-ssh-to-https: converts generic Git hosting SSH to HTTPS" {
	git remote add origin git@git.example.com:user/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"Converting to HTTPS: https://git.example.com/user/repo.git"* ]]

	local new_url
	new_url=$(git remote get-url origin)
	[ "$new_url" = "https://git.example.com/user/repo.git" ]
}

@test "git-ssh-to-https: handles repositories with organization paths" {
	git remote add origin git@github.com:org/team/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"Converting to HTTPS: https://github.com/org/team/repo.git"* ]]

	local new_url
	new_url=$(git remote get-url origin)
	[ "$new_url" = "https://github.com/org/team/repo.git" ]
}

@test "git-ssh-to-https: fails on unsupported URL format" {
	git remote add origin ftp://example.com/repo.git

	run git-ssh-to-https
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unsupported URL format" ]]
	[[ "$output" =~ "This function supports SSH URLs" ]]
}

@test "git-ssh-to-https: displays new origin after conversion" {
	git remote add origin git@github.com:user/repo.git

	run git-ssh-to-https
	[ "$status" -eq 0 ]
	[[ "$output" == *"New origin: https://github.com/user/repo.git"* ]]
}
