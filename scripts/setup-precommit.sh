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
    
    # Check for requirements.txt
    if [ -f requirements.txt ]; then
        # Try pipx first (best practice for tools)
        if command -v pipx >/dev/null 2>&1; then
            echo "Using pipx to install pre-commit..."
            pipx install pre-commit
        # Then try pip3
        elif command -v pip3 >/dev/null 2>&1; then
            echo "Using pip3 to install from requirements.txt..."
            # In containers/CI: install directly
            # Locally: use --user flag
            if [ -f /.dockerenv ] || [ "${CI}" = "true" ]; then
                pip3 install -r requirements.txt
            else
                pip3 install --user -r requirements.txt
            fi
        elif command -v pip >/dev/null 2>&1; then
            echo "Using pip to install from requirements.txt..."
            if [ -f /.dockerenv ] || [ "${CI}" = "true" ]; then
                pip install -r requirements.txt
            else
                pip install --user -r requirements.txt
            fi
        else
            echo "❌ pip not found. Please install Python and pip first."
            exit 1
        fi
    else
        echo "⚠️  requirements.txt not found, installing pre-commit directly..."
        if command -v pip3 >/dev/null 2>&1; then
            pip3 install --user pre-commit
        else
            pip install --user pre-commit
        fi
    fi
    
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
