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
	AGENT_TMPL="${REPO_ROOT}/home/AppData/Local/1Password/config/ssh/agent.toml.tmpl"
	export BASH_TMPL FISH_TMPL AGENT_TMPL
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

# _fake_dsregcmd TENANT_NAME -> put a fake wslinfo + dsregcmd.exe on PATH so the
# config template's Entra ID detection is deterministic regardless of the host
# it runs on. A tenant ending in "Microsoft" is what flips isWork to true.
_fake_dsregcmd() {
	local bin="${TEST_DIR}/fake-bin"
	mkdir -p "${bin}"
	printf '#!/bin/sh\necho "2.5.7"\n' >"${bin}/wslinfo"
	printf '#!/bin/sh\nprintf "AzureAdJoined : YES\\nTenantName : %s\\n"\n' "${1}" \
		>"${bin}/dsregcmd.exe"
	chmod +x "${bin}/wslinfo" "${bin}/dsregcmd.exe"
	export PATH="${bin}:${PATH}"
}

# _fake_wsl_localappdata LOCAL_APP_DATA [WSLPATH_STATUS] -> put fake cmd.exe
# and wslpath commands on PATH so WSL signer detection is host-independent.
_fake_wsl_localappdata() {
	local local_app_data="${1}" wslpath_status="${2:-0}"
	local bin="${TEST_DIR}/fake-wsl-bin"
	mkdir -p "${bin}"
	printf '#!/bin/sh\nprintf "C:\\\\Users\\\\Test\\\\AppData\\\\Local\\r\\n"\n' >"${bin}/cmd.exe"
	if [ "${wslpath_status}" -eq 0 ]; then
		printf '#!/bin/sh\nprintf '\''%%s\\n'\'' '\''%s'\''\n' "${local_app_data}" >"${bin}/wslpath"
	else
		printf '#!/bin/sh\nexit %s\n' "${wslpath_status}" >"${bin}/wslpath"
	fi
	chmod +x "${bin}/cmd.exe" "${bin}/wslpath"
	export PATH="${bin}:${PATH}"
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

	PATH="${TEST_DIR}:${ORIGINAL_PATH}" run env -u SSH_CONNECTION bash -c "source '${out}'; gh auth status"
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
	PATH="${TEST_DIR}:/usr/bin:/bin" run env -u SSH_CONNECTION bash -c "source '${out}'; gh auth status; echo \"sourced=\${OP_PLUGIN_ALIASES_SOURCED:-unset}\""
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

	PATH="${TEST_DIR}:${ORIGINAL_PATH}" run env -u SSH_CONNECTION bash -c "source '${out}'; type -t definitely-not-installed || echo 'not-wrapped'"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "not-wrapped" ]]
}

@test "op-plugins: chezmoi skips the wrappers on WSL (plugins unsupported there)" {
	_skip_without_chezmoi
	local cfg="${TEST_DIR}/wsl.yaml"
	printf 'data:\n  wsl: true\n' >"${cfg}"
	# Assert real ignore behaviour, not the rendered text: .chezmoiignore
	# patterns match the TARGET path, so a dot_config/... pattern would render
	# fine yet never match anything.
	cd "${REPO_ROOT}/home"
	run chezmoi --config "${cfg}" ignored --source=. --no-tty
	[ "$status" -eq 0 ]
	printf '%s\n' "${lines[@]}" | grep -Fxq -- ".config/shell/functions/op-plugins.sh"
	printf '%s\n' "${lines[@]}" | grep -Fxq -- ".config/fish/conf.d/op-plugins.fish"
}

@test "op-plugins: wrappers are applied on a non-WSL host" {
	_skip_without_chezmoi
	local cfg="${TEST_DIR}/nowsl.yaml"
	printf 'data:\n  wsl: false\n' >"${cfg}"
	cd "${REPO_ROOT}/home"
	run chezmoi --config "${cfg}" ignored --source=. --no-tty
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "op-plugins" ]]

	run chezmoi --config "${cfg}" managed --source=. --no-tty
	[ "$status" -eq 0 ]
	printf '%s\n' "${lines[@]}" | grep -Fxq -- ".config/shell/functions/op-plugins.sh"
	printf '%s\n' "${lines[@]}" | grep -Fxq -- ".config/fish/conf.d/op-plugins.fish"
}

@test "op-plugins: .chezmoiignore evaluates without a rendered config" {
	_skip_without_chezmoi
	# `chezmoi ignored/managed` is run in CI without the config generated from
	# .chezmoi.yaml.tmpl, so custom data keys such as .wsl are absent and a
	# bare {{ if .wsl }} would abort the whole template.
	local cfg="${TEST_DIR}/empty.yaml"
	printf '{}\n' >"${cfg}"
	cd "${REPO_ROOT}/home"
	run chezmoi --config "${cfg}" ignored --source=. --no-tty
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "map has no entry for key" ]]
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

