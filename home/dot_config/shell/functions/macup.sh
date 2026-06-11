#!/bin/bash
# macup - Update a macOS machine end to end
#
# Combines three update steps into a single command:
#   1. brewup         - update Homebrew and all installed formulae/casks
#   2. mas upgrade    - update Mac App Store apps (only if `mas` is installed)
#   3. softwareupdate - apply Apple's system/software updates
#
# By default macup lists the available Apple updates and, when something is
# available, prompts before installing only the *recommended* updates. It never
# restarts the machine on its own; pass --restart to allow an automatic restart
# when an update requires one (e.g. a macOS release).
#
# Usage: macup [--dry-run|-n] [--all|-a] [--restart|-R] [--yes|-y] [--help|-h]
#   --dry-run, -n    Show what would be updated without making changes
#   --all, -a        Install all available updates instead of recommended only
#   --restart, -R    Automatically restart if an update requires it
#   --yes, -y        Skip the confirmation prompt (non-interactive)
#   --help, -h       Show this help message
#
# Examples:
#   macup                    # brewup, then list/prompt for Apple updates
#   macup --dry-run          # preview both steps without changing anything
#   macup --yes              # run unattended, install recommended updates
#   macup --all --restart    # install everything and restart if required
#
# Notes:
#   - Installing Apple updates and Mac App Store apps requires administrator
#     privileges. macup prompts for your sudo password at most once per run and
#     reuses the cached credentials for the remaining steps (and reuses any
#     prompt brewup already triggered for a cask such as Edge).
#   - The Mac App Store step is skipped when `mas` is not installed
#     (install it with `brew install mas`).
#   - This is the macOS counterpart of `brewup` (Linux/macOS) and `winup`
#     (Windows).

