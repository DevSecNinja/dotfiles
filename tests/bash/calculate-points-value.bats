#!/usr/bin/env bats
# Tests for calculate-points-value shell function

setup() {
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/calculate-points-value.sh"
}

@test "calculate-points-value: help option displays usage" {
	run calculate-points-value --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: calculate-points-value" ]]
	[[ "$output" =~ "name1" ]]
}

@test "calculate-points-value: short help option works" {
	run calculate-points-value -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: calculate-points-value" ]]
}

@test "calculate-points-value: fails with invalid number of arguments" {
	run calculate-points-value 1 2 3
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Invalid number of arguments" ]]
}

@test "calculate-points-value: fails with no arguments" {
	run calculate-points-value
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Invalid number of arguments" ]]
}

@test "calculate-points-value: works with 4 numeric arguments" {
	run calculate-points-value 8000 180 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Option 1" ]]
	[[ "$output" =~ "Option 2" ]]
	[[ "$output" =~ "8000 points for €180" ]]
	[[ "$output" =~ "25000 points for €268" ]]
	[[ "$output" =~ "better value" ]]
}

@test "calculate-points-value: works with 6 arguments including names" {
	run calculate-points-value "Regency Bali" 8000 180 "Regency Seattle" 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Regency Bali" ]]
	[[ "$output" =~ "Regency Seattle" ]]
}

@test "calculate-points-value: option 1 better when its value is higher" {
	# Option 1: 180/8000 = 0.0225, Option 2: 268/25000 = 0.0107
	run calculate-points-value 8000 180 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Option 1 offers better value" ]]
}

@test "calculate-points-value: option 2 better when its value is higher" {
	run calculate-points-value 25000 268 8000 180
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Option 2 offers better value" ]]
}

@test "calculate-points-value: shows percent better" {
	run calculate-points-value 8000 180 25000 268
	[ "$status" -eq 0 ]
	[[ "$output" =~ "%" ]]
	[[ "$output" =~ "better value than" ]]
}
