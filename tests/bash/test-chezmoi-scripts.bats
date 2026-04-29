#!/usr/bin/env bats
# Tests for Chezmoi run scripts (run_once and run_onchange scripts)
# These tests validate the structure, syntax and behavior of templated chezmoi scripts.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	LINUX_SCRIPTS_DIR="$REPO_ROOT/home/.chezmoiscripts/linux"
	DARWIN_SCRIPTS_DIR="$REPO_ROOT/home/.chezmoiscripts/darwin"
	export LINUX_SCRIPTS_DIR DARWIN_SCRIPTS_DIR

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
}

teardown() {
	[ -n "$TEST_DIR" ] && [ -d "$TEST_DIR" ] && rm -rf "$TEST_DIR"
}

# Helper: strip Chezmoi template directives ({{ ... }}) from a script so we
# can run a syntax check on the resulting plain bash. Comment-style template
# directives ({{- ... -}} or # {{ ... }}) are removed line-by-line first, then
# any remaining inline {{ ... }} expressions are replaced with the placeholder
# string "PLACEHOLDER" so syntactic position remains valid.
strip_template() {
	local script="$1"
	# Remove lines that are pure template directives (optionally prefixed with #)
	# and substitute remaining {{ ... }} expressions with a placeholder string.
	sed -E '/^[[:space:]]*#?[[:space:]]*\{\{.*\}\}[[:space:]]*$/d' "$script" |
		sed -E 's/\{\{[^}]*\}\}/PLACEHOLDER/g'
}

@test "chezmoi-scripts: linux scripts directory exists" {
	[ -d "$LINUX_SCRIPTS_DIR" ]
}

@test "chezmoi-scripts: darwin scripts directory exists" {
	[ -d "$DARWIN_SCRIPTS_DIR" ]
}

@test "chezmoi-scripts: run_once_before_00-setup.sh.tmpl exists and has set -e" {
	local script="$LINUX_SCRIPTS_DIR/run_once_before_00-setup.sh.tmpl"
	[ -f "$script" ]
	grep -q "set -e" "$script"
}

@test "chezmoi-scripts: run_once_before_00-setup creates expected directories" {
	local script="$LINUX_SCRIPTS_DIR/run_once_before_00-setup.sh.tmpl"
	grep -q "mkdir -p" "$script"
	grep -q "\.vim/undo" "$script"
}

@test "chezmoi-scripts: run_once_before_00-setup has valid bash syntax (after stripping templates)" {
	local script="$LINUX_SCRIPTS_DIR/run_once_before_00-setup.sh.tmpl"
	local rendered="$TEST_DIR/rendered.sh"
	strip_template "$script" >"$rendered"
	run bash -n "$rendered"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: run_once_before_01-install-ppas.sh.tmpl exists" {
	[ -f "$LINUX_SCRIPTS_DIR/run_once_before_01-install-ppas.sh.tmpl" ]
}

@test "chezmoi-scripts: install-ppas script references add-apt-repository" {
	grep -q "add-apt-repository" "$LINUX_SCRIPTS_DIR/run_once_before_01-install-ppas.sh.tmpl"
}

@test "chezmoi-scripts: install-ppas script handles non-Ubuntu/Debian gracefully" {
	# Should have an else branch for non-supported systems
	grep -q 'osRelease.id' "$LINUX_SCRIPTS_DIR/run_once_before_01-install-ppas.sh.tmpl"
}

@test "chezmoi-scripts: install-ppas distinguishes light vs full install modes" {
	grep -q '\.installType' "$LINUX_SCRIPTS_DIR/run_once_before_01-install-ppas.sh.tmpl"
}

@test "chezmoi-scripts: install-ppas script falls back when sudo is unavailable" {
	grep -q "command -v sudo" "$LINUX_SCRIPTS_DIR/run_once_before_01-install-ppas.sh.tmpl"
}

@test "chezmoi-scripts: run_once_before_05-install-homebrew.sh.tmpl exists" {
	[ -f "$LINUX_SCRIPTS_DIR/run_once_before_05-install-homebrew.sh.tmpl" ]
}

@test "chezmoi-scripts: install-homebrew references brew or Homebrew" {
	grep -qiE "brew|homebrew" "$LINUX_SCRIPTS_DIR/run_once_before_05-install-homebrew.sh.tmpl"
}

@test "chezmoi-scripts: install-homebrew has valid bash syntax (after stripping templates)" {
	local script="$LINUX_SCRIPTS_DIR/run_once_before_05-install-homebrew.sh.tmpl"
	local rendered="$TEST_DIR/rendered.sh"
	strip_template "$script" >"$rendered"
	run bash -n "$rendered"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: run_once_install-lefthook.sh.tmpl exists" {
	[ -f "$LINUX_SCRIPTS_DIR/run_once_install-lefthook.sh.tmpl" ]
}

