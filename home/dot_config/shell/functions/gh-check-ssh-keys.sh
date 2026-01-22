#!/bin/bash
# gh-check-ssh-keys - Check if GitHub user's SSH keys are in authorized_keys
#
# Fetches public SSH keys for a GitHub user account and checks if any of them
# are present in the user's ~/.ssh/authorized_keys file. This is useful for
# verifying whether a GitHub user can authenticate via SSH.
#
# Usage: gh-check-ssh-keys [OPTIONS] USERNAME
#   USERNAME         GitHub username to check keys for
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   gh-check-ssh-keys octocat              # Check if octocat's keys are trusted
#   gh-check-ssh-keys --verbose octocat    # Check with detailed output
#
# Notes:
#   - Requires curl to be installed
#   - Requires internet connectivity to access GitHub API
#   - Uses the GitHub API: https://api.github.com/users/USERNAME/keys
#   - Exit codes: 0 = keys found, 1 = error, 2 = no keys found in authorized_keys

gh-check-ssh-keys() {
	# Initialize variables
	local verbose=false
	local username=""
	local authorized_keys_file="${HOME}/.ssh/authorized_keys"

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--verbose | -v)
			verbose=true
			shift
			;;
		-h | --help)
			echo "Usage: gh-check-ssh-keys [OPTIONS] USERNAME"
			echo "Check if GitHub user's SSH keys are in authorized_keys"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Arguments:"
			echo "  USERNAME         GitHub username to check keys for"
			echo ""
			echo "Examples:"
			echo "  gh-check-ssh-keys octocat              # Check if octocat's keys are trusted"
			echo "  gh-check-ssh-keys --verbose octocat    # Check with detailed output"
			echo ""
			echo "Exit codes:"
			echo "  0 - At least one key found in authorized_keys"
			echo "  1 - Error occurred"
			echo "  2 - No keys found in authorized_keys"
			return 0
			;;
		-*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		*)
			# Handle positional arguments
			if [ -z "$username" ]; then
				username="$1"
			else
				echo "❌ Too many arguments. Expected 1 username, got: $*"
				echo "Use --help for usage information"
				return 1
			fi
			shift
			;;
		esac
	done

	# Validation checks
	if [ -z "$username" ]; then
		echo "❌ GitHub username is required"
		echo "Use --help for usage information"
		return 1
	fi

	# Check for required commands
	if ! command -v curl >/dev/null 2>&1; then
		echo "❌ Required command 'curl' is not installed or not in PATH"
		return 1
	fi

	# Verbose output
	if [ "$verbose" = true ]; then
		echo "🔍 Checking GitHub SSH keys for user: $username"
		echo "📁 Authorized keys file: $authorized_keys_file"
	fi

	# Check if authorized_keys file exists
	if [ ! -f "$authorized_keys_file" ]; then
		if [ "$verbose" = true ]; then
			echo "ℹ️  File $authorized_keys_file does not exist"
		fi
		echo "❌ No authorized_keys file found - no keys are trusted"
		return 2
	fi

	# Fetch GitHub user's SSH keys
	local github_keys
	if [ "$verbose" = true ]; then
		echo "🌐 Fetching SSH keys from GitHub API..."
	fi

	github_keys=$(curl -sf "https://api.github.com/users/${username}/keys" 2>/dev/null)
	local curl_exit_code=$?

	if [ $curl_exit_code -ne 0 ]; then
		if [ $curl_exit_code -eq 22 ]; then
			echo "❌ User '$username' not found on GitHub"
		else
			echo "❌ Failed to fetch SSH keys from GitHub (curl exit code: $curl_exit_code)"
		fi
		return 1
	fi

	# Check if response is empty or invalid
	if [ -z "$github_keys" ] || [ "$github_keys" = "[]" ]; then
		echo "❌ User '$username' has no public SSH keys on GitHub"
		return 1
	fi

	# Extract public keys from JSON response
	# The API returns: [{"id": 123, "key": "ssh-rsa AAAA..."}, ...]
	# Note: Using grep/sed instead of jq to avoid external dependencies
	# This works for the standard GitHub API response format
	local keys_array
	keys_array=$(echo "$github_keys" | grep -Eo '"key":\s*"[^"]*"' | sed 's/"key":\s*"//g' | sed 's/"//g')

	if [ -z "$keys_array" ]; then
		echo "❌ Failed to parse SSH keys from GitHub response"
		if [ "$verbose" = true ]; then
			echo "ℹ️  API response format may have changed or be malformed"
		fi
		return 1
	fi

	# Count total keys
	local total_keys
	total_keys=$(echo "$keys_array" | wc -l | tr -d ' ')

	if [ "$verbose" = true ]; then
		echo "📋 Found $total_keys SSH key(s) for user '$username' on GitHub"
	fi

	# Check each key against authorized_keys
	local found_count=0
	local key_num=0

	while IFS= read -r key; do
		if [ -z "$key" ]; then
			continue
		fi

		key_num=$((key_num + 1))

		# Extract just the key part (without key type and comment)
		# This handles keys in format: "ssh-rsa AAAA... comment"
		# SSH keys typically have: key_type key_data [optional_comment]
		# We match on key_type + key_data to avoid false positives from comments
		local key_data
		key_data=$(echo "$key" | awk '{print $1 " " $2}')

		# Skip if key parsing failed
		if [ -z "$key_data" ] || [ $(echo "$key_data" | wc -w) -ne 2 ]; then
			if [ "$verbose" = true ]; then
				echo "⚠️  Key #${key_num} has unexpected format, skipping"
			fi
			continue
		fi

		if grep -qF "$key_data" "$authorized_keys_file"; then
			found_count=$((found_count + 1))
			if [ "$verbose" = true ]; then
				local key_type
				key_type=$(echo "$key" | awk '{print $1}')
				local key_preview
				key_preview=$(echo "$key" | awk '{print substr($2, 1, 20)}')
				echo "✅ Key #${key_num} ($key_type ${key_preview}...) is trusted"
			fi
		else
			if [ "$verbose" = true ]; then
				local key_type
				key_type=$(echo "$key" | awk '{print $1}')
				local key_preview
				key_preview=$(echo "$key" | awk '{print substr($2, 1, 20)}')
				echo "❌ Key #${key_num} ($key_type ${key_preview}...) is NOT trusted"
			fi
		fi
	done <<<"$keys_array"

	# Report results
	if [ $found_count -gt 0 ]; then
		echo "✅ Found $found_count of $total_keys key(s) from '$username' in authorized_keys"
		return 0
	else
		echo "❌ None of the $total_keys key(s) from '$username' are in authorized_keys"
		return 2
	fi
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	gh-check-ssh-keys "$@"
fi
