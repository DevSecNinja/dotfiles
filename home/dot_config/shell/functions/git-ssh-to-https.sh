#!/bin/bash
# git-ssh-to-https - Convert Git origin remote from SSH to HTTPS
#
# This function converts the current repository's origin remote URL
# from SSH format to HTTPS format for Git hosting services.
#
# Usage: git-ssh-to-https [--dry-run|-n]
#   --dry-run, -n    Show what would be changed without making changes

git-ssh-to-https() {
	local dry_run=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run | -n)
			dry_run=true
			shift
			;;
		-h | --help)
			echo "Usage: git-ssh-to-https [--dry-run|-n]"
			echo "Convert Git origin remote from SSH to HTTPS format"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be changed without making changes"
			echo "  -h, --help       Show this help message"
			return 0
			;;
		*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		esac
	done

	# Check if we're in a git repository
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "❌ Not in a git repository"
		return 1
	fi

	# Get the current origin URL
	local current_url
	if ! current_url=$(git remote get-url origin 2>/dev/null) || [ -z "$current_url" ]; then
		echo "❌ No origin remote found"
		return 1
	fi

	echo "🔍 Current origin: $current_url"

	# Check if it's already HTTPS
	if [[ "$current_url" == https://* ]]; then
		echo "✅ Origin is already using HTTPS format"
		return 0
	fi

	local host=""
	local path=""

	if [[ "$current_url" =~ ^git@([^:]+):(.+)$ ]]; then
		host="${BASH_REMATCH[1]}"
		path="${BASH_REMATCH[2]}"
	elif [[ "$current_url" =~ ^ssh://git@([^/]+)/(.+)$ ]]; then
		host="${BASH_REMATCH[1]}"
		path="${BASH_REMATCH[2]}"
	else
		echo "❌ Unsupported URL format: $current_url"
		echo "💡 This function supports SSH URLs like git@github.com:user/repo.git and ssh://git@github.com/user/repo.git"
		return 1
	fi

	path="${path%.git}"
	local https_url="https://${host}/${path}.git"

	if [[ "$dry_run" == true ]]; then
		echo "🔍 DRY RUN - No changes will be made"
		echo "🔄 Would convert to HTTPS: $https_url"
		echo "💡 Run without --dry-run to apply the changes"
	else
		echo "🔄 Converting to HTTPS: $https_url"

		# Update the origin remote
		if git remote set-url origin "$https_url"; then
			echo "✅ Successfully converted origin to HTTPS format"
			echo "🔗 New origin: $(git remote get-url origin)"
		else
			echo "❌ Failed to update origin remote"
			return 1
		fi
	fi
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	git-ssh-to-https "$@"
fi
