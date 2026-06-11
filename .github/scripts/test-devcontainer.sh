#!/bin/bash
# Test devcontainer deployment including features, dotfiles, and postCreateCommand
# This script is designed to run inside a devcontainer built from .devcontainer/devcontainer.json

set -e

echo "🧪 Testing devcontainer deployment..."
echo ""

# Track failures
FAILURES=0

# Helper function to check command existence
check_command() {
	local cmd="$1"
	local description="$2"

	if command -v "${cmd}" >/dev/null 2>&1; then
		echo "  ✅ ${description}: ${cmd} is installed"
		return 0
	else
		echo "  ❌ ${description}: ${cmd} NOT found"
		FAILURES=$((FAILURES + 1))
		return 1
	fi
}

# Helper function to check file existence
check_file() {
	local file="$1"
	local description="$2"

	if [ -f "${file}" ]; then
		echo "  ✅ ${description}: ${file} exists"
		return 0
	else
		echo "  ❌ ${description}: ${file} NOT found"
		FAILURES=$((FAILURES + 1))
		return 1
	fi
}

# Helper function to check directory existence
check_directory() {
	local dir="$1"
	local description="$2"

	if [ -d "${dir}" ]; then
		echo "  ✅ ${description}: ${dir} exists"
		return 0
	else
		echo "  ❌ ${description}: ${dir} NOT found"
		FAILURES=$((FAILURES + 1))
		return 1
	fi
}

echo "🔧 Step 0: Verifying mise is on the image-baked PATH (no manual export)..."
echo ""
# postCreateCommand runs in a non-login, non-interactive shell with no profile
# sourcing. Simulate that to ensure the image ENV PATH (not a shell rc) exposes
# mise — this is the exact condition that previously failed with `mise: not found`.
if env -i PATH="$PATH" HOME="$HOME" sh -c 'command -v mise >/dev/null 2>&1'; then
	echo "  ✅ mise resolves via image-baked PATH"
else
	echo "  ❌ mise NOT on baked PATH (postCreateCommand would fail)"
	FAILURES=$((FAILURES + 1))
fi

echo "📦 Step 1: Verifying devcontainer features..."
echo ""

# Check Homebrew (installed by Chezmoi's run_once_before_05-install-homebrew.sh.tmpl in full mode)
# Initialize Homebrew PATH if it exists
if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
	eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
elif [ -f "/opt/homebrew/bin/brew" ]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -f "/usr/local/bin/brew" ]; then
	eval "$(/usr/local/bin/brew shellenv)"
fi
check_command "brew" "Homebrew"

# Check Git LFS (from ghcr.io/devcontainers/features/git-lfs)
check_command "git-lfs" "Git LFS"

# Check PowerShell (from ghcr.io/devcontainers/features/powershell)
if check_command "pwsh" "PowerShell"; then
	# Check if Pester module is installed (specified in devcontainer.json)
	echo "    Checking Pester module..."
	PESTER_VERSION=$(pwsh -NoProfile -Command "Get-Module -ListAvailable -Name Pester | Select-Object -First 1 -ExpandProperty Version" 2>/dev/null)
	if [ -n "${PESTER_VERSION}" ]; then
		echo "    ✅ Pester module installed: ${PESTER_VERSION}"
	else
		echo "    ❌ Pester module NOT installed"
		FAILURES=$((FAILURES + 1))
	fi
fi

# Check Python (from ghcr.io/devcontainers/features/python)
check_command "python3" "Python"
# NOTE: Debian doesn't symlink python to python3 by default, so we only check python3
# check_command "python" "Python"

# Check GitHub CLI (from ghcr.io/devcontainers/features/github-cli)
check_command "gh" "GitHub CLI"

echo ""
echo "🏠 Step 2: Verifying dotfiles installation (postCreateCommand)..."
echo ""

# Ensure PATH includes local package-manager bins for chezmoi
export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}"

# Check if chezmoi was installed by postCreateCommand
if check_command "chezmoi" "Chezmoi"; then
	# Display chezmoi version
	CHEZMOI_VERSION=$(chezmoi --version 2>/dev/null | head -1 || echo "unknown")
	echo "    Version: ${CHEZMOI_VERSION}"

	# Check if dotfiles were applied
	echo ""
	echo "  Checking applied dotfiles..."

	# Essential dotfiles that should exist
	check_file "${HOME}/.vimrc" "Vim configuration"
	check_file "${HOME}/.tmux.conf" "Tmux configuration"
	check_file "${HOME}/.config/fish/config.fish" "Fish shell configuration"
	check_file "${HOME}/.config/git/config" "Git configuration"

	# Check Fish shell directories
	check_directory "${HOME}/.config/fish/conf.d" "Fish conf.d directory"
	check_directory "${HOME}/.config/fish/functions" "Fish functions directory"
fi

echo ""
echo "🐚 Step 3: Verifying Fish shell configuration..."
echo ""

# Check if Fish shell is installed
if check_command "fish" "Fish shell"; then
	# Test Fish shell loads without errors
	echo "  Testing Fish shell syntax..."
	if fish -n "${HOME}/.config/fish/config.fish" 2>/dev/null; then
		echo "  ✅ Fish configuration syntax is valid"
	else
		echo "  ❌ Fish configuration has syntax errors"
		FAILURES=$((FAILURES + 1))
	fi

	# Test Fish shell loads successfully
	echo "  Testing Fish shell initialization..."
	if fish -c "exit" 2>/dev/null; then
		echo "  ✅ Fish shell initializes successfully"
	else
		echo "  ❌ Fish shell initialization failed"
		FAILURES=$((FAILURES + 1))
	fi
fi

echo ""
echo "⚙️  Step 4: Verifying VSCode customizations..."
echo ""

# Check if VSCode extensions would be installed (we can't verify running extensions in CLI)
echo "  Expected VSCode extensions (from devcontainer.json):"
echo "    - GitHub.copilot"
echo "    - GitHub.copilot-chat"
echo "    - pspester.pester-test"
echo "  ℹ️  Note: Extensions are installed by VSCode, not verifiable in CLI test"

# Check terminal default profile setting
echo ""
echo "  Expected VSCode settings:"
echo "    - editor.formatOnSave: true"
echo "    - files.eol: newline"
echo "    - terminal.integrated.defaultProfile.linux: fish"
echo "  ℹ️  Note: Settings are applied by VSCode, not verifiable in CLI test"

echo ""
echo "📊 Step 5: Display Chezmoi status..."
echo ""

if command -v chezmoi >/dev/null 2>&1; then
	echo "  Managed files:"
	chezmoi managed 2>/dev/null | head -20 || echo "    (unable to list managed files)"

	echo ""
	echo "  Chezmoi data:"
	chezmoi data 2>/dev/null | head -30 || echo "    (unable to display data)"
fi

echo ""
echo "═══════════════════════════════════════════════════════"

# Report final results
if [ "${FAILURES}" -eq 0 ]; then
	echo "✅ DEVCONTAINER TEST PASSED!"
	echo "   All features installed, dotfiles applied, and configurations valid"
	exit 0
else
	echo "❌ DEVCONTAINER TEST FAILED!"
	echo "   ${FAILURES} check(s) failed"
	exit 1
fi
