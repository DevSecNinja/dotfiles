#!/bin/bash

git-release() {
	local PREV_TAG
	PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null)
	if [ -z "$PREV_TAG" ]; then
		PREV_TAG="v0.0.0"
		echo "No previous tags found. Starting at $PREV_TAG"
	else
		echo "Previous release: $PREV_TAG"
	fi

	# Show help if no arguments
	if [[ $# -eq 0 ]]; then
		echo "Usage: git-release <major|minor|patch> [prerelease] [message]"
		echo "       git-release <prerelease> [message]"
		return 0
	fi

	# Check if we're on main branch
	local CURRENT_BRANCH
	CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
	if [[ "$CURRENT_BRANCH" != "main" ]]; then
		echo "Error: You must be on the 'main' branch to create a release (currently on '$CURRENT_BRANCH')"
		return 1
	fi

	# Check if main is up-to-date with origin
	echo "Checking if main is up-to-date with origin..."
	git fetch origin main --quiet
	local LOCAL_HASH REMOTE_HASH
	LOCAL_HASH=$(git rev-parse main)
	REMOTE_HASH=$(git rev-parse origin/main)
	if [[ "$LOCAL_HASH" != "$REMOTE_HASH" ]]; then
		echo "Error: Your main branch is not up-to-date with origin/main"
		echo "Please pull the latest changes before creating a release."
		return 1
	fi

	# Split tag into numeric and prerelease parts
	local NUM_PART PRERELEASE
	NUM_PART=${PREV_TAG#v}
	if [[ "$NUM_PART" == *-* ]]; then
		PRERELEASE=${NUM_PART#*-}
		NUM_PART=${NUM_PART%%-*}
	else
		PRERELEASE=""
	fi

	IFS='.' read -r MAJOR MINOR PATCH <<<"$NUM_PART"

	if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$MINOR" =~ ^[0-9]+$ && "$PATCH" =~ ^[0-9]+$ ]]; then
		echo "Error: Could not parse previous tag '$PREV_TAG'"
		return 1
	fi

	local BUMP_TYPE
	local NEW_PRERELEASE
	local MSG

	if [[ "$1" == "major" || "$1" == "minor" || "$1" == "patch" ]]; then
		BUMP_TYPE="$1"
		NEW_PRERELEASE="$2"
		MSG="$3"
	else
		BUMP_TYPE=""
		NEW_PRERELEASE="$1"
		MSG="$2"
	fi

	# Only increment numeric version if not a prerelease
	if [[ -n "$BUMP_TYPE" ]]; then
		case "$BUMP_TYPE" in
		major)
			((MAJOR++))
			MINOR=0
			PATCH=0
			;;
		minor)
			((MINOR++))
			PATCH=0
			;;
		patch)
			# Only increment patch if previous tag had no prerelease
			if [[ -z "$PRERELEASE" ]]; then
				((PATCH++))
			fi
			;;
		esac
	fi

	local NEW_TAG="v$MAJOR.$MINOR.$PATCH"
	[ -n "$NEW_PRERELEASE" ] && NEW_TAG="$NEW_TAG-$NEW_PRERELEASE"

	MSG="${MSG:-Release $NEW_TAG}"

	if git rev-parse "$NEW_TAG" >/dev/null 2>&1 || git ls-remote --tags origin "$NEW_TAG" | grep -q "$NEW_TAG"; then
		echo "Error: Tag '$NEW_TAG' already exists!"
		return 1
	fi

	echo -n "Create and push tag '$NEW_TAG'? [y/N]: "
	read -r CONFIRM
	if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
		echo "Aborted."
		return 1
	fi

	git tag -a "$NEW_TAG" -m "$MSG"
	git push origin "$NEW_TAG"
	echo "Tag $NEW_TAG created and pushed!"
}
