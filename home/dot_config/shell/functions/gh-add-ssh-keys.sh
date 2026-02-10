#!/bin/bash
# gh-add-ssh-keys - Add GitHub user's SSH keys to authorized_keys
#
# Fetches public SSH keys for a GitHub user account and adds them to the
# user's ~/.ssh/authorized_keys file. This allows the GitHub user to
# authenticate via SSH to this system.
#
# Usage: gh-add-ssh-keys [OPTIONS] USERNAME
#   USERNAME         GitHub username to add keys for
#   --dry-run, -n    Show what would be added without making changes
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   gh-add-ssh-keys octocat              # Add octocat's keys to authorized_keys
#   gh-add-ssh-keys --dry-run octocat    # Preview what would be added
#   gh-add-ssh-keys --verbose octocat    # Add with detailed output
#
# Notes:
#   - Requires curl to be installed
#   - Requires internet connectivity to access GitHub API
#   - Creates ~/.ssh directory if it doesn't exist (with mode 700)
#   - Creates/updates ~/.ssh/authorized_keys (with mode 600)
#   - Only adds keys that don't already exist
#   - Adds a comment line before each key identifying the source

gh-add-ssh-keys() {
	# Initialize variables
	local dry_run=false
	local verbose=false
	local username=""
	local authorized_keys_file="${HOME}/.ssh/authorized_keys"
	local ssh_dir="${HOME}/.ssh"
	local changes_made=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run | -n)
			dry_run=true
			shift
			;;
		--verbose | -v)
			verbose=true
			shift
			;;
		-h | --help)
			echo "Usage: gh-add-ssh-keys [OPTIONS] USERNAME"
			echo "Add GitHub user's SSH keys to authorized_keys"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be added without making changes"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Arguments:"
			echo "  USERNAME         GitHub username to add keys for"
			echo ""
			echo "Examples:"
			echo "  gh-add-ssh-keys octocat              # Add octocat's keys to authorized_keys"
			echo "  gh-add-ssh-keys --dry-run octocat    # Preview what would be added"
			echo "  gh-add-ssh-keys --verbose octocat    # Add with detailed output"
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
		# Check if CHEZMOI_GITHUB_USERNAME environment variable is set
		if [ -n "${CHEZMOI_GITHUB_USERNAME:-}" ]; then
			# Check if we're in an interactive environment (stdin is a TTY)
			# AND not in CI/test environment (CI, BATS_VERSION, etc.)
			if [ -t 0 ] && [ -z "${CI:-}" ] && [ -z "${BATS_VERSION:-}" ]; then
				# Ask for confirmation before using the detected username
				echo "🔍 No username provided, detected GitHub username from chezmoi config: $CHEZMOI_GITHUB_USERNAME"
				printf "Do you want to use this username? (y/N): "
				# Use read with timeout to prevent hanging in non-interactive environments
				if read -t 30 -r response; then
					if [[ "$response" =~ ^[Yy]$ ]]; then
						username="$CHEZMOI_GITHUB_USERNAME"
						echo "✅ Using GitHub username: $username"
					else
						echo "❌ GitHub username is required"
						echo "Use --help for usage information"
						return 1
					fi
				else
					# Timeout or no input
					echo ""
					echo "❌ GitHub username is required"
					echo "Use --help for usage information"
					return 1
				fi
			else
				# Non-interactive environment - cannot prompt for confirmation
				echo "❌ GitHub username is required"
				echo "💡 Detected CHEZMOI_GITHUB_USERNAME='$CHEZMOI_GITHUB_USERNAME' but cannot confirm in non-interactive mode"
				echo "Use --help for usage information"
				return 1
			fi
		else
			echo "❌ GitHub username is required"
			echo "Use --help for usage information"
			return 1
		fi
	fi

	# Check for required commands
	if ! command -v curl >/dev/null 2>&1; then
		echo "❌ Required command 'curl' is not installed or not in PATH"
		return 1
	fi

	# Verbose output
	if [ "$verbose" = true ]; then
		echo "🔍 Adding GitHub SSH keys for user: $username"
		echo "📁 SSH directory: $ssh_dir"
		echo "📁 Authorized keys file: $authorized_keys_file"
	fi

	# Check/create .ssh directory
	if [ ! -d "$ssh_dir" ]; then
		if [ "$dry_run" = true ]; then
			echo "🔍 [DRY RUN] Would create directory: $ssh_dir (mode 700)"
		else
			if [ "$verbose" = true ]; then
				echo "📁 Creating directory: $ssh_dir (mode 700)"
			fi
			mkdir -p "$ssh_dir" || {
				echo "❌ Failed to create directory: $ssh_dir"
				return 1
			}
			chmod 700 "$ssh_dir" || {
				echo "❌ Failed to set permissions on: $ssh_dir"
				return 1
			}
			changes_made=true
		fi
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

	# Check if response is empty
	if [ -z "$github_keys" ]; then
		echo "❌ Failed to fetch SSH keys from GitHub"
		return 1
	fi

	# Extract public keys from JSON response
	# Note: Using grep/sed instead of jq to avoid external dependencies
	# This works for the standard GitHub API response format
	local keys_array
	keys_array=$(echo "$github_keys" | grep -Eo '"key":\s*"[^"]*"' | sed 's/"key":\s*"//g' | sed 's/"//g')

	# If no keys extracted, check if it's an empty array or a parse error
	if [ -z "$keys_array" ]; then
		# Strip whitespace and check if response is just an empty array []
		if echo "$github_keys" | tr -d '\n\r\t ' | grep -q '^\[\]$'; then
			echo "❌ User '$username' has no public SSH keys on GitHub"
		else
			echo "❌ Failed to parse SSH keys from GitHub response"
			if [ "$verbose" = true ]; then
				echo "ℹ️  API response format may have changed or be malformed"
			fi
		fi
		return 1
	fi

	# Count total keys
	local total_keys
	total_keys=$(echo "$keys_array" | wc -l | tr -d ' ')

	if [ "$verbose" = true ]; then
		echo "📋 Found $total_keys SSH key(s) for user '$username' on GitHub"
	fi

	# Check if authorized_keys exists, if not create it with proper permissions
	local authorized_keys_content=""
	if [ -f "$authorized_keys_file" ]; then
		authorized_keys_content=$(cat "$authorized_keys_file")
	else
		# Create authorized_keys with correct permissions before writing to it
		# This prevents a security window where the file could have wrong permissions
		if [ "$dry_run" = false ]; then
			touch "$authorized_keys_file" || {
				echo "❌ Failed to create: $authorized_keys_file"
				return 1
			}
			chmod 600 "$authorized_keys_file" || {
				echo "❌ Failed to set permissions on: $authorized_keys_file"
				return 1
			}
			if [ "$verbose" = true ]; then
				echo "📝 Created $authorized_keys_file with mode 600"
			fi
		fi
	fi

	# Process each key
	local added_count=0
	local skipped_count=0
	local key_num=0

	while IFS= read -r key; do
		if [ -z "$key" ]; then
			continue
		fi

		key_num=$((key_num + 1))

		# Extract just the key part (without comment)
		# SSH keys typically have: key_type key_data [optional_comment]
		# We match on key_type + key_data to avoid false positives from comments
		local key_data
		key_data=$(echo "$key" | awk '{print $1 " " $2}')

		# Skip if key parsing failed
		if [ -z "$key_data" ] || [ "$(echo "$key_data" | wc -w)" -ne 2 ]; then
			if [ "$verbose" = true ]; then
				echo "⚠️  Key #${key_num} has unexpected format, skipping"
			fi
			continue
		fi

		# Check if key already exists
		if [ -n "$authorized_keys_content" ] && echo "$authorized_keys_content" | grep -qF "$key_data"; then
			skipped_count=$((skipped_count + 1))
			if [ "$verbose" = true ]; then
				local key_type
				key_type=$(echo "$key" | awk '{print $1}')
				local key_preview
				key_preview=$(echo "$key" | awk '{print substr($2, 1, 20)}')
				echo "⏭️  Key #${key_num} ($key_type ${key_preview}...) already exists, skipping"
			fi
		else
			# Key needs to be added
			added_count=$((added_count + 1))
			local key_type
			key_type=$(echo "$key" | awk '{print $1}')
			local key_preview
			key_preview=$(echo "$key" | awk '{print substr($2, 1, 20)}')

			if [ "$dry_run" = true ]; then
				echo "🔍 [DRY RUN] Would add key #${key_num}: $key_type ${key_preview}..."
			else
				if [ "$verbose" = true ]; then
					echo "➕ Adding key #${key_num}: $key_type ${key_preview}..."
				fi

				# Add comment line and key
				{
					echo "# GitHub user: $username (key #${key_num})"
					echo "$key"
				} >>"$authorized_keys_file" || {
					echo "❌ Failed to write to: $authorized_keys_file"
					return 1
				}
				changes_made=true
			fi
		fi
	done <<<"$keys_array"

	# Set proper permissions on authorized_keys
	if [ "$dry_run" = false ] && [ "$changes_made" = true ]; then
		chmod 600 "$authorized_keys_file" || {
			echo "❌ Failed to set permissions on: $authorized_keys_file"
			return 1
		}
		if [ "$verbose" = true ]; then
			echo "🔒 Set permissions on $authorized_keys_file to 600"
		fi
	fi

	# Report results
	if [ "$dry_run" = true ]; then
		echo ""
		echo "🔍 [DRY RUN] Summary:"
		echo "   Would add: $added_count key(s)"
		echo "   Would skip: $skipped_count key(s) (already exist)"
		echo "   Total keys: $total_keys"
		echo ""
		echo "Run without --dry-run to apply the changes"
		return 0
	fi

	if [ $added_count -gt 0 ]; then
		echo "✅ Successfully added $added_count key(s) from '$username' to authorized_keys"
		if [ $skipped_count -gt 0 ]; then
			echo "ℹ️  Skipped $skipped_count key(s) that already existed"
		fi
		if [ "$verbose" = true ]; then
			echo "📋 Summary:"
			echo "   Added: $added_count key(s)"
			echo "   Skipped: $skipped_count key(s)"
			echo "   Total: $total_keys key(s)"
		fi
	elif [ $skipped_count -gt 0 ]; then
		echo "ℹ️  All $total_keys key(s) from '$username' already exist in authorized_keys"
	else
		echo "ℹ️  No changes needed"
	fi

	return 0
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	gh-add-ssh-keys "$@"
fi
