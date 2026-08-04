#!/usr/bin/env bats
# Tests for the fastfetch status.sh cached-status script.
#
# The script lives at home/dot_config/fastfetch/executable_status.sh and is
# applied by chezmoi to ~/.config/fastfetch/status.sh. It powers the extra
# "Updates", "Reboot" and "Ansible" fastfetch modules.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	SCRIPT="${REPO_ROOT}/home/dot_config/fastfetch/executable_status.sh"
	export SCRIPT

	# Isolated cache + a bin dir for command mocks, prepended to PATH.
	XDG_CACHE_HOME="$(mktemp -d)"
	export XDG_CACHE_HOME
	TEST_BIN_DIR="$(mktemp -d)"
	export TEST_BIN_DIR
	ORIGINAL_PATH="${PATH}"
	export ORIGINAL_PATH

	# Point ansible detection at an empty (unmanaged) dir by default.
	ANSIBLE_PULL_WORKDIR="$(mktemp -d)"
	export ANSIBLE_PULL_WORKDIR
}

teardown() {
	export PATH="${ORIGINAL_PATH}"
	for d in "${XDG_CACHE_HOME}" "${TEST_BIN_DIR}" "${ANSIBLE_PULL_WORKDIR}"; do
		[ -n "${d}" ] && [ -d "${d}" ] && rm -rf "${d}"
	done
}

# Write a mock command into TEST_BIN_DIR and put it first on PATH.
_mock() {
	local name="$1"
	cat >"${TEST_BIN_DIR}/${name}"
	chmod +x "${TEST_BIN_DIR}/${name}"
	export PATH="${TEST_BIN_DIR}:${ORIGINAL_PATH}"
}

@test "fastfetch-status: script exists and is executable" {
	[ -f "${SCRIPT}" ]
	[ -x "${SCRIPT}" ]
}

@test "fastfetch-status: has valid bash syntax" {
	run bash -n "${SCRIPT}"
	[ "$status" -eq 0 ]
}

@test "fastfetch-status: help option displays usage" {
	run bash "${SCRIPT}" --help
	[ "$status" -eq 0 ]
	[[ "$output" =~ "Usage: status.sh" ]]
	[[ "$output" =~ "updates" ]]
	[[ "$output" =~ "ansible" ]]
}

@test "fastfetch-status: unknown command returns error" {
	run bash "${SCRIPT}" bogus
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Unknown command" ]]
}

@test "fastfetch-status: no command prints usage and fails" {
	run bash "${SCRIPT}"
	[ "$status" -eq 1 ]
	[[ "$output" =~ "Usage: status.sh" ]]
}

@test "fastfetch-status: refresh creates cache and timestamp" {
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	[ -f "${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at" ]
}

@test "fastfetch-status: section emits cached value" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	printf 'cached-line\n' >"${XDG_CACHE_HOME}/fastfetch-status/updates"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"

	run bash "${SCRIPT}" updates
	[ "$status" -eq 0 ]
	[[ "$output" =~ "cached-line" ]]
}

@test "fastfetch-status: missing section prints nothing (hides fastfetch line)" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"

	run bash "${SCRIPT}" reboot
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "fastfetch-status: FASTFETCH_STATUS_DISABLE silences all sections" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	printf 'cached-line\n' >"${XDG_CACHE_HOME}/fastfetch-status/updates"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"

	run env FASTFETCH_STATUS_DISABLE=1 bash "${SCRIPT}" updates
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "fastfetch-status: counts available apt updates" {
	_mock apt-get <<'EOF'
#!/bin/bash
cat <<'PKGS'
Inst bash [5.2] (5.2.15 Debian:13 [arm64])
Inst coreutils [9.1] (9.4-3 Debian:13 [arm64])
PKGS
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	run cat "${XDG_CACHE_HOME}/fastfetch-status/updates"
	[[ "$output" =~ "2 update(s) available (apt)" ]]
}

@test "fastfetch-status: updates line reports when it was calculated" {
	_mock apt-get <<'EOF'
#!/bin/bash
echo 'Inst bash [5.2] (5.2.15 Debian:13 [arm64])'
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]

	# Stored as an absolute epoch token so the age keeps advancing between
	# refreshes rather than freezing at "checked 0s ago".
	run cat "${XDG_CACHE_HOME}/fastfetch-status/updates"
	[[ "$output" =~ checked\ @ago:[0-9]+@ ]]

	run bash "${SCRIPT}" updates
	[ "$status" -eq 0 ]
	# Any small age is fine: asserting exactly "0s" makes the test fail
	# whenever the refresh above happens to straddle a second boundary.
	[[ "$output" =~ checked\ [0-9]+s\ ago ]]
}

@test "fastfetch-status: no apt updates leaves updates section empty" {
	_mock apt-get <<'EOF'
#!/bin/bash
echo "Reading package lists..."
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	[ ! -f "${XDG_CACHE_HOME}/fastfetch-status/updates" ]
}

@test "fastfetch-status: counts outdated brew packages (macOS/Linuxbrew)" {
	# Build a minimal PATH with only coreutils + a mock brew so the Linux
	# package managers are treated as absent and the brew branch is used.
	local t
	for t in bash mkdir date grep tr sed mv rm rmdir stat cat; do
		ln -sf "$(command -v "${t}")" "${TEST_BIN_DIR}/${t}"
	done
	cat >"${TEST_BIN_DIR}/brew" <<'EOF'
#!/bin/bash
# mock `brew outdated --quiet`
printf 'wget\nneovim\nfastfetch\n'
EOF
	chmod +x "${TEST_BIN_DIR}/brew"

	PATH="${TEST_BIN_DIR}" run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	run cat "${XDG_CACHE_HOME}/fastfetch-status/updates"
	[[ "$output" =~ "3 update(s) available (brew)" ]]
}

