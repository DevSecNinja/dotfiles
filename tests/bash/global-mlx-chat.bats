#!/usr/bin/env bats

setup() {
	REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
	TEST_HOME="$BATS_TEST_TMPDIR/home with spaces"
	mkdir -p "$BATS_TEST_TMPDIR/External Disk Data"
	export MLX_TEST_VOLUME
	MLX_TEST_VOLUME="$(cd "$BATS_TEST_TMPDIR/External Disk Data" && pwd -P)"
	CACHE_DIR="$MLX_TEST_VOLUME/AI/huggingface"
	export MOCK_OS=Darwin MOCK_ARCH=arm64 MOCK_MOUNTED=1 MOCK_BASE_PYTHON=1
	export PYTHON_CALLS="$BATS_TEST_TMPDIR/python-calls"
	export MLX_TEST_ACTIONS="$BATS_TEST_TMPDIR/actions"
	export MLX_TEST_STATE="$BATS_TEST_TMPDIR/state"
	export MLX_TEST_PYTHON="$BATS_TEST_TMPDIR/venv-python"
	export MLX_TEST_BREW="$BATS_TEST_TMPDIR/homebrew"
	printf 'ready\n' >"$MLX_TEST_STATE"
	mkdir -p "$TEST_HOME/mlx-qwen/.venv/bin" "$TEST_HOME/.config/mlx" \
		"$CACHE_DIR/hub" "$CACHE_DIR/xet" "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/work"
	cp "$REPO_ROOT/home/Taskfile.yml" "$TEST_HOME/Taskfile.yml"
	cp "$REPO_ROOT/home/dot_config/mlx/chat.py" "$TEST_HOME/.config/mlx/chat.py"
	cat >"$MLX_TEST_PYTHON" <<'EOF'
#!/bin/sh
case "$*" in
	*"--check-env"*)
		printf 'check-env\n' >>"$MLX_TEST_ACTIONS"
		test "$(cat "$MLX_TEST_STATE")" = ready
		exit "$?"
		;;
	"-c "*)
		printf 'check-venv\n' >>"$MLX_TEST_ACTIONS"
		exit "${MOCK_VENV_EXIT:-0}"
		;;
	"-m pip --version")
		printf 'check-pip\n' >>"$MLX_TEST_ACTIONS"
		exit "${MOCK_PIP_EXIT:-0}"
		;;
	"-m ensurepip")
		printf 'ensurepip\n' >>"$MLX_TEST_ACTIONS"
		exit 0
		;;
	"-m pip "*)
		printf 'pip: %s\n' "$*" >>"$MLX_TEST_ACTIONS"
		printf 'tmp: %s\n' "$TMPDIR" >>"$MLX_TEST_ACTIONS"
		[ "${MOCK_INSTALL_EXIT:-0}" -eq 0 ] || exit "$MOCK_INSTALL_EXIT"
		[ "${MOCK_STILL_BROKEN:-0}" -eq 1 ] || printf 'ready\n' >"$MLX_TEST_STATE"
		exit 0
		;;
esac
printf 'chat\n' >>"$MLX_TEST_ACTIONS"
printf '<%s>\n' "$@" >"$PYTHON_CALLS"
exit "${MOCK_PYTHON_EXIT:-0}"
EOF
	chmod +x "$MLX_TEST_PYTHON"
	cp "$MLX_TEST_PYTHON" "$TEST_HOME/mlx-qwen/.venv/bin/python"
	cat >"$BATS_TEST_TMPDIR/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
	-s) printf '%s\n' "$MOCK_OS" ;;
	-m) printf '%s\n' "$MOCK_ARCH" ;;
	*) exit 1 ;;
esac
EOF
	cat >"$BATS_TEST_TMPDIR/bin/mount" <<'EOF'
#!/bin/sh
printf 'mount\n' >>"$MLX_TEST_ACTIONS"
[ "$MOCK_MOUNTED" -eq 1 ] || exit 0
printf '/dev/mock on %s (apfs, local)\n' "$MLX_TEST_VOLUME"
EOF
	cat >"$BATS_TEST_TMPDIR/bin/python3" <<'EOF'
