#!/bin/bash
# Disable GitHub CLI telemetry
# Sets telemetry to disabled in gh config if gh is installed.
# See: https://cli.github.com/manual/gh_config_set

# shellcheck source=home/dot_config/shell/functions/log.sh disable=SC1091
. "${CHEZMOI_SOURCE_DIR}/dot_config/shell/functions/log.sh"
# shellcheck disable=SC2034 # consumed by log.sh
LOG_TAG="gh-telemetry"

if ! command -v gh >/dev/null 2>&1; then
	log_info "gh CLI not found, skipping telemetry configuration"
	exit 0
fi

log_state "Disabling GitHub CLI telemetry"
gh config set telemetry disabled
exit_code=$?
if [ $exit_code -eq 0 ]; then
	log_result "GitHub CLI telemetry disabled"
else
	log_warn "Failed to disable GitHub CLI telemetry (exit code: $exit_code)"
fi
