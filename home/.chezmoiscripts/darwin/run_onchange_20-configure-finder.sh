#!/bin/bash

set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
    exit 0
fi

# shellcheck source=home/dot_config/shell/functions/log.sh disable=SC1091
. "${CHEZMOI_SOURCE_DIR}/dot_config/shell/functions/log.sh"
# shellcheck disable=SC2034 # consumed by log.sh
LOG_TAG="configure-finder"

log_state "Configuring Finder to show hidden files"

if ! defaults write com.apple.finder AppleShowAllFiles -bool true; then
    log_error "Failed to enable hidden files in Finder"
    exit 1
fi

log_result "Finder is configured to show hidden files"
log_hint "Relaunch Finder or log out and back in for the change to take effect"
