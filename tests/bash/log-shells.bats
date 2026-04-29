#!/usr/bin/env bats
# Cross-shell consistency: sh / bash / zsh / fish wrapper produce identical
# output for the same call.

load 'helpers/common'

setup() {
	common_setup
	LOG_SCRIPT="$REPO_ROOT/home/dot_config/shell/functions/log.sh"
	export LOG_SCRIPT LOG_JOURNAL=never LOG_COLOR=never
	export LOG_TIMESTAMP="2026-04-29T12:00:00Z"
}

teardown() { common_teardown; }

run_log_in() {
	local sh_cmd="$1"
	"$sh_cmd" -c '. "$1"; LOG_TAG=t log_info "cross-shell"' sh "$LOG_SCRIPT"
}

@test "shells: sh and bash produce identical output" {
	sh_out=$(run_log_in sh)
	bash_out=$(run_log_in bash)
	[ "$sh_out" = "$bash_out" ]
}

@test "shells: zsh produces same output as bash when sourced" {
	if ! command -v zsh >/dev/null 2>&1; then skip "zsh not installed"; fi
	bash_out=$(run_log_in bash)
	zsh_out=$(run_log_in zsh)
	[ "$bash_out" = "$zsh_out" ]
}

@test "shells: real script run from bash and zsh shows same auto-tag" {
	if ! command -v zsh >/dev/null 2>&1; then skip "zsh not installed"; fi
	tmp="$BATS_TEST_TMPDIR/job.sh"
	cat >"$tmp" <<-EOF
		#!/bin/sh
		. "$LOG_SCRIPT"
		log_info "x"
	EOF
	chmod +x "$tmp"
	bash_out=$(env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_JOURNAL=never LOG_COLOR=never bash "$tmp")
	zsh_out=$(env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_JOURNAL=never LOG_COLOR=never zsh "$tmp")
	[ "$bash_out" = "$zsh_out" ]
	[[ "$bash_out" == *"[job] x"* ]]
}

@test "shells: standalone invocation works from any shell" {
	for sh_cmd in sh bash zsh; do
		command -v "$sh_cmd" >/dev/null 2>&1 || continue
		run "$sh_cmd" -c '"$1" INFO "via standalone"' "$sh_cmd" "$LOG_SCRIPT"
		assert_success
		assert_output --partial "via standalone"
	done
}

@test "shells: fish wrapper produces same content as bash standalone" {
	if ! command -v fish >/dev/null 2>&1; then skip "fish not installed"; fi
	# Fish wrapper as defined in config.fish: bash $script $argv
	# Use --no-config to avoid the user's config.fish startup banners.
	bash_out=$(env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG=t LOG_JOURNAL=never LOG_COLOR=never bash "$LOG_SCRIPT" INFO "fish-test")
	fish_out=$(env LOG_TIMESTAMP="2026-04-29T12:00:00Z" LOG_TAG=t LOG_JOURNAL=never LOG_COLOR=never fish --no-config -c "bash $LOG_SCRIPT INFO fish-test")
	[ "$bash_out" = "$fish_out" ]
}
