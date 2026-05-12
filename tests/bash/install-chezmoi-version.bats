#!/usr/bin/env bats
# Tests for install.sh chezmoi version handling

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	FAKE_HOME="${BATS_TEST_TMPDIR}/home"
	FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
	NO_MANAGER_BIN="${BATS_TEST_TMPDIR}/no-manager-bin"
	CHEZMOI_RUN_LOG="${BATS_TEST_TMPDIR}/chezmoi-run.log"
	MISE_LOG="${BATS_TEST_TMPDIR}/mise.log"
	REQUIRED_VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/home/.chezmoiversion")"
	export FAKE_HOME FAKE_BIN NO_MANAGER_BIN CHEZMOI_RUN_LOG MISE_LOG REQUIRED_VERSION

	mkdir -p "$FAKE_HOME" "$FAKE_BIN" "$NO_MANAGER_BIN"

	cat >"${FAKE_BIN}/chezmoi" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	printf 'chezmoi version %s\n' "${CHEZMOI_FAKE_VERSION:-0.0.0}"
	exit 0
fi
{
	printf 'source=path\n'
	printf 'version=%s\n' "${CHEZMOI_FAKE_VERSION:-0.0.0}"
	printf 'args=%s\n' "$*"
} >"${CHEZMOI_RUN_LOG}"
EOF
	chmod +x "${FAKE_BIN}/chezmoi"
	cp "${FAKE_BIN}/chezmoi" "${NO_MANAGER_BIN}/chezmoi"

	cat >"${FAKE_BIN}/mise" <<'EOF'
#!/bin/sh
if [ "${1:-}" = "which" ] && [ "${2:-}" = "chezmoi" ]; then
	printf '%s\n' "${HOME}/.local/bin/chezmoi"
	exit 0
fi
printf '%s\n' "$*" >"${MISE_LOG}"
mkdir -p "${HOME}/.local/bin"
cat >"${HOME}/.local/bin/chezmoi" <<'EOS'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	printf 'chezmoi version %s\n' "${REQUIRED_VERSION}"
	exit 0
fi
{
	printf 'source=mise\n'
	printf 'version=%s\n' "${REQUIRED_VERSION}"
	printf 'args=%s\n' "$*"
} >"${CHEZMOI_RUN_LOG}"
EOS
chmod +x "${HOME}/.local/bin/chezmoi"
EOF
	chmod +x "${FAKE_BIN}/mise"
}

@test "install.sh installs required chezmoi with mise when existing version is too old" {
	run env \
		HOME="$FAKE_HOME" \
		PATH="${FAKE_BIN}:/usr/bin:/bin" \
		CHEZMOI_FAKE_VERSION="0.0.1" \
		CHEZMOI_RUN_LOG="$CHEZMOI_RUN_LOG" \
		MISE_LOG="$MISE_LOG" \
		REQUIRED_VERSION="$REQUIRED_VERSION" \
		"$REPO_ROOT/home/install.sh"

	[ "$status" -eq 0 ]
	grep -q "use --global chezmoi@${REQUIRED_VERSION}" "$MISE_LOG"
	grep -q "source=mise" "$CHEZMOI_RUN_LOG"
	grep -q "args=init --apply --no-tty --force --source=${REPO_ROOT}/home" "$CHEZMOI_RUN_LOG"
}

@test "install.sh keeps existing chezmoi when it satisfies .chezmoiversion" {
	run env \
		HOME="$FAKE_HOME" \
		PATH="${FAKE_BIN}:/usr/bin:/bin" \
		CHEZMOI_FAKE_VERSION="$REQUIRED_VERSION" \
		CHEZMOI_RUN_LOG="$CHEZMOI_RUN_LOG" \
		MISE_LOG="$MISE_LOG" \
		REQUIRED_VERSION="$REQUIRED_VERSION" \
		"$REPO_ROOT/home/install.sh"

	[ "$status" -eq 0 ]
	[ ! -f "$MISE_LOG" ]
	grep -q "source=path" "$CHEZMOI_RUN_LOG"
	grep -q "version=${REQUIRED_VERSION}" "$CHEZMOI_RUN_LOG"
}

@test ".mise.toml chezmoi pin matches .chezmoiversion" {
	run awk -F\" '/^chezmoi = / { print $2 }' "${REPO_ROOT}/.mise.toml"

	[ "$status" -eq 0 ]
	[ "$output" = "$REQUIRED_VERSION" ]
}

@test "renovate tracks both chezmoi version pins" {
	renovate_config="$(cat "${REPO_ROOT}/renovate.json5")"

	printf '%s\n' "$renovate_config" | grep -qF 'managerFilePatterns: ["/(^|/)\\.chezmoiversion$/"]'
	printf '%s\n' "$renovate_config" | grep -qF 'matchStrings: ["^(?<currentValue>\\S+)\\s*$"]'
	printf '%s\n' "$renovate_config" | grep -qF 'managerFilePatterns: ["/(^|/)\\.mise\\.toml$/"]'
	printf '%s\n' "$renovate_config" | grep -qF 'matchStrings: ["chezmoi\\s*=\\s*\"(?<currentValue>[^\"]+)\""]'
}

@test "install.sh does not use unpinned chezmoi installer paths" {
	run grep -E "chezmoi@latest|get\\.chezmoi\\.io|mise use --global chezmoi([[:space:]]|$)" "${REPO_ROOT}/home/install.sh"

	[ "$status" -ne 0 ]
}

@test "install.sh errors when required version is unavailable from package managers" {
	run env \
		HOME="$FAKE_HOME" \
		PATH="${NO_MANAGER_BIN}:/usr/bin:/bin" \
		CHEZMOI_FAKE_VERSION="0.0.1" \
		CHEZMOI_RUN_LOG="$CHEZMOI_RUN_LOG" \
		REQUIRED_VERSION="$REQUIRED_VERSION" \
		"$REPO_ROOT/home/install.sh"

	[ "$status" -ne 0 ]
	printf '%s' "$output" | grep -qF "No supported package manager can provide chezmoi ${REQUIRED_VERSION} or later."
	[ ! -f "$CHEZMOI_RUN_LOG" ]
}
