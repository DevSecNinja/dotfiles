#!/bin/bash
# git-undo - Undo the last Git commit while keeping changes staged
#
# Resets the current branch to the previous commit using --soft flag,
# which keeps all changes from the undone commit staged and ready to
# be recommitted. This is useful when you need to modify a commit
# message or add more changes to the last commit.
#
# Usage: git-undo [OPTIONS]
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   git-undo                # Undo last commit, keep changes staged
#   git-undo --verbose      # Undo with verbose output
#
# Notes:
#   - Changes from the undone commit remain staged
#   - Use with caution if the commit has been pushed to a remote
#   - To undo and unstage changes, use: git reset HEAD^
#   - To undo and discard changes, use: git reset --hard HEAD^

git-undo() {
	# Initialize variables
	local verbose=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--verbose | -v)
			verbose=true
			shift
			;;
		-h | --help)
			echo "Usage: git-undo [OPTIONS]"
			echo "Undo the last Git commit while keeping changes staged"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Examples:"
			echo "  git-undo                # Undo last commit, keep changes staged"
			echo "  git-undo --verbose      # Undo with verbose output"
			return 0
			;;
		*)
			echo "Unknown option: $1"
			echo "Use 'git-undo --help' for usage information"
			return 1
			;;
		esac
	done

	# Check if we're in a Git repository
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "Error: Not in a Git repository"
		return 1
	fi

	# Check if there are any commits to undo
	if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
		echo "Error: No commits to undo"
		return 1
	fi

	# Undo last commit
	if [[ "$verbose" == true ]]; then
		echo "Undoing last commit (keeping changes staged)..."
	fi

	if git reset --soft HEAD^; then
		if [[ "$verbose" == true ]]; then
			echo "✓ Last commit undone successfully"
			echo ""
			git status --short
		else
			echo "Last commit undone (changes still staged)"
		fi
		return 0
	else
		echo "Error: Failed to undo last commit"
		return 1
	fi
}
