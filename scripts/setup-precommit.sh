#!/bin/bash
# Install and setup pre-commit hooks
# This script installs pre-commit and sets up the git hooks

set -e

echo "🔧 Setting up pre-commit..."

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
	"$VENV_DIR/bin/pip" install --upgrade pip

	if [ -f requirements.txt ]; then
		"$VENV_DIR/bin/pip" install -r requirements.txt
	else
		"$VENV_DIR/bin/pip" install pre-commit
	fi

	# Create symlink to make pre-commit available
	mkdir -p "$HOME/.local/bin"
	ln -sf "$VENV_DIR/bin/pre-commit" "$HOME/.local/bin/pre-commit"
	export PATH="$HOME/.local/bin:$PATH"

	# Add to PATH if needed
	export PATH="$HOME/.local/bin:$PATH"

	echo "✅ pre-commit installed successfully"
fi

# Install the git hooks
if [ -f .pre-commit-config.yaml ]; then
	echo "🔗 Installing git hooks..."
	pre-commit install
	echo "✅ Git hooks installed"

	# Optionally run on all files
	if [ "${1}" = "--all" ]; then
		echo "🧹 Running pre-commit on all files..."
		pre-commit run --all-files
	fi
else
	echo "⚠️  .pre-commit-config.yaml not found in current directory"
	exit 1
fi

echo ""
echo "✅ Pre-commit setup complete!"
echo "💡 Hooks will now run automatically on git commit"
echo "💡 To run manually: pre-commit run --all-files"
