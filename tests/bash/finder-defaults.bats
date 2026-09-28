#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	FINDER_SCRIPT="$REPO_ROOT/home/.chezmoiscripts/darwin/run_onchange_20-configure-finder.sh"
	export CHEZMOI_SOURCE_DIR="$REPO_ROOT/home"
	export DEFAULTS_CALLS="$BATS_TEST_TMPDIR/defaults-calls"
	export MOCK_OS="Darwin"
	export MOCK_DEFAULTS_STATUS=0
	export LOG_COLOR=never LOG_LEVEL=info

	mkdir -p "$BATS_TEST_TMPDIR/bin"
	cat >"$BATS_TEST_TMPDIR/bin/uname" <<'EOF'
#!/bin/bash
printf '%s\n' "$MOCK_OS"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/defaults" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$DEFAULTS_CALLS"
exit "$MOCK_DEFAULTS_STATUS"
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/uname" "$BATS_TEST_TMPDIR/bin/defaults"
	export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "finder-defaults: enables hidden files for the current macOS user" {
	run bash "$FINDER_SCRIPT"

	[ "$status" -eq 0 ]
	[ "$(cat "$DEFAULTS_CALLS")" = "write com.apple.finder AppleShowAllFiles -bool true" ]
	[[ "$output" == *"Finder is configured to show hidden files"* ]]
	[[ "$output" == *"Relaunch Finder or log out and back in"* ]]
}

@test "finder-defaults: repeated runs keep hidden files enabled" {
	run bash "$FINDER_SCRIPT"
	[ "$status" -eq 0 ]

	run bash "$FINDER_SCRIPT"
	[ "$status" -eq 0 ]
	[ "$(wc -l <"$DEFAULTS_CALLS" | tr -d ' ')" -eq 2 ]
	[ "$(sort -u "$DEFAULTS_CALLS")" = "write com.apple.finder AppleShowAllFiles -bool true" ]
}

@test "finder-defaults: skips non-macOS platforms without needing chezmoi" {
	unset CHEZMOI_SOURCE_DIR
	for MOCK_OS in Linux MINGW64_NT-10.0; do
		export MOCK_OS
		run bash "$FINDER_SCRIPT"

		[ "$status" -eq 0 ]
		[ ! -e "$DEFAULTS_CALLS" ]
	done
}

@test "finder-defaults: reports preference write failures" {
	export MOCK_DEFAULTS_STATUS=1
	run bash "$FINDER_SCRIPT"

	[ "$status" -eq 1 ]
	[[ "$output" == *"Failed to enable hidden files in Finder"* ]]
	[[ "$output" != *"Finder is configured to show hidden files"* ]]
	[[ "$output" != *"Relaunch Finder"* ]]
}
