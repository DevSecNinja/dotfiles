#!/usr/bin/env bats
# Tests for the chezmoi-up helper (bash/zsh) and its fish twin.
#
# chezmoi is replaced with a stub so the steps, their order, the conditional
# `chezmoi init` and the stop-on-failure gating can be asserted without
# touching the real dotfiles.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	SCRIPT="${REPO_ROOT}/home/dot_config/shell/functions/chezmoi-up.sh"
	FISH_FUNC="${REPO_ROOT}/home/dot_config/fish/functions/chezmoi_up.fish"
	export SCRIPT FISH_FUNC

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_PATH="${PATH}"
	export ORIGINAL_PATH

	mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/src" "${TEST_DIR}/home"
	printf 'template-v1\n' >"${TEST_DIR}/src/.chezmoi.yaml.tmpl"

	# Stub chezmoi: records each invocation and honours FAKE_*_RC exit codes.
	cat >"${TEST_DIR}/bin/chezmoi" <<'EOF'
#!/bin/bash
if [ "$1" = "source-path" ]; then echo "${FAKE_SRC}"; exit 0; fi
case "$1" in
update) echo "UPDATE: $*"; exit "${FAKE_UPDATE_RC:-0}" ;;
init)   echo "INIT: $*";   exit "${FAKE_INIT_RC:-0}" ;;
apply)  echo "APPLY: $*";  exit "${FAKE_APPLY_RC:-0}" ;;
state)  [ -n "${FAKE_STORED_SHA}" ] || exit 1
        printf '{\n  "configTemplateContentsSHA256": "%s"\n}\n' "${FAKE_STORED_SHA}"; exit 0 ;;
esac
exit 0
EOF
	chmod +x "${TEST_DIR}/bin/chezmoi"

	FAKE_SRC="${TEST_DIR}/src"
	export FAKE_SRC
	TEMPLATE_SHA="$(sha256sum "${TEST_DIR}/src/.chezmoi.yaml.tmpl" | cut -d' ' -f1)"
	export TEMPLATE_SHA
}

teardown() {
	export PATH="${ORIGINAL_PATH}"
	if [ -n "${TEST_DIR}" ] && [ -d "${TEST_DIR}" ]; then
		rm -rf "${TEST_DIR}"
	fi
}

# _run_up [env assignments...] -> source the function and run it.
_run_up() {
	# HOME points at an empty dir: CI runners have no ~/.config/shell/functions,
	# so this keeps local runs honest about the log.sh fallback path.
	PATH="${TEST_DIR}/bin:${ORIGINAL_PATH}" HOME="${TEST_DIR}/home" \
		run bash -c "source '${SCRIPT}'; chezmoi-up $*; echo \"rc=\$?\""
}

@test "chezmoi-up: script exists and is executable" {
	[ -f "${SCRIPT}" ]
	[ -x "${SCRIPT}" ]
}

@test "chezmoi-up: has valid bash and zsh syntax" {
	run bash -n "${SCRIPT}"
	[ "$status" -eq 0 ]
	if command -v zsh >/dev/null 2>&1; then
		run zsh -n "${SCRIPT}"
		[ "$status" -eq 0 ]
	fi
}

@test "chezmoi-up: help option displays usage" {
	run bash -c "source '${SCRIPT}'; chezmoi-up --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: chezmoi-up" ]]
	[[ "$output" =~ "--force-init" ]]
}

@test "chezmoi-up: unknown option returns an error" {
	run bash -c "source '${SCRIPT}'; chezmoi-up --bogus"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "unknown option" ]]
}

@test "chezmoi-up: defines the czu alias" {
	run bash -c "source '${SCRIPT}'; alias czu"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "chezmoi-up" ]]
}

@test "chezmoi-up: errors when chezmoi is not installed" {
	PATH="/usr/bin:/bin" run bash -c "source '${SCRIPT}'; chezmoi-up"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "chezmoi is not installed" ]]
}

