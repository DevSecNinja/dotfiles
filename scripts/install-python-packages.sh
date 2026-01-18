#!/bin/bash
# Install Python packages from packages.yaml
# This script extracts Python pip packages from .chezmoidata/packages.yaml and installs them
# Used by CI and development environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGES_FILE="${REPO_ROOT}/home/.chezmoidata/packages.yaml"

echo "📦 Installing Python packages from packages.yaml..."

# Check if packages.yaml exists
if [ ! -f "$PACKAGES_FILE" ]; then
    echo "❌ packages.yaml not found at $PACKAGES_FILE"
    exit 1
fi

# Detect OS
if [ "$(uname)" = "Darwin" ]; then
    OS="darwin"
elif [ "$(uname)" = "Linux" ]; then
    OS="linux"
else
    echo "❌ Unsupported OS: $(uname)"
    exit 1
fi

# Check if yq is available for YAML parsing
if command -v yq >/dev/null 2>&1; then
    # Try to determine which yq version we have
    if yq --version 2>&1 | grep -q 'mikefarah\|version 4'; then
        # Go yq (mikefarah/yq) - modern version
        echo "Using yq to parse packages.yaml..."
        
        # Get light mode packages
        LIGHT_PACKAGES=$(yq eval ".packages.${OS}.pip.light[]" "$PACKAGES_FILE" 2>/dev/null || echo "")
        
        if [ -n "$LIGHT_PACKAGES" ]; then
            echo "Installing light mode Python packages..."
            while IFS= read -r package; do
                if [ -n "$package" ]; then
                    echo "  Installing $package..."
                    pip3 install "$package"
                fi
            done <<< "$LIGHT_PACKAGES"
        fi
        
        # For full mode, would also install full packages, but CI only needs light
        # FULL_PACKAGES=$(yq eval ".packages.${OS}.pip.full[]" "$PACKAGES_FILE" 2>/dev/null || echo "")
        
    else
        echo "❌ Unsupported yq version. Please install mikefarah/yq v4+"
        exit 1
    fi
else
    # Fallback to Python parsing if yq is not available
    if command -v python3 >/dev/null 2>&1; then
        echo "Using Python to parse packages.yaml..."
        python3 << 'EOF'
import yaml
import sys
import os
import subprocess

packages_file = os.environ.get('PACKAGES_FILE')
os_type = os.environ.get('OS')

try:
    with open(packages_file, 'r') as f:
        data = yaml.safe_load(f)
    
    packages = data.get('packages', {}).get(os_type, {}).get('pip', {}).get('light', [])
    
    if packages:
        print("Installing light mode Python packages...")
        for package in packages:
            print(f"  Installing {package}...")
            subprocess.run(['pip3', 'install', package], check=True)
    else:
        print("No Python packages found for this OS")
        
except Exception as e:
    print(f"Error parsing packages.yaml: {e}", file=sys.stderr)
    sys.exit(1)
EOF
    else
        echo "❌ Neither yq nor python3 available for parsing YAML"
        exit 1
    fi
fi

echo "✅ Python packages installation complete!"