@test "chezmoi-scripts: install-lefthook handles light vs full mode" {
	grep -q '\.installType' "$LINUX_SCRIPTS_DIR/run_once_install-lefthook.sh.tmpl"
}

@test "chezmoi-scripts: install-lefthook checks if lefthook already installed (idempotency)" {
	grep -q "command -v lefthook" "$LINUX_SCRIPTS_DIR/run_once_install-lefthook.sh.tmpl"
}

@test "chezmoi-scripts: install-lefthook has valid bash syntax (after stripping templates)" {
	local script="$LINUX_SCRIPTS_DIR/run_once_install-lefthook.sh.tmpl"
	local rendered="$TEST_DIR/rendered.sh"
	strip_template "$script" >"$rendered"
	run bash -n "$rendered"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: run_once_setup-lefthook.sh exists and has set -e" {
	local script="$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
	[ -f "$script" ]
	grep -q "set -e" "$script"
}

@test "chezmoi-scripts: setup-lefthook has valid bash syntax" {
	run bash -n "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: setup-lefthook skips git hooks installation in CI" {
	grep -q "GITHUB_ACTIONS\|CI" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
}

@test "chezmoi-scripts: setup-lefthook verifies lefthook config exists" {
	grep -q "\.lefthook.toml\|lefthook.yml" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
}

@test "chezmoi-scripts: setup-lefthook is idempotent (checks already-installed)" {
	grep -q "already installed\|command -v lefthook" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
}

@test "chezmoi-scripts: setup-lefthook checks packages.yaml before mise usage" {
	grep -q "mise_required_for_current_install" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
	grep -q "skipping lefthook setup: mise not required for this install type" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
}

@test "chezmoi-scripts: setup-lefthook installs tools with mise install, not mise exec" {
	grep -q "mise install" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
	! grep -q "mise exec" "$LINUX_SCRIPTS_DIR/run_once_setup-lefthook.sh"
}

@test "chezmoi-scripts: run_onchange_10-install-packages.sh.tmpl exists" {
	[ -f "$LINUX_SCRIPTS_DIR/run_onchange_10-install-packages.sh.tmpl" ]
}

@test "chezmoi-scripts: install-packages script has valid bash syntax (after stripping templates)" {
	local script="$LINUX_SCRIPTS_DIR/run_onchange_10-install-packages.sh.tmpl"
	local rendered="$TEST_DIR/rendered.sh"
	strip_template "$script" >"$rendered"
	run bash -n "$rendered"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: install-packages script handles light/full installation modes" {
	grep -q '\.installType' "$LINUX_SCRIPTS_DIR/run_onchange_10-install-packages.sh.tmpl"
}

@test "chezmoi-scripts: darwin run_once_before_10-setup-fish-default-shell.sh.tmpl exists" {
	[ -f "$DARWIN_SCRIPTS_DIR/run_once_before_10-setup-fish-default-shell.sh.tmpl" ]
}

@test "chezmoi-scripts: darwin fish setup script references fish" {
	grep -q "fish" "$DARWIN_SCRIPTS_DIR/run_once_before_10-setup-fish-default-shell.sh.tmpl"
}

@test "chezmoi-scripts: darwin fish setup script has valid bash syntax (after stripping templates)" {
	local script="$DARWIN_SCRIPTS_DIR/run_once_before_10-setup-fish-default-shell.sh.tmpl"
	local rendered="$TEST_DIR/rendered.sh"
	strip_template "$script" >"$rendered"
	run bash -n "$rendered"
	[ "$status" -eq 0 ]
}

@test "chezmoi-scripts: all run_once_ scripts use the run_once_ prefix correctly" {
	# All scripts in the chezmoiscripts directory should have either run_once_ or run_onchange_ prefix
	for dir in "$LINUX_SCRIPTS_DIR" "$DARWIN_SCRIPTS_DIR"; do
		[ -d "$dir" ] || continue
		while IFS= read -r script; do
			basename=$(basename "$script")
			[[ "$basename" =~ ^(run_once_|run_onchange_) ]] || {
				echo "Script does not have run_once_ or run_onchange_ prefix: $basename"
				return 1
			}
		done < <(find "$dir" -maxdepth 1 -name "*.sh*" -type f)
	done
}

@test "chezmoi-scripts: all .sh.tmpl scripts have a bash shebang" {
	for dir in "$LINUX_SCRIPTS_DIR" "$DARWIN_SCRIPTS_DIR"; do
		[ -d "$dir" ] || continue
		while IFS= read -r script; do
			first_line=$(head -n 1 "$script")
			[[ "$first_line" =~ ^#! ]] || {
				echo "Script has no shebang: $script"
				return 1
			}
		done < <(find "$dir" -maxdepth 1 -name "*.sh.tmpl" -type f)
	done
}
