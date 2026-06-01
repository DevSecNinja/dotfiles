#!/usr/bin/env bats
# Tests for miles_deal fish function

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	FUNCTION_PATH="$REPO_ROOT/home/dot_config/fish/functions/miles_deal.fish"
	export FUNCTION_PATH
}

run_fn() {
	fish --no-config -c "source '$FUNCTION_PATH'; miles_deal $*"
}

@test "miles_deal: function file exists" {
	[ -f "$FUNCTION_PATH" ]
}

@test "miles_deal: function file has valid syntax" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run fish -n "$FUNCTION_PATH"
	[ "$status" -eq 0 ]
}

@test "miles_deal: help option displays usage" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: miles_deal" ]]
	[[ "$output" =~ "MILES_COST" ]]
	[[ "$output" =~ "--value" ]]
}

@test "miles_deal: short help option works" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: miles_deal" ]]
}

@test "miles_deal: fails with too few arguments" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 45375 256.66
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected 3 arguments" ]]
}

@test "miles_deal: fails with too many arguments" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 45375 256.66 4927 999
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Expected 3 arguments" ]]
}

@test "miles_deal: rejects non-numeric miles cost" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn abc 256.66 4927
	[ "$status" -eq 1 ]
	[[ "$output" =~ "MILES_COST must be a non-negative number" ]]
}

@test "miles_deal: rejects non-numeric fee" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 45375 abc 4927
	[ "$status" -eq 1 ]
	[[ "$output" =~ "MILES_FEE must be a non-negative number" ]]
}

@test "miles_deal: rejects zero miles cost" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 0 256.66 4927
	[ "$status" -eq 1 ]
	[[ "$output" =~ "MILES_COST must be greater than zero" ]]
}

@test "miles_deal: rejects invalid --value" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn --value xyz 45375 256.66 4927
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--value must be a non-negative number" ]]
}

@test "miles_deal: good deal when miles beat cash at benchmark" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# At 0.6 c/mile: 45375 * 0.006 + 256.66 = 528.91 < 4927 -> use miles
	run run_fn --value 0.6 45375 256.66 4927
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Use miles" ]]
}

@test "miles_deal: pay cash when miles do not beat cash at benchmark" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# At 12 c/mile: 45375 * 0.12 + 256.66 = 5701.66 > 4927 -> pay cash
	run run_fn --value 12 45375 256.66 4927
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Pay cash" ]]
}

@test "miles_deal: reports per-mile value in cents" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	# (4927 - 256.66) / 45375 * 100 = 10.293 cents/mile
	run run_fn 45375 256.66 4927
	[ "$status" -eq 0 ]
	[[ "$output" =~ "10.293 c/mile" ]]
}

@test "miles_deal: default benchmark is 1.2 cents" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn 45375 256.66 4927
	[ "$status" -eq 0 ]
	[[ "$output" =~ "1.2 c/mile" ]]
}

@test "miles_deal: honors custom currency symbol" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi
	run run_fn -c GBP 60000 75 950
	[ "$status" -eq 0 ]
	[[ "$output" == *'GBP950'* ]]
}
