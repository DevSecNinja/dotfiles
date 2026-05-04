#!/usr/bin/env bats
# Tests for clipboard-copy helper

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/clipboard-copy.sh"
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	export ORIGINAL_PATH="$PATH"
	# Default uname stub returning Linux (built with shell builtins so we can
	# isolate PATH below without losing `cat`).
	printf '#!/bin/bash\necho Linux\n' >"$TEST_BIN_DIR/uname"
	/usr/bin/chmod +x "$TEST_BIN_DIR/uname"
	# Strip system clipboard tools (xsel, xclip etc.) from PATH so we exercise
	# the function's backend-detection logic deterministically.
	export PATH="$TEST_BIN_DIR"
	unset WAYLAND_DISPLAY DISPLAY
}

teardown() {
	[ -n "$ORIGINAL_PATH" ] && export PATH="$ORIGINAL_PATH"
	[ -n "$TEST_BIN_DIR" ] && [ -d "$TEST_BIN_DIR" ] && rm -rf "$TEST_BIN_DIR"
}

mock_tool() {
	local name="$1"
	printf '#!/bin/bash\ncat >"%s/%s.captured"\n' "$TEST_BIN_DIR" "$name" >"$TEST_BIN_DIR/$name"
	/usr/bin/chmod +x "$TEST_BIN_DIR/$name"
}

@test "clipboard-copy: --check exits 1 with no backends" {
	run clipboard-copy --check
	[ "$status" -eq 1 ]
}

@test "clipboard-copy: --tool prints pbcopy on Darwin-like setup" {
	printf '#!/bin/bash\necho Darwin\n' >"$TEST_BIN_DIR/uname"
	/usr/bin/chmod +x "$TEST_BIN_DIR/uname"
	mock_tool pbcopy
	run clipboard-copy --tool
	[ "$status" -eq 0 ]
	[ "$output" = "pbcopy" ]
}

@test "clipboard-copy: prefers wl-copy when WAYLAND_DISPLAY set" {
	mock_tool wl-copy
	mock_tool xclip
	export WAYLAND_DISPLAY=wayland-0
	run clipboard-copy --tool
	[ "$status" -eq 0 ]
	[ "$output" = "wl-copy" ]
}

@test "clipboard-copy: falls back to xclip on X11" {
	mock_tool xclip
	export DISPLAY=:0
	run clipboard-copy --tool
	[ "$status" -eq 0 ]
	[ "$output" = "xclip" ]
}

@test "clipboard-copy: writes stdin to backend" {
	mock_tool xclip
	export DISPLAY=:0
	# Restore a normal PATH for this test so `bash`, `echo`, `cat` resolve.
	export PATH="$TEST_BIN_DIR:$ORIGINAL_PATH"
	run /bin/bash -c "source '$BATS_TEST_DIRNAME/../../home/dot_config/shell/functions/clipboard-copy.sh'; echo hello | clipboard-copy"
	[ "$status" -eq 0 ]
	[ "$(cat "$TEST_BIN_DIR/xclip.captured")" = "hello" ]
}

@test "clipboard-copy: error message when no backend" {
	run clipboard-copy
	[ "$status" -eq 1 ]
	[[ "$output" =~ "no clipboard backend" ]]
}
