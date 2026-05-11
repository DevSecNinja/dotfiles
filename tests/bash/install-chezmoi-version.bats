#!/usr/bin/env bats
# Tests for install.sh chezmoi version handling

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	FAKE_HOME="${BATS_TEST_TMPDIR}/home"
	FAKE_BIN="${BATS_TEST_TMPDIR}/bin"
	CHEZMOI_RUN_LOG="${BATS_TEST_TMPDIR}/chezmoi-run.log"
	INSTALLER_LOG="${BATS_TEST_TMPDIR}/installer.log"
	FAKE_INSTALLER_SCRIPT="${BATS_TEST_TMPDIR}/fake-installer.sh"
	REQUIRED_VERSION="$(tr -d '[:space:]' <"${REPO_ROOT}/home/.chezmoiversion")"
	export FAKE_HOME FAKE_BIN CHEZMOI_RUN_LOG INSTALLER_LOG FAKE_INSTALLER_SCRIPT REQUIRED_VERSION

	mkdir -p "$FAKE_HOME" "$FAKE_BIN"

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

	cat >"$FAKE_INSTALLER_SCRIPT" <<'EOF'
#!/bin/sh
bindir=
tag=
while [ "$#" -gt 0 ]; do
	case "$1" in
	-b)
		bindir="$2"
		shift 2
		;;
	-t)
		tag="$2"
		shift 2
		;;
	*)
		shift
		;;
	esac
done
printf 'bindir=%s\ntag=%s\n' "$bindir" "$tag" >"${INSTALLER_LOG}"
mkdir -p "$bindir"
cat >"${bindir}/chezmoi" <<'EOS'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then
	printf 'chezmoi version %s\n' "${REQUIRED_VERSION}"
	exit 0
fi
{
	printf 'source=installer\n'
	printf 'version=%s\n' "${REQUIRED_VERSION}"
	printf 'args=%s\n' "$*"
} >"${CHEZMOI_RUN_LOG}"
EOS
chmod +x "${bindir}/chezmoi"
EOF
	chmod +x "$FAKE_INSTALLER_SCRIPT"

	cat >"${FAKE_BIN}/curl" <<'EOF'
#!/bin/sh
cat "${FAKE_INSTALLER_SCRIPT}"
EOF
	chmod +x "${FAKE_BIN}/curl"
}

@test "install.sh installs required chezmoi when existing version is too old" {
	run env \
		HOME="$FAKE_HOME" \
		PATH="${FAKE_BIN}:/usr/bin:/bin" \
		CHEZMOI_FAKE_VERSION="0.0.1" \
		CHEZMOI_RUN_LOG="$CHEZMOI_RUN_LOG" \
		INSTALLER_LOG="$INSTALLER_LOG" \
		FAKE_INSTALLER_SCRIPT="$FAKE_INSTALLER_SCRIPT" \
		REQUIRED_VERSION="$REQUIRED_VERSION" \
		"$REPO_ROOT/home/install.sh"

	[ "$status" -eq 0 ]
	grep -q "tag=v${REQUIRED_VERSION}" "$INSTALLER_LOG"
	grep -q "source=installer" "$CHEZMOI_RUN_LOG"
	grep -q "args=init --apply --no-tty --force --source=${REPO_ROOT}/home" "$CHEZMOI_RUN_LOG"
}

@test "install.sh keeps existing chezmoi when it satisfies .chezmoiversion" {
	run env \
		HOME="$FAKE_HOME" \
		PATH="${FAKE_BIN}:/usr/bin:/bin" \
		CHEZMOI_FAKE_VERSION="$REQUIRED_VERSION" \
		CHEZMOI_RUN_LOG="$CHEZMOI_RUN_LOG" \
		INSTALLER_LOG="$INSTALLER_LOG" \
		FAKE_INSTALLER_SCRIPT="$FAKE_INSTALLER_SCRIPT" \
		REQUIRED_VERSION="$REQUIRED_VERSION" \
		"$REPO_ROOT/home/install.sh"

	[ "$status" -eq 0 ]
	[ ! -f "$INSTALLER_LOG" ]
	grep -q "source=path" "$CHEZMOI_RUN_LOG"
	grep -q "version=${REQUIRED_VERSION}" "$CHEZMOI_RUN_LOG"
}
