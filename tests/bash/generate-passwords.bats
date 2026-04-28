#!/usr/bin/env bats
# Tests for generate-passwords shell function

setup() {
	mock_bin="$BATS_TEST_TMPDIR/bin"
	mkdir -p "$mock_bin"
	cat >"$mock_bin/tr" <<'EOF'
#!/usr/bin/env bash
printf 'A%.0s' {1..1024}
printf '\n'
EOF
	chmod +x "$mock_bin/tr"
	export PATH="$mock_bin:$PATH"

	load "${BATS_TEST_DIRNAME}/../../home/dot_config/shell/functions/generate-passwords.sh"
}

# The function normally reads from /dev/urandom via tr|fold|head. The setup()
# PATH shim keeps tests deterministic and prevents Bats from waiting on
# orphaned processes that can keep Bats-owned file descriptors open in CI.

@test "generate-passwords: help option displays usage" {
	run generate-passwords --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
	[[ "$output" =~ "LENGTH" ]]
	[[ "$output" =~ "--count" ]]
}

@test "generate-passwords: short help option works" {
	run generate-passwords -h
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: generate-passwords" ]]
}

@test "generate-passwords: invalid count returns error" {
	run generate-passwords --count abc
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Count must be a positive integer" ]]
}

@test "generate-passwords: missing count argument returns error" {
	run generate-passwords --count
	[ "$status" -eq 1 ]
	[[ "$output" =~ "--count requires" ]]
}

@test "generate-passwords: invalid length returns error" {
	run generate-passwords abc
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Password length must be a positive integer" ]]
}

@test "generate-passwords: unknown option returns error" {
	run generate-passwords --invalid-option
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown option" ]]
}

@test "generate-passwords: defaults produce 5 passwords of length 64" {
	run generate-passwords
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{64}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate-passwords: custom length produces correct length passwords" {
	run generate-passwords 16
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{16}$' | wc -l)
	[ "$password_lines" -eq 5 ]
}

@test "generate-passwords: custom count produces correct number of passwords" {
	run generate-passwords 12 --count 3
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{12}$' | wc -l)
	[ "$password_lines" -eq 3 ]
}

@test "generate-passwords: short -c count flag works" {
	run generate-passwords 10 -c 2
	[ "$status" -eq 0 ]
	password_lines=$(echo "$output" | grep -E '^[A-Za-z0-9]{10}$' | wc -l)
	[ "$password_lines" -eq 2 ]
}

@test "generate-passwords: header includes count and length" {
	run generate-passwords 8 --count 2
	[ "$status" -eq 0 ]
	[[ "$output" =~ "2 password" ]]
	[[ "$output" =~ "8 characters" ]]
}
