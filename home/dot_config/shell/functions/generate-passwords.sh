#!/bin/bash
# generate-passwords - Generate secure random passwords
#
# Generates multiple alphanumeric passwords using /dev/urandom.
# By default, generates 5 passwords of 64 characters each.
#
# Usage: generate-passwords [OPTIONS] [LENGTH]
#   LENGTH           Length of passwords to generate (default: 64)
#   --count, -c N    Number of passwords to generate (default: 5)
#   --help, -h       Show help message and exit
#
# Examples:
#   generate-passwords              # Generate 5 passwords of 64 characters
#   generate-passwords 32           # Generate 5 passwords of 32 characters
#   generate-passwords --count 10   # Generate 10 passwords of 64 characters
#   generate-passwords 16 --count 3 # Generate 3 passwords of 16 characters
#
# Notes:
#   - Uses alphanumeric characters only (a-z, A-Z, 0-9)
#   - Requires /dev/urandom for random data generation
#   - Each password is generated independently for maximum entropy

generate-passwords() {
	# Initialize variables
	local pass_length=64
	local pass_count=5

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--count | -c)
			if [[ -z "$2" ]] || [[ "$2" =~ ^- ]]; then
				echo "❌ --count requires a number argument"
				echo "Use --help for usage information"
				return 1
			fi
			if ! [[ "$2" =~ ^[0-9]+$ ]]; then
				echo "❌ Count must be a positive integer"
				return 1
			fi
			pass_count="$2"
			shift 2
			;;
		-h | --help)
			echo "Usage: generate-passwords [OPTIONS] [LENGTH]"
			echo "Generate secure random alphanumeric passwords"
			echo ""
			echo "Arguments:"
			echo "  LENGTH           Length of passwords (default: 64)"
			echo ""
			echo "Options:"
			echo "  --count, -c N    Number of passwords to generate (default: 5)"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Examples:"
			echo "  generate-passwords              # Generate 5 passwords of 64 characters"
			echo "  generate-passwords 32           # Generate 5 passwords of 32 characters"
			echo "  generate-passwords --count 10   # Generate 10 passwords of 64 characters"
			echo "  generate-passwords 16 --count 3 # Generate 3 passwords of 16 characters"
			return 0
			;;
		-*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		*)
			# Handle positional argument (password length)
			if ! [[ "$1" =~ ^[0-9]+$ ]]; then
				echo "❌ Password length must be a positive integer"
				return 1
			fi
			pass_length="$1"
			shift
			;;
		esac
	done

	# Validation checks
	if ! [ -r /dev/urandom ]; then
		echo "❌ Cannot read from /dev/urandom"
		return 1
	fi

	if [ "$pass_length" -lt 1 ]; then
		echo "❌ Password length must be at least 1 character"
		return 1
	fi

	if [ "$pass_count" -lt 1 ]; then
		echo "❌ Password count must be at least 1"
		return 1
	fi

	# Main logic
	echo "🔐 Generating $pass_count password(s) of $pass_length characters each:"
	echo ""

	for _ in $(seq 1 "$pass_count"); do
		LC_ALL=C tr -cd '[:alnum:]' </dev/urandom | fold -w"${pass_length}" | head -n 1
	done

	return 0
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	generate-passwords "$@"
fi