#!/bin/sh
case "$1" in
	-c)
		case "$0" in "$MLX_TEST_BREW"/*) exit 0 ;; esac
		[ "$MOCK_BASE_PYTHON" -eq 1 ] || exit 1
		;;
	-m)
		[ "$2" = venv ] || exit 1
		printf 'create-venv\n' >>"$MLX_TEST_ACTIONS"
		mkdir -p "$3/bin"
		cp "$MLX_TEST_PYTHON" "$3/bin/python"
		;;
	*) exit 1 ;;
esac
EOF
	cat >"$BATS_TEST_TMPDIR/bin/brew" <<'EOF'
#!/bin/sh
case "$*" in
	"--prefix python@3") printf '%s\n' "$MLX_TEST_BREW" ;;
	"list --versions python@3") test -f "$MLX_TEST_BREW/libexec/bin/python3" ;;
	"install python@3")
		printf 'install-python\n' >>"$MLX_TEST_ACTIONS"
		mkdir -p "$MLX_TEST_BREW/libexec/bin"
		cp "$(dirname "$0")/python3" "$MLX_TEST_BREW/libexec/bin/python3"
		;;
	*) exit 1 ;;
esac
EOF
	chmod +x "$BATS_TEST_TMPDIR/bin/uname" "$BATS_TEST_TMPDIR/bin/mount" \
		"$BATS_TEST_TMPDIR/bin/python3" "$BATS_TEST_TMPDIR/bin/brew"
}

global_task() {
	local task_bin
	task_bin="$(command -v task)" || return
	cd "$BATS_TEST_TMPDIR/work" || return
	HOME="$TEST_HOME" PATH="$BATS_TEST_TMPDIR/bin:${MLX_TEST_PATH:-$PATH}" \
		"$task_bin" --global "$@" "MLX_CACHE_DIR=$CACHE_DIR" "MLX_VOLUME=$MLX_TEST_VOLUME"
}

@test "global-mlx-chat: Python behavior is validated without MLX or model weights" {
	command -v python3 >/dev/null || skip "Python 3 not installed"
	run python3 -B -m unittest discover -s "$REPO_ROOT/tests/python" -p test_mlx_chat.py
	[ "$status" -eq 0 ]
}

@test "global-mlx-chat: global task works outside the repository with spaces in paths" {
	command -v task >/dev/null || skip "Task not installed"
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[ "$(cat "$PYTHON_CALLS")" = "<$TEST_HOME/.config/mlx/chat.py>
<--cache-dir>
<$CACHE_DIR>
<--volume>
<$MLX_TEST_VOLUME>" ]
	[ "$(cat "$MLX_TEST_ACTIONS")" = "mount
check-env
chat" ]
}

@test "global-mlx-chat: listing tasks does not require the venv or external SSD" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python"
	rmdir "$CACHE_DIR/hub" "$CACHE_DIR/xet"
	export MOCK_OS=Linux MOCK_ARCH=x86_64
	run global_task --list
	[ "$status" -eq 0 ]
	[[ "$output" == *"llm:chat"* ]]
	[ ! -e "$PYTHON_CALLS" ]
	[ ! -e "$MLX_TEST_ACTIONS" ]
}

@test "global-mlx-chat: available Bash, Zsh, and Fish shells use the same global command" {
	command -v task >/dev/null || skip "Task not installed"
	local shell shell_bin task_bin options
	task_bin="$(command -v task)"
	cd "$BATS_TEST_TMPDIR/work"
	for shell in bash zsh fish; do
		shell_bin="$(command -v "$shell")" || continue
		case "$shell" in
			bash) options=(--noprofile --norc) ;;
			zsh) options=(-f) ;;
			fish) options=(--no-config) ;;
		esac
		run env HOME="$TEST_HOME" PATH="$BATS_TEST_TMPDIR/bin:$PATH" \
			MLX_TEST_TASK="$task_bin" MLX_TEST_CACHE_DIR="$CACHE_DIR" \
			"$shell_bin" "${options[@]}" -c \
			'"$MLX_TEST_TASK" --global llm:chat "MLX_CACHE_DIR=$MLX_TEST_CACHE_DIR" "MLX_VOLUME=$MLX_TEST_VOLUME"'
		[ "$status" -eq 0 ]
		[ "$(cat "$PYTHON_CALLS")" = "<$TEST_HOME/.config/mlx/chat.py>
<--cache-dir>
<$CACHE_DIR>
<--volume>
<$MLX_TEST_VOLUME>" ]
	done
}

@test "global-mlx-chat: unsupported systems fail explicitly before starting Python" {
	command -v task >/dev/null || skip "Task not installed"
	for MOCK_OS in Linux Darwin Windows; do
		export MOCK_OS MOCK_ARCH=x86_64
		run global_task llm:chat
		[ "$status" -ne 0 ]
		[[ "$output" == *"requires native Apple Silicon"* ]]
		[ ! -e "$PYTHON_CALLS" ]
	done
}

@test "global-mlx-chat: broken existing venv is not overwritten" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python"
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"Repair it or move it aside"* ]]
	[ -d "$TEST_HOME/mlx-qwen/.venv" ]
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: disconnected SSD fails instead of using an internal cache" {
	command -v task >/dev/null || skip "Task not installed"
	export MOCK_MOUNTED=0
	printf 'missing\n' >"$MLX_TEST_STATE"
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"Connect the SSD"* ]]
	[ ! -e "$PYTHON_CALLS" ]
	[ "$(cat "$MLX_TEST_ACTIONS")" = mount ]
}

@test "global-mlx-chat: missing launcher gives selective deployment guidance" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/.config/mlx/chat.py"
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"Apply the global Taskfile and launcher together"* ]]
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: Python errors propagate through Task" {
	command -v task >/dev/null || skip "Task not installed"
	export MOCK_PYTHON_EXIT=23
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"exit status 23"* ]]
}

@test "global-mlx-chat: missing venv is created once and working installs are not upgraded" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python"
	rmdir "$TEST_HOME/mlx-qwen/.venv/bin" "$TEST_HOME/mlx-qwen/.venv"
	printf 'missing\n' >"$MLX_TEST_STATE"
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[[ "$(cat "$MLX_TEST_ACTIONS")" == mount*create-venv*pip:*check-env*chat ]]
	grep -F -- "--isolated --require-virtualenv" "$MLX_TEST_ACTIONS"
	grep -F -- "--cache-dir $CACHE_DIR/pip install mlx-lm>=0.32.2" "$MLX_TEST_ACTIONS"
	grep -F -- "tmp: $CACHE_DIR/tmp" "$MLX_TEST_ACTIONS"
	! grep -F -- "--upgrade" "$MLX_TEST_ACTIONS"

	: >"$MLX_TEST_ACTIONS"
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[ "$(cat "$MLX_TEST_ACTIONS")" = "mount
check-env
chat" ]
}

@test "global-mlx-chat: missing packages and pip are installed into the existing venv" {
	command -v task >/dev/null || skip "Task not installed"
	printf 'missing\n' >"$MLX_TEST_STATE"
	export MOCK_PIP_EXIT=1
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[[ "$(cat "$MLX_TEST_ACTIONS")" == *check-pip*ensurepip*pip:*check-env*chat ]]
	! grep -F -- "create-venv" "$MLX_TEST_ACTIONS"
	! grep -F -- "install-python" "$MLX_TEST_ACTIONS"
}

@test "global-mlx-chat: unusable packages after pip fail the post-install check" {
	command -v task >/dev/null || skip "Task not installed"
	printf 'broken\n' >"$MLX_TEST_STATE"
	export MOCK_STILL_BROKEN=1
	run global_task llm:chat
	[ "$status" -ne 0 ]
	grep -F -- "pip:" "$MLX_TEST_ACTIONS"
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: pip failures stop before model launch" {
	command -v task >/dev/null || skip "Task not installed"
	printf 'missing\n' >"$MLX_TEST_STATE"
	export MOCK_INSTALL_EXIT=17
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"exit status 17"* ]]
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: missing base Python uses the repository Homebrew formula" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python"
	rmdir "$TEST_HOME/mlx-qwen/.venv/bin" "$TEST_HOME/mlx-qwen/.venv"
	printf 'missing\n' >"$MLX_TEST_STATE"
	export MOCK_BASE_PYTHON=0
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[[ "$(cat "$MLX_TEST_ACTIONS")" == mount*install-python*create-venv*pip:*chat ]]
}

@test "global-mlx-chat: absent Python and Homebrew are reported without unsafe bootstrap" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python" "$BATS_TEST_TMPDIR/bin/brew"
	rmdir "$TEST_HOME/mlx-qwen/.venv/bin" "$TEST_HOME/mlx-qwen/.venv"
	printf 'missing\n' >"$MLX_TEST_STATE"
	export MOCK_BASE_PYTHON=0 MLX_TEST_PATH=/usr/bin:/bin:/usr/sbin:/sbin
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"cannot safely bootstrap Homebrew"* ]]
	! grep -F -- "install-python" "$MLX_TEST_ACTIONS"
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: existing Homebrew Python is reused when PATH Python is unsuitable" {
	command -v task >/dev/null || skip "Task not installed"
	rm "$TEST_HOME/mlx-qwen/.venv/bin/python"
	rmdir "$TEST_HOME/mlx-qwen/.venv/bin" "$TEST_HOME/mlx-qwen/.venv"
	mkdir -p "$MLX_TEST_BREW/libexec/bin"
	cp "$BATS_TEST_TMPDIR/bin/python3" "$MLX_TEST_BREW/libexec/bin/python3"
	printf 'missing\n' >"$MLX_TEST_STATE"
	export MOCK_BASE_PYTHON=0
	run global_task llm:chat
	[ "$status" -eq 0 ]
	grep -F -- "create-venv" "$MLX_TEST_ACTIONS"
	! grep -F -- "install-python" "$MLX_TEST_ACTIONS"
}

@test "global-mlx-chat: cache outside the external volume is rejected before setup" {
	command -v task >/dev/null || skip "Task not installed"
	CACHE_DIR="$BATS_TEST_TMPDIR/internal"
	run global_task llm:chat
	[ "$status" -ne 0 ]
	[[ "$output" == *"must be a directory beneath MLX_VOLUME"* ]]
	[ ! -d "$CACHE_DIR" ]
	[ ! -e "$PYTHON_CALLS" ]
}

@test "global-mlx-chat: cache directories are initialized on a mounted SSD" {
	command -v task >/dev/null || skip "Task not installed"
	rmdir "$CACHE_DIR/hub" "$CACHE_DIR/xet"
	run global_task llm:chat
	[ "$status" -eq 0 ]
	[ -d "$CACHE_DIR/hub" ]
	[ -d "$CACHE_DIR/xet" ]
	[ -d "$CACHE_DIR/pip" ]
	[ -d "$CACHE_DIR/tmp" ]
}

@test "global-mlx-chat: documented selective Chezmoi deployment manages both files from a fresh home" {
	command -v chezmoi >/dev/null || skip "Chezmoi not installed"
	local chezmoi_bin deployment_home
	chezmoi_bin="$(command -v chezmoi)"
	deployment_home="$BATS_TEST_TMPDIR/fresh home"
	mkdir "$deployment_home"
	printf 'data: {}\n' >"$BATS_TEST_TMPDIR/chezmoi.yaml"
	[ ! -e "$deployment_home/.config" ]
	[ ! -e "$deployment_home/Taskfile.yml" ]

	mkdir -p "$deployment_home/.config/mlx"
	run env HOME="$deployment_home" "$chezmoi_bin" --config="$BATS_TEST_TMPDIR/chezmoi.yaml" \
		--destination="$deployment_home" --source="$REPO_ROOT" apply --exclude=scripts --dry-run --verbose \
		"$deployment_home/Taskfile.yml" "$deployment_home/.config/mlx/chat.py"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Taskfile.yml"* ]]
	[[ "$output" == *".config/mlx/chat.py"* ]]
	[[ "$output" == *"llm:chat"* ]]
	[ ! -e "$deployment_home/Taskfile.yml" ]
	[ ! -e "$deployment_home/.config/mlx/chat.py" ]

	run env HOME="$deployment_home" "$chezmoi_bin" --config="$BATS_TEST_TMPDIR/chezmoi.yaml" \
		--destination="$deployment_home" --source="$REPO_ROOT" apply --exclude=scripts \
		"$deployment_home/Taskfile.yml" "$deployment_home/.config/mlx/chat.py"
	[ "$status" -eq 0 ]
	cmp "$REPO_ROOT/home/Taskfile.yml" "$deployment_home/Taskfile.yml"
	cmp "$REPO_ROOT/home/dot_config/mlx/chat.py" "$deployment_home/.config/mlx/chat.py"
	[ ! -e "$deployment_home/.vimrc" ]
	[ ! -e "$deployment_home/.config/fish/config.fish" ]
	[ ! -e "$deployment_home/mlx-qwen" ]
	[ -x "$TEST_HOME/mlx-qwen/.venv/bin/python" ]
	[ -d "$CACHE_DIR/hub" ]
	[ ! -e "$PYTHON_CALLS" ]
	[ ! -e "$MLX_TEST_ACTIONS" ]
}
