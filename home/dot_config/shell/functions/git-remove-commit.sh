#!/bin/bash

# Remove a specific commit from the current branch
git-remove-commit() {
	echo "This script is still in testing phase! Use with caution."
	echo ""

	if [ -z "$1" ] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
		echo "❌ Error: Please provide a commit hash"
		echo "Usage: git-remove-commit <commit-hash>"
		return 1
	fi

	local commit_hash="$1"

	# Check if we're in a git repo
	if ! git rev-parse --git-dir >/dev/null 2>&1; then
		echo "❌ Error: Not in a git repository"
		return 1
	fi

	# Verify the commit exists
	if ! git cat-file -e "$commit_hash" 2>/dev/null; then
		echo "❌ Error: Commit '$commit_hash' not found"
		return 1
	fi

	# Get current branch
	local current_branch
	current_branch=$(git branch --show-current)
	echo "📍 Current branch: $current_branch"
	echo ""

	# Show the commit details
	echo "📋 Commit to remove:"
	git show "$commit_hash" --stat --pretty=format:"%h - %s%n%an, %ar%n" | head -20
	echo ""

	# Check if there are uncommitted changes
	if ! git diff-index --quiet HEAD --; then
		echo "⚠️  Warning: You have uncommitted changes"
		git status --short
		echo ""
		read -r -q "REPLY?Continue anyway? (y/n) "
		echo ""
		if [[ ! $REPLY =~ ^[Yy]$ ]]; then
			echo "❌ Aborted"
			return 1
		fi
	fi

	# Determine removal method
	local head_hash
	head_hash=$(git rev-parse HEAD)
	if [ "$commit_hash" = "$head_hash" ] || git merge-base --is-ancestor "$commit_hash" HEAD 2>/dev/null && [ "$(git rev-parse HEAD)" = "$(git rev-parse "$commit_hash")" ]; then
		# Commit is HEAD - use reset
		echo "🔧 This is the most recent commit, will use 'git reset --hard HEAD~1'"
	else
		# Commit is in history - use rebase
		echo "🔧 This commit is in history, will use interactive rebase"
		echo "⚠️  Note: This will rewrite history and may cause conflicts"
	fi
	echo ""

	# Final confirmation
	read -r -q "REPLY?⚠️  Remove this commit? (y/n) "
	echo ""
	if [[ ! $REPLY =~ ^[Yy]$ ]]; then
		echo "❌ Aborted"
		return 1
	fi

	# Perform the removal
	if [ "$commit_hash" = "$head_hash" ]; then
		git reset --hard HEAD~1
		echo "✅ Commit removed successfully"
	else
		# Use rebase to remove the commit from history
		if git rebase --onto "${commit_hash}^" "$commit_hash"; then
			echo "✅ Commit removed successfully"
		else
			echo "❌ Rebase failed. You may need to resolve conflicts."
			return 1
		fi
	fi

	# Ask about force pushing
	if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
		echo ""
		read -r -q "REPLY?Force push to remote? (y/n) "
		echo ""
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			local remote
			remote=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' | cut -d'/' -f1)
			git push "$remote" "$current_branch" --force
			echo "✅ Force pushed to $remote/$current_branch"
		else
			echo "ℹ️  Remember to force push later: git push origin $current_branch --force"
		fi
	fi
}
