#!/bin/bash

git-update-forked-repo() {
	if [ "$#" -ne 1 ]; then
		echo "Usage: git-update-forked-repo <upstream_remote_name>"
		return 1
	fi

	local inside_git_repo
	inside_git_repo="$(git rev-parse --is-inside-work-tree 2>/dev/null)"

	if [ ! "$inside_git_repo" ]; then
		echo "Not in a Git repo. Function can only be ran from a Git repository."
		return 1
	fi

	local upstream_remote_name="$1"
	local current_branch
	current_branch=$(git symbolic-ref --short HEAD)

	# Check if the upstream remote exists
	if ! git remote get-url "$upstream_remote_name" >/dev/null 2>&1; then
		echo "Error: Upstream remote '${upstream_remote_name}' not found."
		echo "Please add the upstream remote using 'git remote add <upstream_remote_name> <upstream_url>'."
		return 1
	fi

	# Fetch the latest changes from the upstream remote for the current branch only
	git fetch "$upstream_remote_name" "${current_branch}"

	# Show information and prompt for confirmation
	echo "Current branch: ${current_branch}"
	echo "Upstream remote: ${upstream_remote_name}"
	echo "Merge branch: ${upstream_remote_name}/${current_branch}"
	echo "Are you sure you want to merge? [y/N]"
	read -r confirm
	if [[ ! "${confirm}" =~ ^[Yy] ]]; then
		echo "Merge cancelled."
		return 1
	fi

	# Merge the current branch on top of the upstream remote branch
	git merge "${upstream_remote_name}/${current_branch}"

	echo "Confirm merge was successful. Push to ${current_branch}? [y/N]"
	read -r confirm
	if [[ ! "${confirm}" =~ ^[Yy] ]]; then
		echo "Push cancelled."
		return 1
	fi

	# Force push branch
	git push origin "${current_branch}"
}
