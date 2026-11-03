#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  source "$REPO_ROOT/home/.chezmoihelpers/package-uninstall.sh"
  SUDO_CMD="sudo"
  CALLS="$BATS_TEST_TMPDIR/calls"
  INVENTORY="$BATS_TEST_TMPDIR/inventory"
  : >"$CALLS"
  : >"$INVENTORY"
  QUERY_FAIL=0
  QUERY_FAIL_WHEN_EMPTY=0
  REMOVE_FAIL=0
  KEEP_INSTALLED=0
}

log_step() { printf '%s\n' "$*"; }
log_result() { printf '%s\n' "$*"; }
log_error() { printf '%s\n' "$*"; }
log_data() {
  printf '%s\n' "$*"
  cat
}

query_mock() {
  printf 'query %s\n' "$*" >>"$CALLS"
  if [ "$QUERY_FAIL" = 1 ] || { [ "$QUERY_FAIL_WHEN_EMPTY" = 1 ] && [ ! -s "$INVENTORY" ]; }; then
    echo "inventory unavailable" >&2
    return 42
  fi
  cat "$INVENTORY"
}

remove_mock() {
  printf 'remove %s\n' "$*" >>"$CALLS"
  if [ "$REMOVE_FAIL" = 1 ]; then
    echo "removal denied" >&2
    return 43
  fi
  [ "$KEEP_INSTALLED" = 1 ] || : >"$INVENTORY"
}

sudo() {
  printf 'sudo %s\n' "$*" >>"$CALLS"
  "$@"
}

dpkg-query() { query_mock dpkg-query "$@"; }
rpm() { query_mock rpm "$@"; }
apt-get() { remove_mock apt-get "$@"; }
dnf() { remove_mock dnf "$@"; }

brew() {
  if [ "$1" = list ]; then
    query_mock brew "$@"
  else
    printf 'no-autoremove=%s\n' "${HOMEBREW_NO_AUTOREMOVE:-}" >>"$CALLS"
    remove_mock brew "$@"
  fi
}

mas() {
  if [ "$1" = list ]; then
    query_mock mas "$@"
  else
    remove_mock mas "$@"
  fi
}

@test "package-uninstall: APT removes an exact package without purge or autoremove" {
  printf 'legacy amd64 installed\n' >"$INVENTORY"
  run uninstall_package apt legacy
  [ "$status" -eq 0 ]
  grep -Fx 'remove apt-get remove -y -- legacy' "$CALLS"
  grep -Fx 'sudo apt-get remove -y -- legacy' "$CALLS"
  [[ "$output" == *"Uninstalled legacy"* ]]
  [ "$(grep -c '^query ' "$CALLS")" -eq 2 ]
}

@test "package-uninstall: APT handles architecture-qualified names and partial installs" {
  printf 'legacy arm64 unpacked\n' >"$INVENTORY"
  run uninstall_package apt legacy:arm64
  [ "$status" -eq 0 ]
  grep -Fx 'remove apt-get remove -y -- legacy:arm64' "$CALLS"
}

@test "package-uninstall: APT leaves residual configuration alone" {
  printf 'legacy amd64 config-files\n' >"$INVENTORY"
  run uninstall_package apt legacy
  [ "$status" -eq 0 ]
  ! grep -q '^remove ' "$CALLS"
}

@test "package-uninstall: DNF disables automatic removal of unused dependencies" {
  printf 'legacy\n' >"$INVENTORY"
  run uninstall_package dnf legacy
  [ "$status" -eq 0 ]
  grep -Fx 'remove dnf remove -y --setopt=clean_requirements_on_remove=False -- legacy' "$CALLS"
}

@test "package-uninstall: Homebrew formulas remove all versions without autoremove" {
  printf 'vendor/tap/legacy\n' >"$INVENTORY"
  run uninstall_package brew-formula vendor/tap/legacy
  [ "$status" -eq 0 ]
  grep -Fx 'remove brew uninstall --formula --force -- vendor/tap/legacy' "$CALLS"
  grep -Fx 'no-autoremove=1' "$CALLS"
  ! grep -q '^sudo ' "$CALLS"
}

@test "package-uninstall: Homebrew casks do not force, zap or autoremove" {
  printf 'legacy\n' >"$INVENTORY"
  run uninstall_package brew-cask legacy
  [ "$status" -eq 0 ]
  grep -Fx 'remove brew uninstall --cask -- legacy' "$CALLS"
  grep -Fx 'no-autoremove=1' "$CALLS"
}

