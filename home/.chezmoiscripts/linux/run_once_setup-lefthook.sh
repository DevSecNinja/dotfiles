#!/bin/bash
# Install and setup lefthook git hooks
# This script ensures lefthook is available (via mise) and installs the
# git hooks defined in .lefthook.toml in the dotfiles repository.
# Note: This runs from the destination directory, so we need to find the source.

set -e

# Set MISE_YES=1 to auto-accept trust prompts during installation
# This prevents mise from hanging in non-interactive environments (Codespaces, CI)
export MISE_YES=1

echo "🔧 Setting up lefthook..."

# Get the Chezmoi source directory (where the dotfiles repo is)
# The source path is the parent of CHEZMOI_SOURCE_DIR/home
if [ -n "$CHEZMOI_SOURCE_DIR" ]; then
	DOTFILES_ROOT="$(dirname "$CHEZMOI_SOURCE_DIR")"
else
	# Fallback: try to get it from chezmoi command
	if command -v chezmoi >/dev/null 2>&1; then
		DOTFILES_ROOT="$(dirname "$(chezmoi source-path)")"
	else
		echo "⚠️  Cannot determine dotfiles repository location"
		echo "Skipping lefthook setup (run manually from dotfiles repo)"
		exit 0
	fi
fi

echo "📁 Dotfiles repository: $DOTFILES_ROOT"

# Check if we have the required files in the dotfiles repo
if [ ! -f "$DOTFILES_ROOT/.lefthook.toml" ] && [ ! -f "$DOTFILES_ROOT/lefthook.yml" ]; then
	echo "⚠️  No lefthook configuration found in $DOTFILES_ROOT"
	echo "Skipping lefthook setup"
	exit 0
fi

# Resolve a lefthook executable. Prefer mise-managed binaries so the
# version stays in sync with .mise.toml.
LEFTHOOK_CMD=""
if command -v lefthook >/dev/null 2>&1; then
	LEFTHOOK_CMD="lefthook"
	echo "✅ lefthook already installed ($(lefthook version 2>/dev/null || echo 'unknown'))"
elif command -v mise >/dev/null 2>&1; then
	echo "📦 Installing lefthook via mise..."
	# shellcheck disable=SC2015
	(cd "$DOTFILES_ROOT" && mise install lefthook >/dev/null 2>&1 || true)
	if mise which lefthook >/dev/null 2>&1; then
		LEFTHOOK_CMD="mise exec -- lefthook"
		echo "✅ lefthook installed via mise"
	fi
fi

if [ -z "$LEFTHOOK_CMD" ]; then
	echo "⚠️  Could not install lefthook automatically."
	echo "💡 Install mise (https://mise.jdx.dev/) and run: mise install"
	exit 0
fi

# Check if dotfiles repo is a git repository
if [ ! -d "$DOTFILES_ROOT/.git" ]; then
	echo "⚠️  Dotfiles directory is not a git repository"
	echo "Skipping git hooks installation"
	exit 0
fi

# Skip git hooks installation in CI environments
if [ -n "$CI" ] || [ -n "$GITHUB_ACTIONS" ]; then
	echo "ℹ️  Skipping git hooks installation in CI environment"
	exit 0
fi

# Install the git hooks in the dotfiles repository
echo "🔗 Installing git hooks in dotfiles repository..."
cd "$DOTFILES_ROOT" || exit 1

# Verify we're in a git repository before installing hooks
if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "⚠️  Cannot access git repository"
	echo "Skipping git hooks installation"
	exit 0
fi

# shellcheck disable=SC2086
$LEFTHOOK_CMD install

echo ""
echo "✅ Lefthook setup complete!"
echo "💡 Hooks will run automatically on git commit in your dotfiles repo"
echo "💡 To run manually: cd $DOTFILES_ROOT && lefthook run pre-commit --all-files"
