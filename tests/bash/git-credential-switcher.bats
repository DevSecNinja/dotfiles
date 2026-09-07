#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
    export REPO_ROOT

    TEST_HOME="${BATS_TEST_TMPDIR}/home"
    TEST_BIN="${BATS_TEST_TMPDIR}/bin"
    GIT_CALLS="${BATS_TEST_TMPDIR}/git-calls"
    GH_CALLS="${BATS_TEST_TMPDIR}/gh-calls"
    export TEST_HOME TEST_BIN GIT_CALLS GH_CALLS

    mkdir -p "$TEST_HOME/.config/shell/functions" "$TEST_BIN"
    cp "$REPO_ROOT/home/dot_config/shell/functions/log.sh" \
        "$TEST_HOME/.config/shell/functions/log.sh"
    chmod +x "$TEST_HOME/.config/shell/functions/log.sh"

    cat >"$TEST_BIN/git" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$GIT_CALLS"
case "$*" in
*"push"* | *"pull"*)
	if [ "$(wc -l <"$GIT_CALLS")" -eq 1 ]; then
		printf "%s\n" "fatal: Authentication failed for 'https://github.com/DevSecNinja/dotfiles.git/'" >&2
		exit 128
	fi
	printf '%s\n' "retry succeeded"
	exit 0
	;;
esac
printf '%s\n' "ordinary git command"
EOF
    chmod +x "$TEST_BIN/git"

    cat >"$TEST_BIN/gh" <<'EOF'
#!/bin/sh
case "$*" in
"auth status"*)
	printf 'DevSecNinja\ttrue\n'
	printf 'jeanpaulv_microsoft\tfalse\n'
	exit 0
	;;
esac
printf '%s\n' "$*" >>"$GH_CALLS"
exit "${GH_EXIT_STATUS:-0}"
EOF
    chmod +x "$TEST_BIN/gh"

    export HOME="$TEST_HOME"
    export PATH="$TEST_BIN:$PATH"
    export GIT_CREDENTIAL_SWITCHER_FORCE=1
    export LOG_TIMESTAMP="2026-09-07 15:00:00"
    unset GH_TOKEN GITHUB_TOKEN GIT_CREDENTIAL_SWITCHER_DISABLE GH_EXIT_STATUS

    # shellcheck source=../../home/dot_config/shell/functions/log.sh
    source "$HOME/.config/shell/functions/log.sh"
    # shellcheck source=../../home/dot_config/shell/functions/git-credential-switcher.sh
    source "$REPO_ROOT/home/dot_config/shell/functions/git-credential-switcher.sh"
}

@test "git credential switcher: retries push after switching the failed host" {
    run git push origin main <<<"y"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Failed to authenticate with GitHub credential DevSecNinja"* ]]
    [[ "$output" == *"Switch context to jeanpaulv_microsoft"* ]]
    [[ "$output" == *"Active GitHub account switched from DevSecNinja to jeanpaulv_microsoft"* ]]
    [[ "$output" == *"retry succeeded"* ]]
    [ "$(wc -l <"$GIT_CALLS")" -eq 2 ]
    [ "$(cat "$GH_CALLS")" = "auth switch --hostname github.com --user jeanpaulv_microsoft" ]
}

@test "git credential switcher: retries pull after switching credentials" {
    run git -C "$BATS_TEST_TMPDIR" pull --ff-only <<<"yes"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Retrying git pull"* ]]
    [ "$(wc -l <"$GIT_CALLS")" -eq 2 ]
}

@test "git credential switcher: leaves unrelated git commands untouched" {
    run git status --short

    [ "$status" -eq 0 ]
    [ "$output" = "ordinary git command" ]
    [ ! -e "$GH_CALLS" ]
}

@test "git credential switcher: preserves the failure when account switching fails" {
    export GH_EXIT_STATUS=1

    run git push <<<"y"

    [ "$status" -eq 128 ]
    [[ "$output" == *"GitHub account switch failed"* ]]
    [ "$(wc -l <"$GIT_CALLS")" -eq 1 ]
}

@test "git credential switcher: does not switch or retry when confirmation is declined" {
    run git push <<<"n"

    [ "$status" -eq 128 ]
    [[ "$output" == *"GitHub credential switch declined"* ]]
    [ ! -e "$GH_CALLS" ]
    [ "$(wc -l <"$GIT_CALLS")" -eq 1 ]
}

@test "git credential switcher: fish wrapper has valid syntax and matching behavior" {
    if ! command -v fish >/dev/null 2>&1; then
        skip "Fish not installed"
    fi

    run fish -n "$REPO_ROOT/home/dot_config/fish/functions/git.fish"
    [ "$status" -eq 0 ]

    rm -f "$GIT_CALLS" "$GH_CALLS"
    run bash -c "printf 'y\n' | fish --no-config -c \
		\"set -gx HOME '$HOME'; set -gx PATH '$TEST_BIN' \\\$PATH; set -gx GIT_CALLS '$GIT_CALLS'; set -gx GH_CALLS '$GH_CALLS'; set -gx GIT_CREDENTIAL_SWITCHER_FORCE 1; set -gx LOG_TIMESTAMP '$LOG_TIMESTAMP'; source '$REPO_ROOT/home/dot_config/fish/functions/git.fish'; git push origin main\""

    [ "$status" -eq 0 ]
    [[ "$output" == *"Active GitHub account switched from DevSecNinja to jeanpaulv_microsoft"* ]]
    [[ "$output" == *"retry succeeded"* ]]
    [ "$(cat "$GH_CALLS")" = "auth switch --hostname github.com --user jeanpaulv_microsoft" ]
    [ "$(wc -l <"$GIT_CALLS")" -eq 2 ]
}
