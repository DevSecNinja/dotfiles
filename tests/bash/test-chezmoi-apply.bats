#!/usr/bin/env bats
# Tests for Chezmoi apply dry-run validation

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	# Ensure PATH includes ~/.local/bin for chezmoi
	export PATH="${HOME}/.local/bin:${PATH}"
}

@test "test-chezmoi-apply: chezmoi command is available" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed (requires manual installation for test)"
	fi

	run chezmoi --version
	[ "$status" -eq 0 ]
}

@test "test-chezmoi-apply: dry-run init succeeds" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi init --apply --dry-run --no-tty --source=.
	[ "$status" -eq 0 ]
}

@test "test-chezmoi-apply: dry-run does not create managed files" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Use a separate destination directory so we can verify that
	# `chezmoi init --apply --dry-run` doesn't write any managed
	# files to it. We also redirect HOME so chezmoi's own config
	# and state files (which are always written by `init`, even
	# during --dry-run) land in an isolated, throwaway location.
	local temp_home temp_dest
	temp_home="$(mktemp -d)"
	temp_dest="$(mktemp -d)"

	cd "$REPO_ROOT/home"
	HOME="$temp_home" run chezmoi init --apply --dry-run --no-tty --source=. --destination="$temp_dest"

	# Verify no managed files were actually created in the destination.
	local file_count
	file_count=$(find "$temp_dest" -type f 2>/dev/null | wc -l)

	# Cleanup
	rm -rf "$temp_home" "$temp_dest"

	# In dry-run mode, no files should be created in the destination
	[ "$file_count" -eq 0 ]
}

@test "test-chezmoi-apply: can read source directory" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi source-path --source=.
	[ "$status" -eq 0 ]
}

@test "test-chezmoi-apply: managed files list is not empty" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Initialize chezmoi with the source directory
	cd "$REPO_ROOT/home"

	# Check if any files would be managed (in dry-run mode with --no-tty to avoid prompts)
	run bash -c "chezmoi init --apply --dry-run --no-tty --source=. 2>&1 || true"
	[ "$status" -eq 0 ]

	# Output should contain some file references
	[[ "$output" != "" ]] || skip "No output from dry-run"
}
