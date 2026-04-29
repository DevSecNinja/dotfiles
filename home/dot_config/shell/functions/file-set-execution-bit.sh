#!/bin/bash
# file-set-execution-bit - Ensure executable permissions on shell scripts
#
# This function automatically sets executable permissions on shell scripts
# in the git repository and updates the git index accordingly.
# Processes both staged and unstaged files.
#
# Usage: file-set-execution-bit [--dry-run|-n] [--all|-a] [file...]
#   --dry-run, -n    Show what would be changed without making changes
#   --all, -a        Check all tracked shell scripts (or all files outside git)
#   file...          Check only the provided files
#
# Originally based on Stack Overflow solution by ixe013
# Retrieved 2026-01-16, License - CC BY-SA 4.0

file-set-execution-bit() {
	local dry_run=false
	local check_all=false
	local changes_made=false
	local explicit_files=()

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run | -n)
			dry_run=true
			shift
			;;
		--all | -a)
			check_all=true
			shift
			;;
		--)
			shift
			explicit_files+=("$@")
			break
			;;
		-h | --help)
			echo "Usage: file-set-execution-bit [--dry-run|-n] [--all|-a] [file...]"
			echo "Ensure executable permissions on shell scripts"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be changed without making changes"
			echo "  --all, -a        Check all tracked shell scripts (or all files outside git)"
			echo "  file...          Check only the provided files"
			echo "  -h, --help       Show this help message"
			return 0
			;;
		-*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		*)
			explicit_files+=("$1")
			shift
			;;
		esac
	done

	# Check if we're in a git repository (only needed for git mode)
	if [ "$check_all" = false ] && [ ${#explicit_files[@]} -eq 0 ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "❌ Not in a git repository"
		return 1
	fi

	echo "🔧 Checking executable permissions on shell scripts..."
	if [ "$dry_run" = true ]; then
		echo "🔍 Dry run mode: no changes will be made"
	fi

	# Get list of files
	local files
	if [ ${#explicit_files[@]} -gt 0 ]; then
		echo "📄 Checking provided files..."
		files=$(printf '%s\n' "${explicit_files[@]}" | sort -u)
	elif [ "$check_all" = true ]; then
		if git rev-parse --git-dir >/dev/null 2>&1; then
			echo "📁 Checking all git-tracked shell scripts..."
			files=$(git ls-files "*.sh" "*.bash" 2>/dev/null | sort)
		else
			echo "📁 Checking all files in current directory..."
			# Find all .sh and .bash files recursively
			files=$(find . -type f \( -name "*.sh" -o -name "*.bash" \) -not -path "./.git/*" 2>/dev/null | sed 's|^\./||' | sort)
		fi
	else
		echo "📝 Checking git-tracked files..."
		files=$(
			{
				git diff-index --cached --name-only HEAD 2>/dev/null || true
				git diff-index --name-only HEAD 2>/dev/null || true
				git ls-files --others --exclude-standard 2>/dev/null || true
			} | sort -u
		)
	fi

	if [ -z "$files" ]; then
		echo "ℹ️  No files found to check"
		return 0
	fi

	# Process each file
	while IFS= read -r filename; do
		# Skip empty lines
		[ -z "$filename" ] && continue

		# For --all mode, we already filtered to shell scripts
		# For explicit/default git mode, check if it's a shell script file
		if [ "$check_all" = true ] || [[ "$filename" =~ \.(sh|bash)$ ]]; then
			if [ -f "$filename" ]; then
				if [ ! -x "$filename" ]; then
					changes_made=true
					if [ "$dry_run" = true ]; then
						echo "🔍 Would make executable: $filename"
					else
						echo "🔧 Making executable: $filename"
						chmod +x "$filename"
						# Update git index if file is tracked and we're in a git repo
						if [ "$check_all" = false ] && git ls-files --error-unmatch "$filename" >/dev/null 2>&1; then
							git update-index --chmod=+x -- "$filename"
						elif [ "$check_all" = true ] && git rev-parse --git-dir >/dev/null 2>&1 && git ls-files --error-unmatch "$filename" >/dev/null 2>&1; then
							git update-index --chmod=+x -- "$filename"
						fi
					fi
				else
					echo "✅ Already executable: $filename"
				fi
			else
				echo "⚠️  File not found: $filename"
			fi
		fi
	done <<<"$files"

	# Final status
	if [ "$changes_made" = false ]; then
		echo "✅ All shell scripts already have correct permissions"
	elif [ "$dry_run" = true ]; then
		echo "🔍 Dry run completed - changes would be made above"
	else
		echo "✅ Execution permissions updated successfully"
	fi
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	file-set-execution-bit "$@"
fi