@test "wsl-signing: WSL with a signing key and a signer enables 1Password signing" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|' \
		"s|^  opSshSignProgram: .*|  opSshSignProgram: \"${TEST_DIR}/op-ssh-sign-wsl.exe\"|")"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	# git needs the key:: prefix to read a literal public key rather than a path.
	[[ "$output" =~ "signingkey = key::ssh-ed25519 AAAATESTKEY comment" ]]
	[[ "$output" =~ "gpgsign = true" ]]
	[[ "$output" =~ "format = ssh" ]]
	[[ "$output" =~ "op-ssh-sign-wsl.exe" ]]
	# WSL keeps routing ssh through the Windows client.
	[[ "$output" =~ "sshCommand = ssh.exe" ]]
}

@test "wsl-signing: a missing signer leaves signing OFF rather than breaking commits" {
	_skip_without_chezmoi
	local cfg chezmoi_bin
	# Hide Windows interop even when this test runs inside WSL. Enabling gpgsign
	# without a signer would make every commit fail.
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|' \
		's|^  opSshSignProgram: .*|  opSshSignProgram: ""|')"
	chezmoi_bin="$(dirname "$(command -v chezmoi)")"
	PATH="${chezmoi_bin}:/usr/bin:/bin" run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "gpgsign" ]]
	[[ ! "$output" =~ "signingkey" ]]
	[[ "$output" =~ "signing is left OFF on purpose" ]]
}

@test "wsl-signing: auto-detection uses the current user's MSIX signer" {
	_skip_without_chezmoi
	local cfg local_app_data="${TEST_DIR}/LocalAppData"
	mkdir -p "${local_app_data}/Microsoft/WindowsApps" "${local_app_data}/1Password/app/8"
	touch "${local_app_data}/Microsoft/WindowsApps/op-ssh-sign-wsl.exe"
	touch "${local_app_data}/1Password/app/8/op-ssh-sign-wsl"
	_fake_wsl_localappdata "${local_app_data}"
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|' \
		's|^  opSshSignProgram: .*|  opSshSignProgram: ""|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "program = \"${local_app_data}/Microsoft/WindowsApps/op-ssh-sign-wsl.exe\"" ]]
	[[ ! "$output" =~ "program = \"${local_app_data}/1Password/app/8/op-ssh-sign-wsl\"" ]]
	[[ "$output" =~ "gpgsign = true" ]]
}

@test "wsl-signing: auto-detection falls back to the pre-MSIX signer" {
	_skip_without_chezmoi
	local cfg local_app_data="${TEST_DIR}/LocalAppData"
	mkdir -p "${local_app_data}/1Password/app/8"
	touch "${local_app_data}/1Password/app/8/op-ssh-sign-wsl"
	_fake_wsl_localappdata "${local_app_data}"
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|' \
		's|^  opSshSignProgram: .*|  opSshSignProgram: ""|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "program = \"${local_app_data}/1Password/app/8/op-ssh-sign-wsl\"" ]]
	[[ "$output" =~ "gpgsign = true" ]]
}

@test "wsl-signing: a failed LocalAppData conversion leaves signing OFF" {
	_skip_without_chezmoi
	local cfg
	_fake_wsl_localappdata "${TEST_DIR}/LocalAppData" 1
	cfg="$(_config \
		's|^  wsl: .*|  wsl: true|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY comment"|' \
		's|^  opSshSignProgram: .*|  opSshSignProgram: ""|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ ! "$output" =~ "gpgsign" ]]
	[[ "$output" =~ "signing is left OFF on purpose" ]]
}

@test "wsl-signing: auto-detection never scans every Windows profile" {
	run grep -F "/mnt/c/Users/*/" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -ne 0 ]
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

