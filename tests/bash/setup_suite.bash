#!/usr/bin/env bash
# Bats suite-level setup, auto-loaded by Bats from the directory of the first
# test file (also when running a single file directly with `bats <file>`).

setup_suite() {
  # Many tests create a throwaway git repo and commit into it. A developer
  # machine usually has `commit.gpgsign = true` in its global config, because
  # chezmoi enables SSH commit signing via the 1Password agent or a YubiKey.
  # Those signers need an unlocked agent and a user present, so every such
  # commit fails (or blocks until the test times out) in a headless run.
  # Force signing off for the whole suite instead of opting out per test file.
  export GIT_CONFIG_COUNT=2
  export GIT_CONFIG_KEY_0=commit.gpgsign
  export GIT_CONFIG_VALUE_0=false
  export GIT_CONFIG_KEY_1=tag.gpgsign
  export GIT_CONFIG_VALUE_1=false
}
