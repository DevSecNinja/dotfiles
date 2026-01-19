#!/bin/bash
# mise (rtx) initialization for Bash
# This file handles mise shell integration and completion

# Initialize mise if available
if command -v mise >/dev/null 2>&1; then
	eval "$(mise activate bash)"
fi
