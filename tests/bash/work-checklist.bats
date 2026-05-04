#!/usr/bin/env bats
# Tests for work-checklist

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/work-checklist.sh"
}

@test "work-checklist: prints CloudMFA URL" {
	run work-checklist
	[ "$status" -eq 0 ]
	[[ "$output" =~ "https://aka.ms/CloudMFA" ]]
}

@test "work-checklist: mentions yk-enroll" {
	run work-checklist
	[ "$status" -eq 0 ]
	[[ "$output" =~ "yk-enroll" ]]
}

@test "work-checklist: idempotent (no side effects, repeatable)" {
	run work-checklist
	first="$output"
	run work-checklist
	[ "$first" = "$output" ]
}

@test "work-checklist: includes BOTH gh ssh-key add types" {
	run work-checklist
	[ "$status" -eq 0 ]
	[[ "$output" =~ "--type authentication" ]]
	[[ "$output" =~ "--type signing" ]]
}

@test "work-checklist: includes git signing wiring step" {
	run work-checklist
	[ "$status" -eq 0 ]
	[[ "$output" =~ "yk-git-sign-setup" ]]
	[[ "$output" =~ "Wire git for SSH commit signing" ]]
}