@test "signing: Linux auto-detects no signer, so it stays unsigned" {
	_skip_without_chezmoi
	local cfg
	# There is no auto-detected 1Password signer path on Linux; a desktop-Linux
	# user points at theirs with opSshSignProgram.
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

@test "op-plugins: wrappers stay out of the way in an SSH session" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config)"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "OP_RUN: $*"\n' >"${TEST_DIR}/op"
	printf '#!/bin/bash\necho "REAL_GH: $*"\n' >"${TEST_DIR}/gh"
	chmod +x "${TEST_DIR}/op" "${TEST_DIR}/gh"

	# `op plugin run` needs the 1Password desktop app, which a headless host
	# reached over SSH does not have. Wrapping there would break copilot-ssh,
	# whose whole job is forwarding COPILOT_GITHUB_TOKEN / GH_TOKEN to it.
	PATH="${TEST_DIR}:${ORIGINAL_PATH}" SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" \
		run bash -c "source '${out}'; gh auth status; echo \"sourced=\${OP_PLUGIN_ALIASES_SOURCED:-unset}\""
	[ "$status" -eq 0 ]
	[[ "$output" =~ "REAL_GH: auth status" ]]
	[[ ! "$output" =~ "OP_RUN:" ]]
	[[ "$output" =~ "sourced=unset" ]]
}

@test "op-plugins: fish wrappers also stay out of the way over SSH" {
	_skip_without_chezmoi
	command -v fish >/dev/null 2>&1 || skip "fish not installed"
	local cfg out="${TEST_DIR}/op-plugins.fish"
	cfg="$(_config)"
	_render "${cfg}" "${FISH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "OP_RUN: $*"\n' >"${TEST_DIR}/op"
	printf '#!/bin/bash\necho "REAL_GH: $*"\n' >"${TEST_DIR}/gh"
	chmod +x "${TEST_DIR}/op" "${TEST_DIR}/gh"

	run fish --no-config -c "set -gx PATH '${TEST_DIR}' \$PATH; set -gx SSH_CONNECTION '10.0.0.1 22 10.0.0.2 22'; source '${out}'; gh auth status"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "REAL_GH: auth status" ]]
	[[ ! "$output" =~ "OP_RUN:" ]]
}

@test "op-plugins: copilot-ssh forwarded tokens survive on the remote host" {
	_skip_without_chezmoi
	local cfg out="${TEST_DIR}/op-plugins.sh"
	cfg="$(_config)"
	_render "${cfg}" "${BASH_TMPL}" >"${out}"

	printf '#!/bin/bash\necho "OP_RUN: $*"\n' >"${TEST_DIR}/op"
	printf '#!/bin/bash\necho "COPILOT_TOKEN=${COPILOT_GITHUB_TOKEN:-unset}"\n' >"${TEST_DIR}/copilot"
	chmod +x "${TEST_DIR}/op" "${TEST_DIR}/copilot"

	# Simulates the session copilot-ssh opens: token forwarded via SendEnv, and
	# op present on the remote. The real copilot must run and see the token.
	PATH="${TEST_DIR}:${ORIGINAL_PATH}" SSH_CONNECTION="10.0.0.1 22 10.0.0.2 22" \
		COPILOT_GITHUB_TOKEN="forwarded-token" \
		run bash -c "source '${out}'; copilot"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "COPILOT_TOKEN=forwarded-token" ]]
	[[ ! "$output" =~ "OP_RUN:" ]]
}

@test "signing: a Windows signer path is emitted with forward slashes" {
	_skip_without_chezmoi
	local cfg
	# git config treats backslashes as escapes, so a native-Windows path must be
	# normalised — which is also the form 1Password's own snippet uses.
	cfg="$(_config \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY"|' \
		's|^  opSshSignProgram: .*|  opSshSignProgram: "C:\\\\Users\\\\Me\\\\AppData\\\\Local\\\\Microsoft\\\\WindowsApps\\\\op-ssh-sign.exe"|')"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'program = "C:/Users/Me/AppData/Local/Microsoft/WindowsApps/op-ssh-sign.exe"' ]]
	[[ ! "$output" =~ '\\' ]]
	[[ "$output" =~ "gpgsign = true" ]]
}

@test "signing: a key without a comment still gets the key:: prefix" {
	_skip_without_chezmoi
	local cfg
	# 1Password's snippet emits a bare key with no trailing comment.
	cfg="$(_config \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO9Rsn"|' \
		"s|^  opSshSignProgram: .*|  opSshSignProgram: \"${TEST_DIR}/op-ssh-sign\"|")"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "signingkey = key::ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO9Rsn" ]]
}

@test "signing: works outside WSL too (signer override on any platform)" {
	_skip_without_chezmoi
	local cfg
	# Before this branch, gitSigningKey was only honoured when wsl was true, so
	# a native Windows or macOS workstation silently got no signing at all.
	cfg="$(_config \
		's|^  wsl: .*|  wsl: false|' \
		's|^  useYubiKey: .*|  useYubiKey: false|' \
		's|^  gitSigningKey: .*|  gitSigningKey: "ssh-ed25519 AAAATESTKEY"|' \
		"s|^  opSshSignProgram: .*|  opSshSignProgram: \"${TEST_DIR}/op-ssh-sign\"|")"
	run _render "${cfg}" "${REPO_ROOT}/home/dot_config/git/config.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "gpgsign = true" ]]
	[[ "$output" =~ "format = ssh" ]]
}

