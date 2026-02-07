#!/usr/bin/env bats
# Tests for calculate-points-value bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/calculate-points-value.sh"
}

@test "calculate-points-value: help option displays usage" {
	run calculate-points-value --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: calculate-points-value" ]]
}

@test "calculate-points-value: short help option displays usage" {
	run calculate-points-value -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: calculate-points-value" ]]
}

@test "calculate-points-value: compares two options with 4 arguments" {
	run calculate-points-value 8000 180 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Points/miles value analysis" ]]
	[[ "$output" =~ "Option 1" ]]
	[[ "$output" =~ "Option 2" ]]
	[[ "$output" =~ "better value" ]]
}

@test "calculate-points-value: compares two options with 6 arguments (named)" {
	run calculate-points-value "Hotel A" 8000 180 "Hotel B" 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Hotel A" ]]
	[[ "$output" =~ "Hotel B" ]]
	[[ "$output" =~ "better value" ]]
}

@test "calculate-points-value: fails with wrong number of arguments" {
	run calculate-points-value 8000 180
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Invalid number of arguments" ]]
}

@test "calculate-points-value: fails with too many arguments" {
	run calculate-points-value 1 2 3 4 5 6 7
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Invalid number of arguments" ]]
}
