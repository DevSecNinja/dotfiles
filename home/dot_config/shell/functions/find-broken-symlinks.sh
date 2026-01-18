#!/bin/bash
# find-broken-symlinks - Find and optionally remove broken symbolic links
#
# This function recursively searches for broken symbolic links in a specified
# directory and prompts for removal confirmation. Broken symlinks are those
# that point to non-existent targets.
#
# Usage: find-broken-symlinks [OPTIONS] [DIRECTORY]
#   --dry-run, -n    Show what would be removed without making changes
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#   --yes, -y        Skip confirmation prompts and remove all broken symlinks
#
# Examples:
#   find-broken-symlinks                       # Check current directory
#   find-broken-symlinks /path/to/dir          # Check specific directory
#   find-broken-symlinks --dry-run ~/projects  # Preview without removing
#   find-broken-symlinks --yes ~/old-files     # Remove all without prompting
#
# Notes:
#   - Requires 'find' command (standard on Unix-like systems)
#   - Only checks symbolic links, not regular files or directories
#   - Uses 'test -e' to determine if symlink target exists

find-broken-symlinks() {
	# Initialize variables
	local dry_run=false
	local verbose=false
	local auto_confirm=false
	local target_dir=""
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
		--yes | -y)
			auto_confirm=true
			shift
			;;
		-h | --help)
			echo "Usage: find-broken-symlinks [OPTIONS] [DIRECTORY]"
			echo "Find and optionally remove broken symbolic links"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be removed without making changes"
			echo "  --verbose, -v    Enable verbose output"
			echo "  --yes, -y        Skip confirmation prompts and remove all broken symlinks"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Arguments:"
			echo "  DIRECTORY        Directory to search (default: current directory)"
			echo ""
			echo "Examples:"
			echo "  find-broken-symlinks                       # Check current directory"
			echo "  find-broken-symlinks /path/to/dir          # Check specific directory"
			echo "  find-broken-symlinks --dry-run ~/projects  # Preview without removing"
			echo "  find-broken-symlinks --yes ~/old-files     # Remove all without prompting"
			return 0
			;;
		-*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		*)
			# Handle positional arguments
			if [ -z "$target_dir" ]; then
				target_dir="$1"
			else
				echo "❌ Too many arguments. Expected at most 1 directory, got: $*"
				echo "Use --help for usage information"
				return 1
			fi
			shift
			;;
		esac
	done

	# Set default target directory to current directory if not provided
	if [ -z "$target_dir" ]; then
		target_dir="."
	fi

	# Validation checks
	# Check if find command is available
	if ! command -v find >/dev/null 2>&1; then
		echo "❌ Required command 'find' is not installed or not in PATH"
		return 1
	fi

	# Check if target directory exists
	if [ ! -d "$target_dir" ]; then
		echo "❌ Directory does not exist: $target_dir"
		return 1
	fi

	# Check if target directory is readable
	if [ ! -r "$target_dir" ]; then
		echo "❌ Directory is not readable: $target_dir"
		return 1
	fi

	# Get absolute path for better display
	if ! target_dir=$(cd "$target_dir" && pwd); then
		echo "❌ Failed to access directory: $target_dir"
		return 1
	fi

	# Verbose output
	if [ "$verbose" = true ]; then
		echo "🔍 Running find-broken-symlinks with arguments:"
		echo "   Dry run: $dry_run"
		echo "   Verbose: $verbose"
		echo "   Auto-confirm: $auto_confirm"
		echo "   Target directory: $target_dir"
	fi

	# Main logic starts here
	echo "🔍 Searching for broken symlinks in: $target_dir"

	# Find all broken symlinks
	# -L tells find to follow symlinks and report those that are broken
	# -type l finds symbolic links
	# When combined with -L, only broken symlinks (those whose targets don't exist) are matched
	local broken_symlinks=()
	while IFS= read -r -d '' link; do
		broken_symlinks+=("$link")
	done < <(find -L "$target_dir" -type l -print0 2>/dev/null)

	# Check if any broken symlinks were found
	if [ ${#broken_symlinks[@]} -eq 0 ]; then
		echo "✅ No broken symlinks found in $target_dir"
		return 0
	fi

	# Display found broken symlinks
	echo ""
	echo "🔗 Found ${#broken_symlinks[@]} broken symlink(s):"
	for link in "${broken_symlinks[@]}"; do
		# Get the target the symlink points to
		local target
		target=$(readlink "$link")
		echo "  📌 $link -> $target"
	done
	echo ""

	# Handle dry-run mode
	if [ "$dry_run" = true ]; then
		echo "🔍 [DRY RUN] Would remove ${#broken_symlinks[@]} broken symlink(s)"
		for link in "${broken_symlinks[@]}"; do
			echo "   - Would remove: $link"
		done
		echo ""
		echo "💡 Run without --dry-run to actually remove these symlinks"
		return 0
	fi

	# Confirm removal unless auto-confirm is set
	if [ "$auto_confirm" = false ]; then
		read -p "❓ Do you want to remove these broken symlinks? [y/N] " response
		case "$response" in
		[yY] | [yY][eE][sS])
			echo "🗑️  Removing broken symlinks..."
			;;
		*)
			echo "ℹ️  Removal cancelled by user"
			return 0
			;;
		esac
	else
		echo "🗑️  Auto-removing broken symlinks (--yes flag)..."
	fi

	# Remove broken symlinks
	local removed_count=0
	local failed_count=0

	for link in "${broken_symlinks[@]}"; do
		if [ "$verbose" = true ]; then
			echo "   Removing: $link"
		fi

		if rm "$link" 2>/dev/null; then
			removed_count=$((removed_count + 1))
			changes_made=true
		else
			echo "   ❌ Failed to remove: $link"
			failed_count=$((failed_count + 1))
		fi
	done

	# Report results
	echo ""
	if [ "$changes_made" = true ]; then
		echo "✅ Successfully removed $removed_count broken symlink(s)"
		if [ $failed_count -gt 0 ]; then
			echo "⚠️  Failed to remove $failed_count symlink(s)"
			echo "💡 You may need elevated permissions for some files"
		fi
		if [ "$verbose" = true ]; then
			echo "📋 Summary:"
			echo "   - Total found: ${#broken_symlinks[@]}"
			echo "   - Removed: $removed_count"
			echo "   - Failed: $failed_count"
		fi
	else
		echo "ℹ️  No changes were made"
	fi

	# Return error code if any removals failed
	if [ $failed_count -gt 0 ]; then
		return 1
	fi

	return 0
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	find-broken-symlinks "$@"
fi
