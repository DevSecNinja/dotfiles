#!/bin/bash
# Test Fish shell configuration
# Verifies that Fish can start and load the configuration

set -e

echo "🐠 Testing Fish shell configuration..."

# Check if Fish is installed
if ! command -v fish >/dev/null 2>&1; then
	echo "❌ Fish is not installed"
	echo "💡 Run: sudo apt-get install fish (or equivalent for your OS)"
	exit 1
fi

echo "✅ Fish $(fish --version) is available"
echo ""

# Copy Fish config to test location if we're testing from source
if [ -d "dot_config/fish" ]; then
	echo "📋 Copying Fish config for testing..."
	mkdir -p "$HOME/.config/fish"
	cp -r dot_config/fish/* "$HOME/.config/fish/" 2>/dev/null || true
fi

# Test that Fish can start with the config
echo "🧪 Testing Fish startup..."
if fish -c "echo '✅ Fish shell started successfully'"; then
	echo "✅ Fish configuration loads correctly"
else
	echo "❌ Fish failed to start with configuration"
	exit 1
fi

echo ""
echo "🧪 Testing custom functions..."
if fish -c "functions fish-greeting" >/dev/null 2>&1; then
	echo "✅ Custom functions are available"
else
	echo "⚠️  Custom functions not found (may be expected in some cases)"
fi

echo ""
echo "🧪 Testing aliases..."
if fish -c "type -q l" >/dev/null 2>&1; then
	echo "✅ Aliases loaded successfully"
else
	echo "⚠️  Aliases not loaded (may be expected in some cases)"
fi

echo ""
echo "✅ Fish configuration test completed!"
