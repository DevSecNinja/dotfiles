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

	mkdir -p "${TEST_DIR}/bin" "${TEST_DIR}/src"
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
	PATH="${TEST_DIR}/bin:${ORIGINAL_PATH}" run bash -c "source '${SCRIPT}'; chezmoi-up $*; echo \"rc=\$?\""
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