@test "chezmoi-up: pulls without applying, then applies" {
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ "$output" =~ "UPDATE: update --apply=false" ]]
	[[ "$output" =~ "APPLY: apply" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: skips init when the config template is unchanged" {
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ "$output" =~ "skipping chezmoi init" ]]
	[[ ! "$output" =~ "INIT:" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: runs init when the config template changed" {
	FAKE_STORED_SHA="0000000000000000000000000000000000000000000000000000000000000000" _run_up
	[[ "$output" =~ "Config template changed" ]]
	[[ "$output" =~ "INIT: init" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: --force-init runs init even when unchanged" {
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up --force-init
	[[ "$output" =~ "INIT: init" ]]
	[[ ! "$output" =~ "skipping chezmoi init" ]]
}

@test "chezmoi-up: runs init when chezmoi has no recorded state" {
	# Unknown state must fall back to running init: a redundant init is
	# harmless, a skipped one leaves a stale config behind.
	FAKE_STORED_SHA="" _run_up
	[[ "$output" =~ "INIT: init" ]]
}

@test "chezmoi-up: a failed update stops before init and apply" {
	FAKE_UPDATE_RC=1 FAKE_STORED_SHA="deadbeef" _run_up
	[[ "$output" =~ "chezmoi update failed" ]]
	[[ ! "$output" =~ "INIT:" ]]
	[[ ! "$output" =~ "APPLY:" ]]
	[[ "$output" =~ "rc=1" ]]
}

@test "chezmoi-up: a failed init stops before apply" {
	FAKE_INIT_RC=1 FAKE_STORED_SHA="deadbeef" _run_up
	[[ "$output" =~ "INIT: init" ]]
	[[ "$output" =~ "chezmoi init failed" ]]
	[[ ! "$output" =~ "APPLY:" ]]
	[[ "$output" =~ "rc=1" ]]
}

@test "chezmoi-up: a failed apply is reported" {
	FAKE_APPLY_RC=1 FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ "$output" =~ "APPLY: apply" ]]
	[[ "$output" =~ "chezmoi apply failed" ]]
	[[ ! "$output" =~ "up to date" ]]
	[[ "$output" =~ "rc=1" ]]
}


@test "chezmoi-up: still reports every step when log.sh is unavailable" {
	# A machine that has not applied the dotfiles yet has no log.sh at all.
	# Missing log helpers must not swallow the output or abort the run.
	local isolated="${TEST_DIR}/isolated"
	mkdir -p "${isolated}"
	cp "${SCRIPT}" "${isolated}/chezmoi-up.sh"

	PATH="${TEST_DIR}/bin:${ORIGINAL_PATH}" HOME="${TEST_DIR}/home" FAKE_STORED_SHA="${TEMPLATE_SHA}" \
		run bash -c "source '${isolated}/chezmoi-up.sh'; chezmoi-up; echo \"rc=\$?\""
	[[ "$output" =~ "Pulling the source repository" ]]
	[[ "$output" =~ "skipping chezmoi init" ]]
	[[ "$output" =~ "Applying" ]]
	[[ "$output" =~ "up to date" ]]
	[[ ! "$output" =~ "command not found" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: reports failures when log.sh is unavailable" {
	local isolated="${TEST_DIR}/isolated-fail"
	mkdir -p "${isolated}"
	cp "${SCRIPT}" "${isolated}/chezmoi-up.sh"

	PATH="${TEST_DIR}/bin:${ORIGINAL_PATH}" HOME="${TEST_DIR}/home" FAKE_UPDATE_RC=1 \
		run bash -c "source '${isolated}/chezmoi-up.sh'; chezmoi-up; echo \"rc=\$?\""
	[[ "$output" =~ "chezmoi update failed" ]]
	[[ ! "$output" =~ "command not found" ]]
	[[ "$output" =~ "rc=1" ]]
}

@test "chezmoi-up: parses a compact one-line state object" {
	# chezmoi pretty-prints today, but a compact object must not leave a
	# trailing brace glued to the hash and make every run look changed.
	cat >"${TEST_DIR}/bin/chezmoi" <<'EOF'
#!/bin/bash
if [ "$1" = "source-path" ]; then echo "${FAKE_SRC}"; exit 0; fi
case "$1" in
update) echo "UPDATE: $*"; exit 0 ;;
init)   echo "INIT: $*"; exit 0 ;;
apply)  echo "APPLY: $*"; exit 0 ;;
state)  printf '{"configTemplateContentsSHA256": "%s"}\n' "${FAKE_STORED_SHA}"; exit 0 ;;
esac
EOF
	chmod +x "${TEST_DIR}/bin/chezmoi"

	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ "$output" =~ "skipping chezmoi init" ]]
	[[ ! "$output" =~ "INIT:" ]]
}

