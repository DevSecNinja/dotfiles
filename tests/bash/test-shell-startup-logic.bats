#!/usr/bin/env bats
# Tests for shell startup directory logic across all shells

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "test-shell-startup-logic: interactive shells configure the SOPS editor" {
	run grep -Fxq 'export SOPS_EDITOR="code --wait"' "$REPO_ROOT/home/dot_config/shell/config.bash"
	[ "$status" -eq 0 ]

	run grep -Fxq 'export SOPS_EDITOR="code --wait"' "$REPO_ROOT/home/dot_config/shell/config.zsh"
	[ "$status" -eq 0 ]

	run grep -Fxq 'set -gx SOPS_EDITOR "code --wait"' "$REPO_ROOT/home/dot_config/fish/config.fish"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: bash config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.bash"

	if [ ! -f "$config_file" ]; then
		skip "Bash config not found"
	fi

	# Should check if directory exists before cd
	run grep -q '\-d.*projects' "$config_file"
	[ "$status" -eq 0 ]
}

run_bash_startup() {
	run env -u BASH_ENV HOME="$BATS_TEST_TMPDIR/home" TERM_PROGRAM="${2:-}" \
		/bin/bash --noprofile --norc -c '
			cd -- "$1" || exit
			source "$REPO_ROOT/home/dot_config/shell/config.bash"
			pwd
		' bash "$1"
}

@test "test-shell-startup-logic: bash preserves mixed-case projects paths without startup errors" {
	local start="$BATS_TEST_TMPDIR/home/PrOjEcTs/client"
	mkdir -p "$start" "$BATS_TEST_TMPDIR/home/projects"

	run_bash_startup "$start"
	[ "$status" -eq 0 ]
	[ "$output" = "$start" ]
}

@test "test-shell-startup-logic: bash enters projects from an unrelated directory" {
	mkdir -p "$BATS_TEST_TMPDIR/home/work" "$BATS_TEST_TMPDIR/home/projects"

	run_bash_startup "$BATS_TEST_TMPDIR/home/work"
	[ "$status" -eq 0 ]
	[ "$output" = "$BATS_TEST_TMPDIR/home/projects" ]
}

@test "test-shell-startup-logic: bash preserves the VS Code working directory" {
	local start="$BATS_TEST_TMPDIR/home/work"
	mkdir -p "$start" "$BATS_TEST_TMPDIR/home/projects"

	run_bash_startup "$start" vscode
	[ "$status" -eq 0 ]
	[ "$output" = "$start" ]
}

@test "test-shell-startup-logic: bash preserves the working directory when projects is absent" {
	local start="$BATS_TEST_TMPDIR/home/work"
	mkdir -p "$start"

	run_bash_startup "$start"
	[ "$status" -eq 0 ]
	[ "$output" = "$start" ]
}

@test "test-shell-startup-logic: Homebrew completions load only on Bash supporting nosort" {
	export TEST_BREW_PREFIX="$BATS_TEST_TMPDIR/brew"
	local completions="$TEST_BREW_PREFIX/etc/bash_completion.d"
	mkdir -p "$completions"
	cat >"$completions/example" <<'EOF'
complete -o nosort -W example example
printf 'completion loaded\n'
EOF

	run env -u BASH_ENV /bin/bash --noprofile --norc -c '
		brew() { printf "%s\n" "$TEST_BREW_PREFIX"; }
		source "$REPO_ROOT/home/dot_config/shell/completions.d/00-homebrew.bash" || exit
		if (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4) )); then
			complete -p example >/dev/null || exit
		else
			if complete -p example >/dev/null 2>&1; then exit 1; fi
			printf "older Bash: completion skipped\n"
		fi
	'
	[ "$status" -eq 0 ]
	[[ "$output" = "completion loaded" || "$output" = "older Bash: completion skipped" ]]
}

@test "test-shell-startup-logic: zsh config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	# Should check if directory exists before cd
	run grep -q '\-d.*projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: zsh config uses case-insensitive check" {
	local config_file="$REPO_ROOT/home/dot_config/shell/config.zsh"

	if [ ! -f "$config_file" ]; then
		skip "Zsh config not found"
	fi

	# Should use case-insensitive comparison (either parameter expansion or regex)
	run bash -c "grep -q ':l\|[Pp][Rr][Oo][Jj][Ee][Cc][Tt][Ss]' '$config_file'"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config contains VS Code check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	run grep -q 'TERM_PROGRAM.*vscode' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config contains projects path check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	run grep -q 'projects' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config checks directory existence before changing" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	# Should check if directory exists before cd
	run grep -q 'test -d' "$config_file"
	[ "$status" -eq 0 ]
}

@test "test-shell-startup-logic: fish config uses case-insensitive check" {
	local config_file="$REPO_ROOT/home/dot_config/fish/config.fish"

	if [ ! -f "$config_file" ]; then
		skip "Fish config not found"
	fi

	# Should use case-insensitive string match
	run grep -q 'string match.*-qi' "$config_file"
	[ "$status" -eq 0 ]
}
