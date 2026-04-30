#!/bin/bash
# Disable GitHub CLI telemetry where supported.
#
# Background: gh does not actually expose a `telemetry` config key — the
# previous `gh config set telemetry disabled` call produced the warning
# `'telemetry' is not a known configuration key` and had no effect. gh
# itself does not currently send telemetry, but it (and many other CLIs)
# respect the cross-vendor `DO_NOT_TRACK=1` environment variable. If you
# want a hard opt-out, export `DO_NOT_TRACK=1` from your shell rc files.
# This script is now a no-op kept only so chezmoi does not re-run earlier
# broken versions on machines where the run_once state is missing.

# shellcheck source=home/dot_config/shell/functions/log.sh disable=SC1091
. "${CHEZMOI_SOURCE_DIR}/dot_config/shell/functions/log.sh"
# shellcheck disable=SC2034 # consumed by log.sh
LOG_TAG="gh-telemetry"

if ! command -v gh >/dev/null 2>&1; then
	log_info "gh CLI not found, nothing to do"
	exit 0
fi

log_info "gh has no configurable telemetry; export DO_NOT_TRACK=1 to opt out broadly"