macup() {
	# Initialize variables
	local dry_run=false
	local install_all=false
	local auto_restart=false
	local assume_yes=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--dry-run | -n)
			dry_run=true
			shift
			;;
		--all | -a)
			install_all=true
			shift
			;;
		--restart | -R)
			auto_restart=true
			shift
			;;
		--yes | -y)
			assume_yes=true
			shift
			;;
		-h | --help)
			echo "Usage: macup [--dry-run|-n] [--all|-a] [--restart|-R] [--yes|-y]"
			echo "Update a macOS machine: Homebrew (brewup) + Apple software updates"
			echo ""
			echo "Options:"
			echo "  --dry-run, -n    Show what would be updated without making changes"
			echo "  --all, -a        Install all available updates instead of recommended only"
			echo "  --restart, -R    Automatically restart if an update requires it"
			echo "  --yes, -y        Skip the confirmation prompt (non-interactive)"
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

	# macup is macOS-only: softwareupdate ships with macOS.
	if ! command -v softwareupdate >/dev/null 2>&1; then
		echo "❌ 'softwareupdate' not found; macup only works on macOS"
		return 1
	fi

	# Prompt for the sudo password at most once per run. sudo caches the
	# credentials, so any later `sudo ...` call within the cache window won't
	# prompt again. If an earlier step (e.g. brewup upgrading a cask like Edge)
	# already triggered sudo, this becomes a no-op. Returns non-zero when
	# credentials can't be obtained (e.g. a non-interactive shell).
	local sudo_primed=false
	_macup_prime_sudo() {
		[[ "$sudo_primed" == "true" ]] && return 0
		if sudo -v; then
			sudo_primed=true
			return 0
		fi
		return 1
	}

	# Make sure the brewup function is available. When this file is sourced by
	# bash/zsh the sibling brewup.sh is sourced too, but the Fish wrapper runs
	# this script standalone via `bash macup.sh`, so source it on demand.
	if ! type brewup >/dev/null 2>&1; then
		local script_dir
		script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		if [ -f "$script_dir/brewup.sh" ]; then
			# shellcheck source=/dev/null
			. "$script_dir/brewup.sh"
		fi
	fi

	# Step 1: Homebrew.
	echo "🍎 Step 1/3: Homebrew"
	if type brewup >/dev/null 2>&1; then
		local -a brew_args=()
		[[ "$dry_run" == "true" ]] && brew_args+=("--dry-run")
		[[ "$assume_yes" == "true" ]] && brew_args+=("--greedy")
		brewup "${brew_args[@]}"
	else
		echo "⚠️  brewup is not available; skipping Homebrew step"
	fi

	# Step 2: Mac App Store apps via `mas` (optional).
	echo
	echo "🍎 Step 2/3: Mac App Store"
	if command -v mas >/dev/null 2>&1; then
		local mas_outdated
		mas_outdated=$(mas outdated 2>/dev/null)
		if [ -z "$mas_outdated" ]; then
			echo "✅ All Mac App Store apps are up to date!"
		else
			echo "⚠️ Outdated Mac App Store apps:"
			echo "$mas_outdated" | awk '{ print "   - " $0 }'
			if [[ "$dry_run" == "true" ]]; then
				echo "⬆️  Would upgrade them with: sudo mas upgrade"
			else
				echo "⬆️  Upgrading Mac App Store apps..."
				if _macup_prime_sudo; then
					if ! sudo mas upgrade; then
						echo "⚠️  Some Mac App Store apps may have failed to upgrade"
					fi
				else
					echo "ℹ️  Could not obtain sudo privileges; skipping Mac App Store upgrade."
				fi
			fi
		fi
	else
		echo "ℹ️  'mas' not installed; skipping Mac App Store step (brew install mas)"
	fi

	echo
	echo "🍎 Step 3/3: Apple software updates"

	# List available Apple updates. softwareupdate prints its findings on stderr,
	# so capture both streams.
	echo "🔍 Checking for available updates..."
	local su_list
	su_list=$(softwareupdate -l 2>&1)

	# Available updates are listed as "* Label: <name>" lines.
	local available
	available=$(echo "$su_list" | grep -E '^[[:space:]]*\*[[:space:]]*Label:' | sed -E 's/^[[:space:]]*\*[[:space:]]*Label:[[:space:]]*//')

	if [ -z "$available" ]; then
		echo "✅ No Apple software updates available!"
		echo
		echo "🎉 macup complete!"
		return 0
	fi

	echo "⚠️ Apple updates available:"
	echo "$available" | awk '{ print "   - " $0 }'

	# Build the install command preview.
	local scope_flag="-r"
	local scope_label="recommended"
	if [[ "$install_all" == "true" ]]; then
		scope_flag="-a"
		scope_label="all"
	fi

	local restart_note=""
	[[ "$auto_restart" == "true" ]] && restart_note=" -R"

	if [[ "$dry_run" == "true" ]]; then
		echo
		echo "🔍 DRY RUN MODE - Showing what would be done:"
		echo "⬆️  Would install $scope_label updates with: sudo softwareupdate -i $scope_flag$restart_note"
		if [[ "$auto_restart" != "true" ]]; then
			echo "ℹ️  Updates that require a restart would NOT trigger one (no --restart)."
		fi
		echo
		echo "To actually perform these actions, run: macup"
		return 0
	fi

	# Confirm before installing unless --yes was given.
	local proceed=false
	if [[ "$assume_yes" == "true" ]]; then
		proceed=true
	elif [ -t 0 ]; then
		local reply
		read -r -p "Install $scope_label Apple updates now? [y/N] " reply
		[[ "$reply" =~ ^[Yy] ]] && proceed=true
	else
		echo "ℹ️  Non-interactive shell; skipping. Use 'macup --yes' to install."
	fi

	if [[ "$proceed" != "true" ]]; then
		echo "⏭️  Skipped Apple software updates."
		echo
		echo "🎉 macup complete!"
		return 0
	fi

	echo "⬆️  Installing $scope_label Apple updates..."
	local -a su_args=("-i" "$scope_flag")
	[[ "$auto_restart" == "true" ]] && su_args+=("-R")

	if ! _macup_prime_sudo; then
		echo "❌ Could not obtain sudo privileges to install Apple updates"
		return 1
	fi

	if ! sudo softwareupdate "${su_args[@]}"; then
		echo "❌ Failed to install Apple software updates"
		return 1
	fi

	echo "✅ Apple software updates complete!"
	echo
	echo "🎉 macup complete!"
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	macup "$@"
fi
