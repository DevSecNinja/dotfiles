#!/bin/bash
# Install and setup pre-commit hooks
# This script installs pre-commit and sets up the git hooks
# Note: This runs from the destination directory, so we need to find the source

set -e

echo "🔧 Setting up pre-commit..."

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
		echo "Skipping pre-commit setup (run manually from dotfiles repo)"
		exit 0
	fi
fi

echo "📁 Dotfiles repository: $DOTFILES_ROOT"

# Check if we have the required files in the dotfiles repo
if [ ! -f "$DOTFILES_ROOT/.pre-commit-config.yaml" ]; then
	echo "⚠️  .pre-commit-config.yaml not found in $DOTFILES_ROOT"
	echo "Skipping pre-commit setup"
	exit 0
fi

# Check if pre-commit is already installed
if command -v pre-commit >/dev/null 2>&1; then
	echo "✅ pre-commit is already installed ($(pre-commit --version))"
else
	echo "📦 Installing pre-commit..."

	# Install in a dedicated venv
	VENV_DIR="$HOME/.local/venvs/pre-commit"

	if [ ! -d "$VENV_DIR" ]; then
		echo "Creating venv for pre-commit..."
		python3 -m venv "$VENV_DIR"
	fi

	echo "Installing pre-commit in venv..."
	"$VENV_DIR/bin/pip" install --upgrade pip >/dev/null 2>&1

	if [ -f "$DOTFILES_ROOT/requirements.txt" ]; then
		"$VENV_DIR/bin/pip" install -r "$DOTFILES_ROOT/requirements.txt" >/dev/null 2>&1
	else
		"$VENV_DIR/bin/pip" install pre-commit >/dev/null 2>&1
	fi

	# Create symlink to make pre-commit available
	mkdir -p "$HOME/.local/bin"
	ln -sf "$VENV_DIR/bin/pre-commit" "$HOME/.local/bin/pre-commit"
	export PATH="$HOME/.local/bin:$PATH"

	echo "✅ pre-commit installed successfully"
fi

# Check if dotfiles repo is a git repository
if [ ! -d "$DOTFILES_ROOT/.git" ]; then
	echo "⚠️  Dotfiles directory is not a git repository"
	echo "Skipping git hooks installation"
	exit 0
fi

# Install the git hooks in the dotfiles repository
echo "🔗 Installing git hooks in dotfiles repository..."
cd "$DOTFILES_ROOT"
pre-commit install

echo ""
echo "✅ Pre-commit setup complete!"
echo "💡 Hooks will run automatically on git commit in your dotfiles repo"
echo "💡 To run manually: cd $DOTFILES_ROOT && pre-commit run --all-files"