@test "package-uninstall: Homebrew recognizes unqualified and core-qualified names" {
  for package in legacy homebrew/core/legacy; do
    printf 'legacy\n' >"$INVENTORY"
    run uninstall_package brew-formula "$package"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Uninstalled legacy"* ]]
  done
  printf 'vendor/tap/legacy\n' >"$INVENTORY"
  run uninstall_package brew-formula legacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"Uninstalled legacy"* ]]
}

@test "package-uninstall: Mac App Store removal uses the exact numeric ID" {
  printf '123456 Legacy App (1.0)\n' >"$INVENTORY"
  run uninstall_package mas 123456
  [ "$status" -eq 0 ]
  grep -Fx 'sudo mas uninstall 123456' "$CALLS"
  grep -Fx 'remove mas uninstall 123456' "$CALLS"
}

@test "package-uninstall: absent packages are skipped for every manager" {
  for manager in apt dnf brew-formula brew-cask mas; do
    run uninstall_package "$manager" 123456
    [ "$status" -eq 0 ]
    [[ "$output" == *"is not installed"* ]]
  done
  ! grep -q '^remove ' "$CALLS"
}

@test "package-uninstall: inventory failures are not mistaken for absence" {
  QUERY_FAIL=1
  for manager in apt dnf brew-formula brew-cask mas; do
    run uninstall_package "$manager" 123456
    [ "$status" -ne 0 ]
    [[ "$output" == *"Could not list"* ]]
    [[ "$output" == *"inventory unavailable"* ]]
  done
  ! grep -q '^remove ' "$CALLS"
}

@test "package-uninstall: removal failures stop every manager" {
  REMOVE_FAIL=1
  for manager in apt dnf brew-formula brew-cask mas; do
    if [ "$manager" = apt ]; then
      printf '123456 amd64 installed\n' >"$INVENTORY"
    else
      printf '123456\n' >"$INVENTORY"
    fi
    run uninstall_package "$manager" 123456
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to uninstall"* ]]
    [[ "$output" == *"removal denied"* ]]
  done
}

@test "package-uninstall: verifies absence after a successful removal command" {
  KEEP_INSTALLED=1
  for manager in apt dnf brew-formula brew-cask mas; do
    if [ "$manager" = apt ]; then
      printf '123456 amd64 installed\n' >"$INVENTORY"
    else
      printf '123456\n' >"$INVENTORY"
    fi
    run uninstall_package "$manager" 123456
    [ "$status" -ne 0 ]
    [[ "$output" == *"still installed"* ]]
  done
}

@test "package-uninstall: repeated runs do not remove twice" {
  printf 'legacy\n' >"$INVENTORY"
  run uninstall_package brew-formula legacy
  [ "$status" -eq 0 ]
  run uninstall_package brew-formula legacy
  [ "$status" -eq 0 ]
  [ "$(grep -c '^remove ' "$CALLS")" -eq 1 ]
}

@test "package-uninstall: verification query failures are reported" {
  QUERY_FAIL_WHEN_EMPTY=1
  printf 'legacy\n' >"$INVENTORY"
  run uninstall_package dnf legacy
  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not verify removal"* ]]
}

@test "package-uninstall: root removal does not require sudo" {
  SUDO_CMD=""
  printf 'legacy\n' >"$INVENTORY"
  run uninstall_package dnf legacy
  [ "$status" -eq 0 ]
  ! grep -q '^sudo ' "$CALLS"
}

@test "package-uninstall: package matches are exact, not prefixes or regexes" {
  printf 'legacy-tools\nlegacyXname\n' >"$INVENTORY"
  run uninstall_package dnf legacy
  [ "$status" -eq 0 ]
  run uninstall_package dnf legacy.name
  [ "$status" -eq 0 ]
  ! grep -q '^remove ' "$CALLS"
}

@test "package-uninstall: invalid selectors never reach a package manager" {
  for manager in apt dnf brew-formula brew-cask mas; do
    for package in '*' '--all' '../legacy' 'legacy;false'; do
      run uninstall_package "$manager" "$package"
      [ "$status" -ne 0 ]
      [[ "$output" == *"Invalid"* ]]
    done
  done
  [ ! -s "$CALLS" ]
}

@test "package-uninstall: unsupported managers fail explicitly" {
  run uninstall_package unknown legacy
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsupported uninstall manager"* ]]
}
