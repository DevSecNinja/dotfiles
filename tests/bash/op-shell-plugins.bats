#!/usr/bin/env bats
# Tests for the 1Password shell plugin wrappers and the WSL SSH integration.
#
# Unlike the older template tests, these render the REAL templates through
# chezmoi (using a config generated from home/.chezmoi.yaml.tmpl) so a change
# to the template is actually covered.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	export PATH="${HOME}/.local/bin:${PATH}"

	TEST_DIR="$(mktemp -d)"
	export TEST_DIR
	ORIGINAL_PATH="${PATH}"
	export ORIGINAL_PATH

	BASH_TMPL="${REPO_ROOT}/home/dot_config/shell/functions/op-plugins.sh.tmpl"
	FISH_TMPL="${REPO_ROOT}/home/dot_config/fish/conf.d/op-plugins.fish.tmpl"
	export BASH_TMPL FISH_TMPL
}

teardown() {
	export PATH="${ORIGINAL_PATH}"
	if [ -n "${TEST_DIR}" ] && [ -d "${TEST_DIR}" ]; then
		rm -rf "${TEST_DIR}"
	fi
}

# _skip_without_chezmoi -> skip the test when chezmoi is unavailable.
_skip_without_chezmoi() {
	command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
}

# _config [SED_EXPR...] -> render .chezmoi.yaml.tmpl into a config file,
# applying any sed expressions so a test can override single data values.
# Prints the config path. Non-interactive: bats gives a non-TTY stdin, so the
# template's promptString/promptBool calls are skipped.
_config() {
	local cfg="${TEST_DIR}/chezmoi-$(( RANDOM )).yaml" expr
	chezmoi execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl" >"${cfg}"
	for expr in "$@"; do
		sed -i -e "${expr}" "${cfg}"
	done
	printf '%s\n' "${cfg}"
}

# _render CONFIG TEMPLATE -> render a source template with that config.
_render() {
	chezmoi --config "${1}" execute-template <"${2}"
}

@test "op-plugins: templates exist for bash/zsh and fish" {
	[ -f "${BASH_TMPL}" ]
	[ -f "${FISH_TMPL}" ]
}

@test "op-plugins: default plugin list wraps gh and copilot" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config)"
	run _render "${cfg}" "${BASH_TMPL}"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "op plugin run -- gh" ]]
	[[ "$output" =~ "op plugin run -- copilot" ]]
}

@test "op-plugins: rendered bash wrapper has valid bash and zsh syntax" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config)"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"
	run bash -n "${out}"
	[ "$status" -eq 0 ]
	if command -v zsh >/dev/null 2>&1; then
		run zsh -n "${out}"
		[ "$status" -eq 0 ]
	fi
}

@test "op-plugins: rendered fish wrapper has valid fish syntax" {
	_skip_without_chezmoi
	command -v fish >/dev/null 2>&1 || skip "fish not installed"
	local cfg out="${TEST_DIR}/op-plugins.fish"
	cfg="$(_config)"
	_render "${cfg}" "${FISH_TMPL}" >"${out}"
	run fish -n "${out}"
	[ "$status" -eq 0 ]
}

@test "op-plugins: sets OP_PLUGIN_ALIASES_SOURCED so op does not ask for plugins.sh" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config)"
	run _render "${cfg}" "${BASH_TMPL}"
	[[ "$output" =~ "OP_PLUGIN_ALIASES_SOURCED" ]]
	run _render "${cfg}" "${FISH_TMPL}"
	[[ "$output" =~ "OP_PLUGIN_ALIASES_SOURCED" ]]
}

@test "op-plugins: honours a custom plugin list" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config 's|^  opShellPlugins: .*|  opShellPlugins: ["aws"]|')"
	run _render "${cfg}" "${BASH_TMPL}"
	[[ "$output" =~ "op plugin run -- aws" ]]
	[[ ! "$output" =~ "op plugin run -- gh" ]]
}

@test "op-plugins: accepts a comma-separated list and trims, dedupes and sorts it" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/pre.yaml"
	# A local chezmoi config may set the variable as a string instead of a list.
	printf 'data:\n  opShellPlugins: " aws , gh ,, aws "\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'opShellPlugins: ["aws","gh"]' ]]
}

@test "op-plugins: a list-valued override is passed through unchanged" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/pre-list.yaml"
	printf 'data:\n  opShellPlugins:\n    - aws\n    - gh\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'opShellPlugins: ["aws","gh"]' ]]
}

@test "op-plugins: wrappers are guarded on op being installed" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config)"
	run _render "${cfg}" "${BASH_TMPL}"
	[[ "$output" =~ "command -v op" ]]
	run _render "${cfg}" "${FISH_TMPL}"
	[[ "$output" =~ "command -q op" ]]
}

@test "op-plugins: fish wrappers use --wraps so completions keep working" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config)"
	run _render "${cfg}" "${FISH_TMPL}"
	[[ "$output" =~ "--wraps gh" ]]
}

