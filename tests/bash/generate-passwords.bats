#!/usr/bin/env bats
# Tests for generate-passwords bash function

# Setup function runs before each test
setup() {
	# Load the function
	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/generate-passwords.sh"
}

@test "generate-passwords: help option displays usage" {
	run generate-passwords --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
	[[ "$output" =~ "--count" ]]
}

@test "generate-passwords: short help option displays usage" {
	run generate-passwords -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
}

@test "generate-passwords: generates default 5 passwords of 64 chars" {
	run generate-passwords
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Generating 5 password(s) of 64 characters" ]]
	# Count the number of generated password lines (non-empty, non-header lines)
	local password_count
	password_count=$(echo "$output" | grep -cE '^[a-zA-Z0-9]{64}$')
	[ "$password_count" -eq 5 ]
}

@test "generate-passwords: generates custom length passwords" {
	run generate-passwords 16
	[ "$status" -eq 0 ]
	[[ "$output" =~ "16 characters" ]]
	local password_count
	password_count=$(echo "$output" | grep -cE '^[a-zA-Z0-9]{16}$')
	[ "$password_count" -eq 5 ]
}

@test "generate-passwords: generates custom count of passwords" {
	run generate-passwords --count 3
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Generating 3 password(s)" ]]
	local password_count
	password_count=$(echo "$output" | grep -cE '^[a-zA-Z0-9]{64}$')
	[ "$password_count" -eq 3 ]
}

@test "generate-passwords: short count option works" {
	run generate-passwords -c 2
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Generating 2 password(s)" ]]
}

@test "generate-passwords: unknown option returns error" {
	run generate-passwords --invalid
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "generate-passwords: non-numeric length returns error" {
	run generate-passwords abc
	[ "$status" -eq 1 ]
	[[ "$output" =~ "must be a positive integer" ]]
}

@test "generate-passwords: count without value returns error" {
	run generate-passwords --count
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--count requires a number" ]]
}
