#!/usr/bin/env bats
# Tests for the VS Code settings.json chezmoi modify_ script
# (home/Library/Application Support/Code/User/modify_settings.json.tmpl).
#
# The source is a chezmoi template; we render it with chezmoi so
# {{ .chezmoi.homeDir }} is resolved, then exercise the rendered script by
# piping candidate settings.json contents on stdin (as chezmoi does).

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	SRC="${REPO_ROOT}/home/Library/Application Support/Code/User/modify_settings.json.tmpl"
	export REPO_ROOT SRC

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR

	if ! command -v chezmoi >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
		skip "chezmoi and jq are required"
	fi

	# Render the template to a runnable script.
	SCRIPT="$TEST_DIR/modify_settings.sh"
	chezmoi execute-template <"$SRC" >"$SCRIPT"
	chmod +x "$SCRIPT"
	export SCRIPT

	# The proxy path the script should write (matches the template expression).
	PROXY="$HOME/.local/bin/copilot-ssh-proxy.sh"
	export PROXY
}

teardown() {
	if [ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ]; then
		rm -rf "$TEST_DIR"
	fi
}

@test "modify-vscode-settings: creates the key when the file is absent (empty stdin)" {
	run bash -c "printf '' | '$SCRIPT'"
	[ "$status" -eq 0 ]
	# Output must be valid JSON containing the key set to the proxy path.
	echo "$output" | jq -e --arg p "$PROXY" '.["remote.SSH.path"] == $p'
}

@test "modify-vscode-settings: adds the key while preserving existing settings" {
	run bash -c "printf '%s' '{\"editor.fontSize\": 13}' | '$SCRIPT'"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.["editor.fontSize"] == 13'
	echo "$output" | jq -e --arg p "$PROXY" '.["remote.SSH.path"] == $p'
}

@test "modify-vscode-settings: leaves input unchanged when the value already matches" {
	local in
	in="$(jq -n --arg p "$PROXY" '{"remote.SSH.path": $p, "a": 1}')"
	run bash -c "printf '%s' '$in' | '$SCRIPT'"
	[ "$status" -eq 0 ]
	[ "$output" = "$in" ]
}

@test "modify-vscode-settings: never clobbers JSONC (comments), leaves it unchanged" {
	local in_file="$TEST_DIR/jsonc-settings.json"
	cat >"$in_file" <<'JSONC'
{
  // a comment VS Code allows
  "editor.fontSize": 13,
}
JSONC
	run bash -c "'$SCRIPT' < '$in_file'"
	[ "$status" -eq 0 ]
	# Output must be byte-for-byte identical to the input (never clobbered)...
	[ "$output" = "$(cat "$in_file")" ]
	# ...and must NOT have had the key injected.
	[[ ! "$output" =~ "remote.SSH.path" ]]
	[[ "$output" =~ "// a comment VS Code allows" ]]
}

@test "modify-vscode-settings: updates an existing but different value" {
	run bash -c "printf '%s' '{\"remote.SSH.path\": \"/old\", \"x\": 2}' | '$SCRIPT'"
	[ "$status" -eq 0 ]
	echo "$output" | jq -e '.["x"] == 2'
	echo "$output" | jq -e --arg p "$PROXY" '.["remote.SSH.path"] == $p'
}