# --- fish twin --------------------------------------------------------------

_fish_available() {
	command -v fish >/dev/null 2>&1 || skip "fish not installed"
}

# _run_up_fish ARGS -> run chezmoi_up under fish with the same stubs.
_run_up_fish() {
	run fish --no-config -c "set -gx PATH '${TEST_DIR}/bin' \$PATH; \
set -gx FAKE_SRC '${FAKE_SRC}'; \
set -gx FAKE_STORED_SHA '${FAKE_STORED_SHA:-}'; \
set -gx FAKE_UPDATE_RC '${FAKE_UPDATE_RC:-0}'; \
set -gx FAKE_INIT_RC '${FAKE_INIT_RC:-0}'; \
set -gx FAKE_APPLY_RC '${FAKE_APPLY_RC:-0}'; \
source '${FISH_FUNC}'; chezmoi_up $*; echo \"rc=\$status\""
}

@test "chezmoi_up (fish): has valid syntax" {
	_fish_available
	run fish -n "${FISH_FUNC}"
	[ "$status" -eq 0 ]
}

@test "chezmoi_up (fish): help option displays usage" {
	_fish_available
	run fish --no-config -c "source '${FISH_FUNC}'; chezmoi_up --help"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: chezmoi_up" ]]
}

@test "chezmoi_up (fish): skips init when the config template is unchanged" {
	_fish_available
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up_fish
	[[ "$output" =~ "skipping chezmoi init" ]]
	[[ ! "$output" =~ "INIT:" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi_up (fish): runs init when the config template changed" {
	_fish_available
	FAKE_STORED_SHA="0000000000000000000000000000000000000000000000000000000000000000" _run_up_fish
	[[ "$output" =~ "INIT: init" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi_up (fish): --force-init runs init even when unchanged" {
	_fish_available
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up_fish --force-init
	[[ "$output" =~ "INIT: init" ]]
	[[ ! "$output" =~ "skipping chezmoi init" ]]
}

@test "chezmoi_up (fish): a failed update stops before init and apply" {
	_fish_available
	FAKE_UPDATE_RC=1 FAKE_STORED_SHA="deadbeef" _run_up_fish
	[[ "$output" =~ "chezmoi update failed" ]]
	[[ ! "$output" =~ "INIT:" ]]
	[[ ! "$output" =~ "APPLY:" ]]
	[[ "$output" =~ "rc=1" ]]
}

@test "chezmoi_up (fish): a failed init stops before apply" {
	_fish_available
	FAKE_INIT_RC=1 FAKE_STORED_SHA="deadbeef" _run_up_fish
	[[ "$output" =~ "chezmoi init failed" ]]
	[[ ! "$output" =~ "APPLY:" ]]
	[[ "$output" =~ "rc=1" ]]
}

@test "chezmoi_up (fish): czu alias is defined in aliases.fish" {
	run grep -F "alias czu 'chezmoi_up'" "${REPO_ROOT}/home/dot_config/fish/conf.d/aliases.fish"
	[ "$status" -eq 0 ]
}

# --- branch guard -----------------------------------------------------------
#
# `chezmoi update` pulls whichever branch is checked out, so chezmoi-up warns
# when the source repo is not on its default branch. The source dir used by the
# tests above is deliberately not a git repo, which is itself the "no branch to
# be wrong" case asserted below.

# _make_git_src -> turn ${TEST_DIR}/src into a clone of a bare origin on main.
_make_git_src() {
	git init -q --bare -b main "${TEST_DIR}/origin"
	git -c init.defaultBranch=main init -q "${TEST_DIR}/src"
	git -C "${TEST_DIR}/src" config user.email t@t.t
	git -C "${TEST_DIR}/src" config user.name t
	git -C "${TEST_DIR}/src" config commit.gpgsign false
	git -C "${TEST_DIR}/src" add -A
	git -C "${TEST_DIR}/src" commit -qm init
	git -C "${TEST_DIR}/src" branch -M main
	git -C "${TEST_DIR}/src" remote add origin "${TEST_DIR}/origin"
	git -C "${TEST_DIR}/src" push -q -u origin main
	git -C "${TEST_DIR}/src" remote set-head origin -a >/dev/null 2>&1 || true
}

_src_branch() {
	git -C "${TEST_DIR}/src" symbolic-ref --short -q HEAD 2>/dev/null || echo "DETACHED"
}

@test "chezmoi-up: says nothing when the source repo is on the default branch" {
	_make_git_src
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ ! "$output" =~ "not 'main'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: warns when the source repo is on another branch" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_NO=1 _run_up
	[[ "$output" =~ "is on 'feature/x', not 'main'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: warns before pulling, not after" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_NO=1 _run_up
	local warn_line update_line
	warn_line="$(printf '%s\n' "$output" | grep -n "not 'main'" | head -1 | cut -d: -f1)"
	update_line="$(printf '%s\n' "$output" | grep -n 'UPDATE:' | head -1 | cut -d: -f1)"
	[ "${warn_line}" -lt "${update_line}" ]
}

@test "chezmoi-up: declining the switch keeps the branch and still applies" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_NO=1 _run_up
	[[ "$output" =~ "Staying on 'feature/x'" ]]
	[[ "$output" =~ "APPLY: apply" ]]
	[ "$(_src_branch)" = "feature/x" ]
}

@test "chezmoi-up: accepting the switch checks out the default branch" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_YES=1 _run_up
	[[ "$output" =~ "rc=0" ]]
	[ "$(_src_branch)" = "main" ]
}

@test "chezmoi-up: refuses to switch with uncommitted changes and keeps them" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	printf 'dirty\n' >>"${TEST_DIR}/src/.chezmoi.yaml.tmpl"
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_YES=1 _run_up
	[[ "$output" =~ "uncommitted changes" ]]
	[ "$(_src_branch)" = "feature/x" ]
	grep -q dirty "${TEST_DIR}/src/.chezmoi.yaml.tmpl"
}

@test "chezmoi-up: warns about a detached HEAD" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q --detach
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_NO=1 _run_up
	[[ "$output" =~ "detached HEAD" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: CHEZMOI_UP_SKIP_BRANCH_CHECK skips the guard" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_SKIP_BRANCH_CHECK=1 _run_up
	[[ ! "$output" =~ "not 'main'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: CHEZMOI_UP_BRANCH overrides the expected branch" {
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b develop
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_BRANCH=develop _run_up
	[[ ! "$output" =~ "not 'develop'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi-up: says nothing when the source dir is not a git repo" {
	FAKE_STORED_SHA="${TEMPLATE_SHA}" _run_up
	[[ ! "$output" =~ "not 'main'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi_up (fish): warns when the source repo is on another branch" {
	_fish_available
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_NO=1 _run_up_fish
	[[ "$output" =~ "is on 'feature/x', not 'main'" ]]
	[[ "$output" =~ "rc=0" ]]
}

@test "chezmoi_up (fish): accepting the switch checks out the default branch" {
	_fish_available
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_YES=1 _run_up_fish
	[ "$(_src_branch)" = "main" ]
}

@test "chezmoi_up (fish): refuses to switch with uncommitted changes" {
	_fish_available
	_make_git_src
	git -C "${TEST_DIR}/src" checkout -q -b feature/x
	printf 'dirty\n' >>"${TEST_DIR}/src/.chezmoi.yaml.tmpl"
	FAKE_STORED_SHA="${TEMPLATE_SHA}" CHEZMOI_UP_ASSUME_YES=1 _run_up_fish
	[[ "$output" =~ "uncommitted changes" ]]
	[ "$(_src_branch)" = "feature/x" ]
}
