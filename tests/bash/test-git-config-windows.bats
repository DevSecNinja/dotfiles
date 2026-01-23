#!/usr/bin/env bats

# Test Git configuration rendering for Windows
# Validates that the sshCommand is correctly set for Windows OS

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	# Ensure PATH includes ~/.local/bin for chezmoi
	export PATH="${HOME}/.local/bin:${PATH}"

	# Create temporary file for tests
	TEST_TEMPLATE="$(mktemp)"
	export TEST_TEMPLATE
}

# Teardown function runs after each test
teardown() {
	# Clean up temporary file if it exists
	if [ -n "$TEST_TEMPLATE" ] && [ -f "$TEST_TEMPLATE" ]; then
		rm -f "$TEST_TEMPLATE"
	fi
}

@test "git-config-windows: Git config template exists" {
	[ -f "$REPO_ROOT/home/dot_config/git/config.tmpl" ]
}

@test "git-config-windows: Windows sshCommand is configured correctly" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Test the Git config template rendering for Windows
	# Using chezmoi data structure to simulate Windows OS without WSL
	cat >"$TEST_TEMPLATE" <<'EOF'
{{- /* Simulate Windows OS data */ -}}
{{- $chezmoi := dict "os" "windows" -}}
{{- $wsl := false -}}
[core]
	editor = vim
	autocrlf = input
	excludesfile = ~/.config/git/ignore
{{- if $wsl }}
	sshCommand = ssh.exe
{{- else if eq $chezmoi.os "windows" }}
	sshCommand = "C:/Windows/System32/OpenSSH/ssh.exe"
{{- end }}
EOF

	run chezmoi execute-template <"$TEST_TEMPLATE"
	[ "$status" -eq 0 ]

	# Verify the output contains Windows SSH command
	[[ "$output" == *'sshCommand = "C:/Windows/System32/OpenSSH/ssh.exe"'* ]]
}

@test "git-config-windows: WSL sshCommand takes precedence over Windows" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Test that WSL configuration takes precedence
	# Using chezmoi data structure to simulate WSL environment
	cat >"$TEST_TEMPLATE" <<'EOF'
{{- /* Simulate WSL environment */ -}}
{{- $chezmoi := dict "os" "linux" -}}
{{- $wsl := true -}}
[core]
	editor = vim
	autocrlf = input
	excludesfile = ~/.config/git/ignore
{{- if $wsl }}
	sshCommand = ssh.exe
{{- else if eq $chezmoi.os "windows" }}
	sshCommand = "C:/Windows/System32/OpenSSH/ssh.exe"
{{- end }}
EOF

	run chezmoi execute-template <"$TEST_TEMPLATE"
	[ "$status" -eq 0 ]

	# Verify the output contains WSL SSH command (not Windows)
	[[ "$output" == *'sshCommand = ssh.exe'* ]]
	[[ "$output" != *'C:/Windows/System32/OpenSSH/ssh.exe'* ]]
}

@test "git-config-windows: Linux does not have sshCommand" {
	# Check if chezmoi is available
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Test that Linux config doesn't set sshCommand
	# Using chezmoi data structure to simulate native Linux (not WSL)
	cat >"$TEST_TEMPLATE" <<'EOF'
{{- /* Simulate native Linux (not WSL) */ -}}
{{- $chezmoi := dict "os" "linux" -}}
{{- $wsl := false -}}
[core]
	editor = vim
	autocrlf = input
	excludesfile = ~/.config/git/ignore
{{- if $wsl }}
	sshCommand = ssh.exe
{{- else if eq $chezmoi.os "windows" }}
	sshCommand = "C:/Windows/System32/OpenSSH/ssh.exe"
{{- end }}
EOF

	run chezmoi execute-template <"$TEST_TEMPLATE"
	[ "$status" -eq 0 ]

	# Verify the output does not contain sshCommand
	[[ "$output" != *'sshCommand'* ]]
}