@test "signing: the public signing key ships as a default" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/fresh.yaml"
	printf '{}\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 ' ]]
}

@test "signing: an existing empty value still picks up the default" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/empty-key.yaml"
	# A config written by an earlier init already carries gitSigningKey: "",
	# so `hasKey` would be permanently true and the default never apply.
	printf 'data:\n  gitSigningKey: ""\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 ' ]]
}

@test "signing: a work machine gets the work default key" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/work.yaml"
	_fake_dsregcmd Microsoft
	printf '{}\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "isWork: true" ]]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHf9KPQ4uBdDqzZFrKyE1ugMJBee1XXVZwLLUKklNQV"' ]]
}

@test "signing: a non-work machine gets the personal default key" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/personal.yaml"
	_fake_dsregcmd Contoso
	printf '{}\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ "isWork: false" ]]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO9RsnZlHiWrFkVf9iUaAH1Jb/6G9bCREjpjG2izEu99"' ]]
}

@test "op-agent: the agent config enables the work vault on a work machine" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/agent-work.yaml"
	_fake_dsregcmd Microsoft
	printf '{}\n' >"${pre}"
	chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl" >"${TEST_DIR}/agent-work-cfg.yaml"
	run _render "${TEST_DIR}/agent-work-cfg.yaml" "${AGENT_TMPL}"
	[ "$status" -eq 0 ]
	[[ "$output" =~ '[[ssh-keys]]' ]]
	[[ "$output" =~ 'vault = "Microsoft"' ]]
}

@test "op-agent: the agent config enables Private on a personal machine" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/agent-personal.yaml"
	_fake_dsregcmd Contoso
	printf '{}\n' >"${pre}"
	chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl" >"${TEST_DIR}/agent-personal-cfg.yaml"
	run _render "${TEST_DIR}/agent-personal-cfg.yaml" "${AGENT_TMPL}"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'vault = "Private"' ]]
}

@test "op-agent: a custom vault name overrides the default" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/agent-custom.yaml"
	_fake_dsregcmd Microsoft
	printf 'data:\n  opSshVault: "My Custom Vault"\n' >"${pre}"
	chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl" >"${TEST_DIR}/agent-custom-cfg.yaml"
	run _render "${TEST_DIR}/agent-custom-cfg.yaml" "${AGENT_TMPL}"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'vault = "My Custom Vault"' ]]
}

@test "op-agent: never enables zero keys, which is what breaks the agent" {
	_skip_without_chezmoi
	local cfg
	cfg="$(_config)"
	run _render "${cfg}" "${AGENT_TMPL}"
	[ "$status" -eq 0 ]
	# A bare `ssh-keys = []` means no identities at all; it may only ever appear
	# inside the explanatory comment block.
	[[ ! "$output" =~ $'\nssh-keys = []' ]]
	[[ "$output" =~ '[[ssh-keys]]' ]]
}

@test "op-agent: the agent config is Windows-only" {
	_skip_without_chezmoi
	# AppData is ignored off Windows, so a Linux/macOS apply must not try to
	# write a Windows-shaped path into $HOME.
	run chezmoi ignored --source="${REPO_ROOT}/home"
	[ "$status" -eq 0 ]
	if [ "$(uname -s)" != "Darwin" ]; then
		[[ "$output" =~ "AppData" ]]
	fi
}

@test "signing: a persisted shipped default is re-picked per machine" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/stale-default.yaml"
	# A config written before the work key existed carries the personal default;
	# that is not a real override, so a work machine must still get the work key.
	_fake_dsregcmd Microsoft
	printf 'data:\n  gitSigningKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO9RsnZlHiWrFkVf9iUaAH1Jb/6G9bCREjpjG2izEu99"\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init \
		<"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINHf9KPQ4uBdDqzZFrKyE1ugMJBee1XXVZwLLUKklNQV"' ]]
}

@test "signing: a per-machine key overrides the default" {
	_skip_without_chezmoi
	local pre="${TEST_DIR}/other-key.yaml"
	printf 'data:\n  gitSigningKey: "ssh-ed25519 OTHERKEY someone@example.com"\n' >"${pre}"
	run chezmoi --config "${pre}" execute-template --init <"${REPO_ROOT}/home/.chezmoi.yaml.tmpl"
	[ "$status" -eq 0 ]
	[[ "$output" =~ 'gitSigningKey: "ssh-ed25519 OTHERKEY someone@example.com"' ]]
}
