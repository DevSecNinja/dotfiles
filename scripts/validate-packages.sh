#!/bin/bash
# Validate packages.yaml syntax and structure
# Ensures the YAML file is valid and contains expected sections

set -e

SOURCE_DIR="${1:-.}"
PACKAGES_FILE="${SOURCE_DIR}/.chezmoidata/packages.yaml"

echo "Validating packages.yaml..."

# Check if file exists
if [ ! -f "$PACKAGES_FILE" ]; then
	echo "❌ packages.yaml not found at $PACKAGES_FILE"
	exit 1
fi

# Check if yq or python with pyyaml is available for YAML validation
if command -v yq >/dev/null 2>&1; then
	# Validate YAML syntax with yq
	# Check which version of yq (Go version supports eval, Python version doesn't)
	if yq --version 2>&1 | grep -q 'mikefarah\|version 4'; then
		# Go yq (mikefarah/yq)
		if yq eval '.' "$PACKAGES_FILE" >/dev/null 2>&1; then
			echo "✅ YAML syntax is valid (verified with yq)"
		else
			echo "❌ YAML syntax errors detected"
			yq eval '.' "$PACKAGES_FILE" 2>&1
			exit 1
		fi
	elif yq --help 2>&1 | grep -q 'yaml-output\|python'; then
		# Python yq (kislyuk/yq) - different syntax
		if yq -y . "$PACKAGES_FILE" >/dev/null 2>&1; then
			echo "✅ YAML syntax is valid (verified with Python yq)"
		else
			echo "❌ YAML syntax errors detected"
			yq -y . "$PACKAGES_FILE" 2>&1
			exit 1
		fi
	else
		# Unknown yq version, try basic eval
		if yq '.' "$PACKAGES_FILE" >/dev/null 2>&1; then
			echo "✅ YAML syntax is valid (verified with yq)"
		else
			echo "❌ YAML syntax errors detected"
			yq '.' "$PACKAGES_FILE" 2>&1
			exit 1
		fi
	fi
elif command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" 2>/dev/null; then
	# Validate YAML syntax with Python
	if python3 -c "import yaml; yaml.safe_load(open('$PACKAGES_FILE'))" 2>/dev/null; then
		echo "✅ YAML syntax is valid"
	else
		echo "❌ YAML syntax errors detected"
		python3 -c "import yaml; yaml.safe_load(open('$PACKAGES_FILE'))"
		exit 1
	fi
else
	echo "⚠️  Warning: Neither yq nor python3 with PyYAML found, skipping YAML validation"
	echo "   Install yq or 'pip3 install pyyaml' for validation"
fi

# Check for expected top-level keys
echo "Checking for required sections..."
required_sections=("packages")

for section in "${required_sections[@]}"; do
	if grep -q "^${section}:" "$PACKAGES_FILE"; then
		echo "✅ Found section: ${section}"
	else
		echo "❌ Missing required section: ${section}"
		exit 1
	fi
done

# Check for platform-specific package lists
echo "Checking for platform-specific package definitions..."
platforms=("linux" "darwin" "windows")

for platform in "${platforms[@]}"; do
	if grep -q "${platform}:" "$PACKAGES_FILE"; then
		echo "✅ Found platform: ${platform}"
	else
		echo "⚠️  Warning: No packages defined for platform: ${platform}"
	fi
done

echo "✅ packages.yaml validation complete!"
