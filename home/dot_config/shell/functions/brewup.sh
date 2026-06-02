#!/bin/bash
# brewup - Update Homebrew and all installed packages
#
# This function updates Homebrew itself, upgrades all installed packages,
# and cleans up old versions to free up space.

brewup() {
	# Initialize variables
	local dry_run=false
	local assume_yes=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run | -n)
			dry_run=true
			shift
			;;
		--greedy | -g)
			assume_yes=true
			shift
			;;
		-h | --help)
			echo "Usage: brewup [--dry-run|-n] [--greedy|-g]"
			echo "Update Homebrew and all installed packages"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be updated without making changes"
			echo "  --greedy, -g     Also upgrade auto-updating casks without prompting"
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

	# Check if brew is installed
	if ! command -v brew >/dev/null 2>&1; then
		echo "❌ Homebrew is not installed or not in PATH"
		return 1
	fi

	# Detect normally-outdated packages (formulae + casks Homebrew tracks).
	outdated=$(brew outdated 2>/dev/null)

	# Detect casks that have updates available but are excluded from the normal
	# upgrade because they declare `auto_updates true` (e.g. copilot-cli).
	# These are the casks listed by --greedy-auto-updates but not by a plain
	# `brew outdated --cask`. We surface them separately so the user can opt in.
	local greedy_casks
	greedy_casks=$(comm -13 \
		<(brew outdated --cask 2>/dev/null | sort -u) \
		<(brew outdated --cask --greedy-auto-updates 2>/dev/null | sort -u))

	if [ -z "$outdated" ] && [ -z "$greedy_casks" ]; then
		echo "✅ All packages are up to date!"
		return 0
	fi

	if [ -n "$outdated" ]; then
		echo "⚠️ Outdated packages that will be updated:"
		echo "$outdated"
	fi

	if [[ "$dry_run" == "true" ]]; then
		echo "🔍 DRY RUN MODE - Showing what would be done:"
		echo
		if [ -n "$outdated" ]; then
			echo "📦 Would update package lists with: brew update"
			echo "⬆️  Would upgrade packages with: brew upgrade"
			echo "🖥️  Would upgrade casks with: brew upgrade --cask"
			echo "🧹 Would clean up with: brew cleanup"
		fi
		if [ -n "$greedy_casks" ]; then
			echo
			echo "⚠️ The following packages have updates but are excluded because"
			echo "    they have auto-updating capabilities:"
			echo "$greedy_casks"
			if [[ "$assume_yes" == "true" ]]; then
				echo "Would upgrade them with: brew upgrade --cask --greedy-auto-updates"
			else
				echo "Run 'brewup' and confirm the prompt (or 'brewup --greedy') to update them."
			fi
		fi
		echo
		echo "To actually perform these actions, run: brewup"
		return 0
	fi

	# Only run the normal update workflow when something normal is outdated.
	if [ -n "$outdated" ]; then
		echo "🍺 Updating Homebrew..."

		# Update Homebrew itself and the formulae
		echo "📦 Updating package lists..."
		if ! brew update; then
			echo "❌ Failed to update Homebrew"
			return 1
		fi

		# Upgrade all installed packages
		echo "⬆️  Upgrading installed packages..."
		if ! brew upgrade; then
			echo "❌ Failed to upgrade packages"
			return 1
		fi

		# Upgrade casks (GUI applications)
		echo "🖥️  Upgrading casks..."
		if ! brew upgrade --cask; then
			echo "⚠️  Some casks may have failed to upgrade (this is often normal)"
		fi

		# Clean up old versions and cache
		echo "🧹 Cleaning up old versions..."
		if ! brew cleanup; then
			echo "⚠️  Cleanup encountered some issues (this is often normal)"
		fi
	fi

	# Handle auto-updating casks that were excluded from the normal upgrade.
	if [ -n "$greedy_casks" ]; then
		echo
		echo "⚠️ The following packages have updates but are excluded because"
		echo "    they have auto-updating capabilities:"
		echo "$greedy_casks"

		local proceed=false
		if [[ "$assume_yes" == "true" ]]; then
			proceed=true
		elif [ -t 0 ]; then
			local reply
			read -r -p "Want to proceed and upgrade them anyway? [y/N] " reply
			[[ "$reply" =~ ^[Yy] ]] && proceed=true
		else
			echo "ℹ️  Non-interactive shell; skipping. Use 'brewup --greedy' to include them."
		fi

		if [[ "$proceed" == "true" ]]; then
			echo "🖥️  Upgrading auto-updating casks..."
			if ! brew upgrade --cask --greedy-auto-updates; then
				echo "⚠️  Some casks may have failed to upgrade (this is often normal)"
			fi
		fi
	fi

	# Show what's outdated (should be empty now)
	outdated=$(brew outdated 2>/dev/null)
	if [ -n "$outdated" ]; then
		echo "⚠️  Still outdated:"
		echo "$outdated"
	else
		echo "✅ All packages are up to date!"
	fi

	# Show summary
	echo
	echo "📊 Homebrew summary:"
	brew --version
	echo "Installed packages: $(brew list --formula | wc -l | tr -d ' ')"
	echo "Installed casks: $(brew list --cask | wc -l | tr -d ' ')"

	echo "🎉 Homebrew update complete!"
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	brewup "$@"
fi
