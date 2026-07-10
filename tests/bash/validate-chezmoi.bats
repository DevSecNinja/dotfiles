#!/usr/bin/env bats
# Tests for Chezmoi configuration validation

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	# Ensure PATH includes ~/.local/bin for chezmoi
	export PATH="${HOME}/.local/bin:${PATH}"
}

@test "validate-chezmoi: chezmoi command is available" {
	# Check if chezmoi is available or can be installed
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed (requires manual installation for test)"
	fi

	run chezmoi --version
	[ "$status" -eq 0 ]
}

@test "validate-chezmoi: can read chezmoi data from repository" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi data --source=.
	[ "$status" -eq 0 ]
	[[ "$output" != "" ]]
}

@test "validate-chezmoi: chezmoi configuration is valid" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi data --source=.
	[ "$status" -eq 0 ]

	# Check for expected fields in output
	[[ "$output" =~ "chezmoi" ]]
}

@test "validate-chezmoi: .chezmoi.yaml.tmpl exists" {
	[ -f "$REPO_ROOT/home/.chezmoi.yaml.tmpl" ]
}

@test "validate-chezmoi: .chezmoiignore exists" {
	[ -f "$REPO_ROOT/home/.chezmoiignore" ]
}

@test "validate-chezmoi: dev/meta files are not applied to the device" {
	# README.md, scaffolding templates and stale *.old copies live alongside
	# real dotfiles in the source tree but must never land on a device.
	# See issue #563.
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi ignored --source=. --no-tty
	[ "$status" -eq 0 ]

	local dev_files=(
		".config/fish/README.md"
		".config/powershell/README.md"
		".config/shell/completions.d/README.md"
		".config/fish/functions/_template.fish"
		".config/powershell/scripts/_template.ps1.txt"
		".config/shell/functions/_template.sh.txt"
		".config/powershell/completions/mise.ps1.old"
	)

	for dev_file in "${dev_files[@]}"; do
		printf '%s\n' "${lines[@]}" | grep -Fxq -- "$dev_file" || {
			echo "Expected dev/meta file to be ignored: $dev_file"
			return 1
		}
	done
}

@test "validate-chezmoi: no README/_template/*.old files are managed" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	cd "$REPO_ROOT/home"
	run chezmoi managed --source=. --no-tty
	[ "$status" -eq 0 ]

	for managed_file in "${lines[@]}"; do
		if printf '%s\n' "$managed_file" | grep -qiE 'README\.md$|_template\.|\.old$'; then
			echo "Unexpected dev/meta file is managed: $managed_file"
			return 1
		fi
	done
}
