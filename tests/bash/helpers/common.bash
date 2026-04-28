#!/usr/bin/env bash
# Shared BATS test setup helpers for the dotfiles repository.
#
# Modeled on the helpers used in DevSecNinja/truenas-apps. Load it from a
# `.bats` file with:
#
#     load '../helpers/common'
#     # or, depending on the file location:
#     load 'helpers/common'
#
# Then call `common_setup` from `setup()` and `common_teardown` from
# `teardown()`. The helper auto-downloads bats-support, bats-assert, and
# bats-file into `tests/bash/libs/` (gitignored) on first use, so existing
# plain-bats tests keep working unchanged while new tests can opt in to the
# richer assertion libraries.

# Resolve repository root from this file's location: tests/bash/helpers/common.bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
TESTS_BASH_DIR="${REPO_ROOT}/tests/bash"

# Auto-install BATS helper libraries if missing
if [ ! -f "${TESTS_BASH_DIR}/libs/bats-support/load.bash" ]; then
	bash "${TESTS_BASH_DIR}/setup_libs.sh"
fi

# shellcheck disable=SC1091
load "${TESTS_BASH_DIR}/libs/bats-support/load"
# shellcheck disable=SC1091
load "${TESTS_BASH_DIR}/libs/bats-assert/load"
# shellcheck disable=SC1091
load "${TESTS_BASH_DIR}/libs/bats-file/load"

common_setup() {
	# Make REPO_ROOT visible to tests
	export REPO_ROOT

	# Ensure ~/.local/bin is on PATH so chezmoi (and friends) are findable
	export PATH="${HOME}/.local/bin:${PATH}"
}

common_teardown() {
	# Placeholder for future per-test cleanup; currently a no-op so test
	# files can call it unconditionally.
	:
}
