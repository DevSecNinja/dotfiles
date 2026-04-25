#!/bin/bash
# Disable GitHub CLI telemetry
# Sets telemetry to disabled in gh config if gh is installed.
# See: https://cli.github.com/manual/gh_config_set

if ! command -v gh >/dev/null 2>&1; then
	echo "[SKIP] gh CLI not found, skipping telemetry configuration"
	exit 0
fi

echo ">> Disabling GitHub CLI telemetry..."
gh config set telemetry disabled
exit_code=$?
if [ $exit_code -eq 0 ]; then
	echo "[OK] GitHub CLI telemetry disabled"
else
	echo "[WARN] Failed to disable GitHub CLI telemetry (exit code: $exit_code)"
fi
