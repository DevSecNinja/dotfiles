#!/usr/bin/env bats
# Tests for git-update-forked-repo bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-update-forked-repo.sh"

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
	echo "initial" >.gitkeep
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

@test "git-update-forked-repo: help option displays usage" {
	run git-update-forked-repo --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-update-forked-repo" ]]
	[[ "$output" =~ "upstream_remote_name" ]]
	[[ "$output" =~ "Sync a forked repository" ]]
}

@test "git-update-forked-repo: short help option displays usage" {
	run git-update-forked-repo -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: git-update-forked-repo" ]]
}

@test "git-update-forked-repo: fails when no arguments provided" {
	run git-update-forked-repo
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected exactly one argument" ]]
	[[ "$output" =~ "Usage: git-update-forked-repo" ]]
}

@test "git-update-forked-repo: fails when too many arguments provided" {
	run git-update-forked-repo upstream extra
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected exactly one argument" ]]
}

@test "git-update-forked-repo: fails when not in git repo" {
	NO_GIT_DIR="$(mktemp -d)"
	cd "$NO_GIT_DIR"

	run git-update-forked-repo upstream
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Not in a Git repository" ]]

	rm -rf "$NO_GIT_DIR"
	cd "$TEST_DIR"
}

@test "git-update-forked-repo: fails when upstream remote does not exist" {
	run git-update-forked-repo upstream
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Upstream remote 'upstream' not found" ]]
	[[ "$output" =~ "git remote add" ]]
}

@test "git-update-forked-repo: cancels merge when user declines" {
	# Create a bare upstream remote with a commit on main
	UPSTREAM_DIR="$(mktemp -d)"
	git -C "$UPSTREAM_DIR" init -q --bare -b main

	# Create a worktree to populate the bare repo
	UPSTREAM_WORK="$(mktemp -d)"
	git -C "$UPSTREAM_WORK" init -q -b main
	git -C "$UPSTREAM_WORK" config user.email "u@example.com"
	git -C "$UPSTREAM_WORK" config user.name "Upstream"
	echo "upstream" >"$UPSTREAM_WORK/upstream.txt"
	git -C "$UPSTREAM_WORK" add upstream.txt
	git -C "$UPSTREAM_WORK" commit -q -m "upstream commit"
	git -C "$UPSTREAM_WORK" remote add origin "$UPSTREAM_DIR"
	git -C "$UPSTREAM_WORK" push -q origin main

	git remote add upstream "$UPSTREAM_DIR"

	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-update-forked-repo.sh'
		cd '$TEST_DIR'
		echo 'n' | git-update-forked-repo upstream
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Current branch: main" ]]
	[[ "$output" =~ "Upstream remote: upstream" ]]
	[[ "$output" =~ "Merge cancelled" ]]

	# Verify no merge occurred (no upstream.txt in our working tree)
	[ ! -f "$TEST_DIR/upstream.txt" ]

	rm -rf "$UPSTREAM_DIR" "$UPSTREAM_WORK"
}

@test "git-update-forked-repo: merges when user confirms but cancels push" {
	# Create a bare upstream remote with a commit on main
	UPSTREAM_DIR="$(mktemp -d)"
	git -C "$UPSTREAM_DIR" init -q --bare -b main

	UPSTREAM_WORK="$(mktemp -d)"
	git -C "$UPSTREAM_WORK" init -q -b main
	git -C "$UPSTREAM_WORK" config user.email "u@example.com"
	git -C "$UPSTREAM_WORK" config user.name "Upstream"
	# Use a file with the same path so the merge will fast-forward
	echo "upstream-content" >"$UPSTREAM_WORK/.gitkeep"
	git -C "$UPSTREAM_WORK" add .gitkeep
	git -C "$UPSTREAM_WORK" commit -q -m "upstream initial"
	echo "more upstream" >"$UPSTREAM_WORK/upstream.txt"
	git -C "$UPSTREAM_WORK" add upstream.txt
	git -C "$UPSTREAM_WORK" commit -q -m "upstream second"
	git -C "$UPSTREAM_WORK" remote add origin "$UPSTREAM_DIR"
	git -C "$UPSTREAM_WORK" push -q origin main

	# Reinit our test repo to share history with upstream's first commit
	rm -rf "$TEST_DIR/.git"
	git -C "$TEST_DIR" init -q -b main
	git -C "$TEST_DIR" config user.email "test@example.com"
	git -C "$TEST_DIR" config user.name "Test User"
	echo "upstream-content" >"$TEST_DIR/.gitkeep"
	git -C "$TEST_DIR" add .gitkeep
	# Use the same author/date to ensure same commit hash
	GIT_COMMITTER_DATE="$(git -C "$UPSTREAM_WORK" log --reverse --format=%cI | head -n1)" \
		GIT_AUTHOR_DATE="$(git -C "$UPSTREAM_WORK" log --reverse --format=%aI | head -n1)" \
		git -C "$TEST_DIR" -c user.email=u@example.com -c user.name=Upstream \
		commit -q -m "upstream initial"

	git -C "$TEST_DIR" remote add upstream "$UPSTREAM_DIR"

	# Confirm merge (y), then decline push (n)
	run bash -c "
		source '${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/git-update-forked-repo.sh'
		cd '$TEST_DIR'
		printf 'y\nn\n' | git-update-forked-repo upstream
	"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Push cancelled" ]]

	# Verify the merge happened (upstream.txt should exist now)
	[ -f "$TEST_DIR/upstream.txt" ]

	rm -rf "$UPSTREAM_DIR" "$UPSTREAM_WORK"
}