@test "op-plugins: bash wrapper routes the CLI through op plugin run" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config)"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "OP_RUN: $*"\n' >"${TEST_DIR}/op"
	printf '#!/bin/bash\necho "REAL_GH: $*"\n' >"${TEST_DIR}/gh"
	chmod +x "${TEST_DIR}/op" "${TEST_DIR}/gh"

	PATH="${TEST_DIR}:${ORIGINAL_PATH}" run bash -c "source '${out}'; gh auth status"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "OP_RUN: plugin run -- gh auth status" ]]
	[[ ! "$output" =~ "REAL_GH:" ]]
}

@test "op-plugins: nothing is defined when op is not installed" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config)"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "REAL_GH: $*"\n' >"${TEST_DIR}/gh"
	chmod +x "${TEST_DIR}/gh"

	# A PATH with gh but deliberately without op.
	PATH="${TEST_DIR}:/usr/bin:/bin" run bash -c "source '${out}'; gh auth status; echo \"sourced=\${OP_PLUGIN_ALIASES_SOURCED:-unset}\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ "REAL_GH: auth status" ]]
	[[ "$output" =~ "sourced=unset" ]]
}

@test "op-plugins: an uninstalled CLI is not wrapped" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config 's|^  opShellPlugins: .*|  opShellPlugins: ["definitely-not-installed"]|')"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "OP_RUN: $*"\n' >"${TEST_DIR}/op"
	chmod +x "${TEST_DIR}/op"

	PATH="${TEST_DIR}:${ORIGINAL_PATH}" run bash -c "source '${out}'; type -t definitely-not-installed || echo 'not-wrapped'"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "not-wrapped" ]]
}

@test "op-plugins: chezmoi skips the wrappers on WSL (plugins unsupported there)" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config 's|^  wsl: .*|  wsl: true|')"
	run _render "${cfg}" "${REPO_ROOT}/home/.chezmoiignore"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "dot_config/shell/functions/op-plugins.sh" ]]
	[[ "$output" =~ "dot_config/fish/conf.d/op-plugins.fish" ]]
}

@test "op-plugins: wrappers are applied on a non-WSL host" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config 's|^  wsl: .*|  wsl: false|')"
	run _render "${cfg}" "${REPO_ROOT}/home/.chezmoiignore"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "op-plugins" ]]
}

# --- WSL SSH / commit signing ------------------------------------------------

@test "wsl-ssh: alias files exist for bash/zsh and fish" {
	[ -f "${REPO_ROOT}/home/dot_config/shell/functions/wsl-ssh.sh" ]
	[ -f "${REPO_ROOT}/home/dot_config/fish/conf.d/wsl-ssh.fish" ]
}

@test "wsl-ssh: aliases only apply inside WSL with interop available" {
	local f="${REPO_ROOT}/home/dot_config/shell/functions/wsl-ssh.sh"
	run bash -n "${f}"
	[ "$status" -eq 0 ]

	# Not WSL: no aliases defined.
	run bash -c "unset WSL_DISTRO_NAME; source '${f}'; alias ssh 2>/dev/null || echo 'no-alias'"
	[[ "$output" =~ "no-alias" ]]

	# WSL but no ssh.exe on PATH (interop off): still no aliases.
	run bash -c "WSL_DISTRO_NAME=Ubuntu; export WSL_DISTRO_NAME; PATH=/usr/bin:/bin; source '${f}'; alias ssh 2>/dev/null || echo 'no-alias'"
	[[ "$output" =~ "no-alias" ]]
}

@test "wsl-ssh: aliases are defined when WSL and ssh.exe are present" {
	local f="${REPO_ROOT}/home/dot_config/shell/functions/wsl-ssh.sh"
	printf '#!/bin/bash\necho "WIN_SSH: $*"\n' >"${TEST_DIR}/ssh.exe"
	printf '#!/bin/bash\necho "WIN_SSH_ADD: $*"\n' >"${TEST_DIR}/ssh-add.exe"
	chmod +x "${TEST_DIR}/ssh.exe" "${TEST_DIR}/ssh-add.exe"

	run bash -c "WSL_DISTRO_NAME=Ubuntu; export WSL_DISTRO_NAME; PATH='${TEST_DIR}:${ORIGINAL_PATH}'; source '${f}'; alias ssh; alias ssh-add"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ssh.exe" ]]
	[[ "$output" =~ "ssh-add.exe" ]]
}

@test "wsl-signing: WSL with a signing key enables 1Password SSH signing" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	# git needs the key:: prefix to read a literal public key rather than a path.
	[[ "$output" =~ "signingkey = key::ssh-ed25519 AAAATESTKEY comment" ]]
	[[ "$output" =~ "gpgsign = true" ]]
	[[ "$output" =~ "format = ssh" ]]
	# WSL keeps routing ssh through the Windows client.
	[[ "$output" =~ "sshCommand = ssh.exe" ]]
}

@test "wsl-signing: no signing key means no signing configuration" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: ""|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "gpgsign" ]]
	[[ ! "$output" =~ "signingkey" ]]
}

@test "wsl-signing: YubiKey mode takes precedence over the 1Password branch" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: true|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "key::ssh-ed25519 AAAATESTKEY" ]]
}

@test "wsl-signing: native Linux without YubiKey stays unsigned" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  wsl: .*|  wsl: false|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "gpgsign" ]]
}

@test "wsl-signing: allowed_signers lists the 1Password public key" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/allowed_signers.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ssh-ed25519 AAAATESTKEY comment" ]]
}
