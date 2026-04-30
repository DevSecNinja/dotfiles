#!/bin/bash
# Install and setup lefthook git hooks
# This script ensures lefthook is available (via mise) and installs the
# git hooks defined in .lefthook.toml in the dotfiles repository.
# Note: This runs from the destination directory, so we need to find the source.

set -e

# Set MISE_YES=1 to auto-accept trust prompts during installation
# This prevents mise from hanging in non-interactive environments (Codespaces, CI)
export MISE_YES=1

# shellcheck source=home/dot_config/shell/functions/log.sh disable=SC1091
. "${CHEZMOI_SOURCE_DIR}/dot_config/shell/functions/log.sh"
# shellcheck disable=SC2034 # consumed by log.sh
LOG_TAG="setup-lefthook"

log_state "Setting up lefthook"

# Get the Chezmoi source directory (where the dotfiles repo is)
# The source path is the parent of CHEZMOI_SOURCE_DIR/home
if [ -n "$CHEZMOI_SOURCE_DIR" ]; then
	DOTFILES_ROOT="$(dirname "$CHEZMOI_SOURCE_DIR")"
else
	# Fallback: try to get it from chezmoi command
	if command -v chezmoi >/dev/null 2>&1; then
		DOTFILES_ROOT="$(dirname "$(chezmoi source-path)")"
	else
		log_warn "Cannot determine dotfiles repository location"
		log_hint "Skipping lefthook setup (run manually from dotfiles repo)"
		exit 0
	fi
fi

log_info "Dotfiles repository: $DOTFILES_ROOT"

PACKAGE_UTILS="$DOTFILES_ROOT/home/.chezmoihelpers/package-utils.sh"
if [ ! -f "$PACKAGE_UTILS" ]; then
	log_warn "Cannot find package utility helpers"
	log_hint "Skipping lefthook setup"
	exit 0
fi

# shellcheck source=home/.chezmoihelpers/package-utils.sh
source "$PACKAGE_UTILS"

if ! mise_required_for_current_install "$DOTFILES_ROOT/home/.chezmoidata/packages.yaml"; then
	log_info "skipping lefthook setup: mise not required for this install type"
	exit 0
fi

# Check if we have the required files in the dotfiles repo
if [ ! -f "$DOTFILES_ROOT/.lefthook.toml" ] && [ ! -f "$DOTFILES_ROOT/lefthook.yml" ]; then
	log_warn "No lefthook configuration found in $DOTFILES_ROOT"
	log_hint "Skipping lefthook setup"
	exit 0
fi

# Resolve a lefthook executable. Prefer mise-managed binaries so the
# version stays in sync with .mise.toml.
LEFTHOOK_PATH=""
if command -v lefthook >/dev/null 2>&1; then
	LEFTHOOK_PATH="$(command -v lefthook)"
	log_result "lefthook already installed ($(lefthook version 2>/dev/null || echo 'unknown'))"
elif command -v mise >/dev/null 2>&1; then
	log_step "Installing mise-managed tools"
	if ! (cd "$DOTFILES_ROOT" && mise install >/dev/null 2>&1); then
		log_warn "mise install failed"
	fi
	if mise which lefthook >/dev/null 2>&1; then
		LEFTHOOK_PATH="$(mise which lefthook)"
		log_result "lefthook installed via mise"
	fi
fi

if [ -z "$LEFTHOOK_PATH" ]; then
	log_warn "Could not install lefthook automatically."
	log_hint "Install mise (https://mise.jdx.dev/) and run: mise install"
	exit 0
fi

# Check if dotfiles repo is a git repository
if [ ! -d "$DOTFILES_ROOT/.git" ]; then
	log_warn "Dotfiles directory is not a git repository"
	log_hint "Skipping git hooks installation"
	exit 0
fi

# Skip git hooks installation in CI environments
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
	log_info "Skipping git hooks installation in CI environment"
	exit 0
fi

# Install the git hooks in the dotfiles repository
log_step "Installing git hooks in dotfiles repository"
cd "$DOTFILES_ROOT" || exit 1

# Verify we're in a git repository before installing hooks
if ! git rev-parse --git-dir >/dev/null 2>&1; then
	log_warn "Cannot access git repository"
	log_hint "Skipping git hooks installation"
	exit 0
fi

"$LEFTHOOK_PATH" install

log_result "Lefthook setup complete"
log_hint "Hooks will run automatically on git commit in your dotfiles repo"
log_hint "To run manually: cd $DOTFILES_ROOT && lefthook run pre-commit --all-files"
