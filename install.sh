#!/bin/sh

# Wrapper script for Coder support
# Coder looks for install.sh in the repository root
# This script delegates to the actual install script in the home directory

# -e: exit on error
# -u: exit on unset variables
set -eu

# POSIX way to get script's dir: https://stackoverflow.com/a/29834779/12156188
script_dir="$(cd -P -- "$(dirname -- "$(command -v -- "$0")")" && pwd -P)"

# Run the actual install script from the home directory
exec "${script_dir}/home/install.sh"
