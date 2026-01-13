#!/bin/bash
# Validate Fish shell configuration files
# Checks all .fish files for syntax errors

set -e

echo "🐠 Validating Fish configuration files..."

# Get the source directory (current directory if not specified)
SOURCE_DIR="${1:-.}"

# Check if Fish is installed
if ! command -v fish >/dev/null 2>&1; then
    echo "📦 Fish not found, installing..."
    
    # Install Fish based on the OS
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update -qq
        sudo apt-get install -y fish
    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y fish
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -S --noconfirm fish
    elif command -v brew >/dev/null 2>&1; then
        brew install fish
    else
        echo "❌ Unable to install Fish automatically"
        exit 1
    fi
fi

echo "✅ Fish $(fish --version) is available"
echo ""

# Find and validate all Fish files
TEMP_FILE="$(mktemp)"
trap "rm -f '${TEMP_FILE}'" EXIT

find "${SOURCE_DIR}" -name "*.fish" -type f | sort > "${TEMP_FILE}"

if [ ! -s "${TEMP_FILE}" ]; then
    echo "No Fish files found"
    exit 0
fi

FISH_COUNT=0
ERROR_COUNT=0

while IFS= read -r fish_file; do
    FISH_COUNT=$((FISH_COUNT + 1))
    echo "  Validating: ${fish_file}"
    
    if fish -n "${fish_file}" 2>&1; then
        echo "    ✅ OK"
    else
        echo "    ❌ Syntax error"
        ERROR_COUNT=$((ERROR_COUNT + 1))
    fi
done < "${TEMP_FILE}"

echo ""
echo "📊 Checked ${FISH_COUNT} Fish file(s)"

if [ "${ERROR_COUNT}" -gt 0 ]; then
    echo "❌ Found ${ERROR_COUNT} file(s) with syntax errors"
    exit 1
fi

echo "✅ All Fish configurations are valid!"