@test "fastfetch-status: reports ansible-pull success from systemd" {
	_mock systemctl <<'EOF'
#!/bin/bash
unit=""; prop=""
while [ $# -gt 0 ]; do
	case "$1" in
	show) shift ;;
	-p) prop="$2"; shift 2 ;;
	--value) shift ;;
	*) [ -z "$unit" ] && unit="$1"; shift ;;
	esac
done
case "${unit}:${prop}" in
ansible-pull.service:LoadState) echo loaded ;;
ansible-pull.service:ActiveState) echo inactive ;;
ansible-pull.service:Result) echo success ;;
ansible-pull.service:ExecMainStatus) echo 0 ;;
ansible-pull.service:InactiveEnterTimestamp) date -d '10 minutes ago' ;;
ansible-pull.timer:NextElapseUSecRealtime) echo $(( ($(date +%s) + 1800) * 1000000 )) ;;
*) echo "" ;;
esac
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	# The cache stores absolute epoch tokens, not pre-rendered durations.
	run cat "${XDG_CACHE_HOME}/fastfetch-status/ansible"
	[[ "$output" =~ ran\ @ago:[0-9]+@ ]]
	[[ "$output" =~ next\ @in:[0-9]+@ ]]
	# ... and definitely not a duration that would freeze until the next refresh.
	[[ ! "$output" =~ [0-9]+[smhd]\ ago ]]
	# Emitting expands them against the current clock.
	run bash "${SCRIPT}" ansible
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ansible-pull OK" ]]
	[[ "$output" =~ "ran 10m ago" ]]
	[[ "$output" =~ "next in" ]]
}

@test "fastfetch-status: relative times advance without a cache refresh" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"
	printf 'ansible-pull OK \302\267 ran @ago:%s@\n' "$(($(date +%s) - 3540))" \
		>"${XDG_CACHE_HOME}/fastfetch-status/ansible"

	run bash "${SCRIPT}" ansible
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ran 59m ago" ]]

	# Same cache file, later clock -> a different rendered duration.
	printf 'ansible-pull OK \302\267 ran @ago:%s@\n' "$(($(date +%s) - 3660))" \
		>"${XDG_CACHE_HOME}/fastfetch-status/ansible"
	run bash "${SCRIPT}" ansible
	[ "$status" -eq 0 ]
	[[ "$output" =~ "ran 1h ago" ]]
}

@test "fastfetch-status: elapsed next-run token renders as due" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"
	printf 'ansible-pull OK \302\267 next @in:%s@\n' "$(($(date +%s) - 60))" \
		>"${XDG_CACHE_HOME}/fastfetch-status/ansible"

	run bash "${SCRIPT}" ansible
	[ "$status" -eq 0 ]
	[[ "$output" =~ "next due" ]]
}

@test "fastfetch-status: tokens expand to a bare duration phrase" {
	# The wording around a token belongs to the collector, so the same token
	# can read as "checked 5m ago" or "ran 5m ago" depending on the section.
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"
	printf 'checked @ago:%s@ \302\267 due @in:%s@\n' \
		"$(($(date +%s) - 300))" "$(($(date +%s) + 600))" \
		>"${XDG_CACHE_HOME}/fastfetch-status/updates"

	run bash "${SCRIPT}" updates
	[ "$status" -eq 0 ]
	[[ "$output" =~ "checked 5m ago" ]]
	[[ "$output" =~ "due in 10m" ]]
	[[ ! "$output" =~ "ran " ]]
}

@test "fastfetch-status: lines without tokens are emitted verbatim" {
	mkdir -p "${XDG_CACHE_HOME}/fastfetch-status"
	: >"${XDG_CACHE_HOME}/fastfetch-status/.refreshed-at"
	printf 'user@host \302\267 @nope:1@ \302\267 100%% done\n' \
		>"${XDG_CACHE_HOME}/fastfetch-status/updates"

	run bash "${SCRIPT}" updates
	[ "$status" -eq 0 ]
	[[ "$output" =~ "user@host" ]]
	[[ "$output" =~ "@nope:1@" ]]
	[[ "$output" =~ "100% done" ]]
}

@test "fastfetch-status: reports ansible-pull failure from systemd" {
	_mock systemctl <<'EOF'
#!/bin/bash
unit=""; prop=""
while [ $# -gt 0 ]; do
	case "$1" in
	show) shift ;;
	-p) prop="$2"; shift 2 ;;
	--value) shift ;;
	*) [ -z "$unit" ] && unit="$1"; shift ;;
	esac
done
case "${unit}:${prop}" in
ansible-pull.service:LoadState) echo loaded ;;
ansible-pull.service:ActiveState) echo inactive ;;
ansible-pull.service:Result) echo exit-code ;;
ansible-pull.service:ExecMainStatus) echo 2 ;;
ansible-pull.service:InactiveEnterTimestamp) date -d '2 hours ago' ;;
*) echo "" ;;
esac
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	run cat "${XDG_CACHE_HOME}/fastfetch-status/ansible"
	[[ "$output" =~ "ansible-pull FAILED (exit 2)" ]]
}

@test "fastfetch-status: unmanaged host omits ansible section" {
	_mock systemctl <<'EOF'
#!/bin/bash
# Report the unit as absent for every query.
echo ""
EOF
	run bash "${SCRIPT}" refresh
	[ "$status" -eq 0 ]
	[ ! -f "${XDG_CACHE_HOME}/fastfetch-status/ansible" ]
}
