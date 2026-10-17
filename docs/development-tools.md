# 🛠️ Development Tools

This repository includes [Task](https://taskfile.dev/) and
[mise](https://mise.jdx.dev/) for streamlined development.

## Task Runner

Task provides convenient commands for common operations:

```bash
# List all available tasks
task --list

# Install all dependencies (mise, go-task, Python packages)
task install:all

# Run all validation checks (required before commit)
task validate:all

# Run specific validations
task validate:chezmoi      # Validate Chezmoi config
task validate:shell        # Validate shell scripts
task validate:fish         # Validate Fish config

# Run tests
task test:all              # All tests
task test:chezmoi-apply    # Test Chezmoi apply

# Chezmoi operations
task chezmoi:init          # Preview changes (dry-run)
task chezmoi:diff          # Show differences
task chezmoi:verify        # Verify applied files

# Development setup
task dev:setup             # Complete dev environment setup

# CI tasks
task ci:validate           # Run CI validation pipeline
```

## Global Tasks

Chezmoi deploys `home/Taskfile.yml` to `~/Taskfile.yml`, separate from the
repository's development `Taskfile.yml`. With Task on your PATH, `task -g`
selects the home Taskfile from **any directory and shell**, including Fish,
Bash, Zsh, and PowerShell. Ordinary repository `task` commands stay unchanged.

```sh
task -g --list
task -g llm:chat
```

### Local MLX chat (Apple Silicon)

`llm:chat` uses Apple's `mlx-lm` Python API directly, not an inference frontend.
It requires native Apple Silicon macOS; other platforms get an explicit error
only if they invoke this task. A Task dependency checks prerequisites before
launch, installing only what is missing.

The default setup uses:

- `~/mlx-qwen/.venv/bin/python` with `mlx-lm` 0.32.2 or newer (developed against 0.32.2).
- The `mlx-community/Qwen3.5-9B-4bit` model in
  `/Volumes/External Disk Data/AI/huggingface/hub`.
- `/Volumes/External Disk Data/AI/huggingface/xet` on the same external SSD.

**Setup order:** native Apple Silicon and the mounted SSD are checked first.
Cache directories are created on that SSD and checked for writability and
symlink redirection. A `status` check then verifies the venv and imports the
required MLX APIs without loading weights. A working installation skips
provisioning entirely: no Python replacement, pip upgrade, or package upgrade.

If the venv is missing, Task creates it with native Python 3.10+ and `venv`.
If suitable Python is missing, it uses the same Homebrew `python@3` formula
as the repository's macOS package setup. Missing pip is bootstrapped with
`ensurepip`; missing requirements are installed with isolated
`python -m pip install 'mlx-lm>=0.32.2'`, without `--upgrade`. Pip and Homebrew
download caches, plus setup temporary files, stay on the SSD; the venv itself
remains at the configured `MLX_VENV` path. No uv or inference frontend is involved.
An existing broken/non-native venv is **not deleted**: repair it or move it
aside, then rerun. Installation failures and a failed post-install import
check stop the task before model launch; corrupt installed packages may
require manual repair rather than a forced reinstall.

The launcher at `~/.config/mlx/chat.py` sets `HF_HOME`, `HF_HUB_CACHE`, and
`HF_XET_CACHE` to the external cache, overriding inherited Hugging Face
settings. It first resolves the existing cached model without network access.
If absent, it downloads the model there (approximately 6 GB); existing cached
weights are reused, not copied or updated. There is no internal-disk fallback.
Connect the SSD first and run from a terminal permitted to access it (for
example Terminal.app); this does not bypass macOS volume permissions.

**Bootstrap boundary:** Task cannot install itself before the `task` command
exists. Full macOS dotfiles setup already includes `go-task` and Python. If
Task alone is missing, use the existing Homebrew setup and `brew install go-task`,
or your configured mise installation with `mise use --global task@latest`.
If neither suitable Python nor Homebrew is available, the task reports that
Homebrew must be installed through the existing dotfiles setup; it does not run
a new privileged bootstrap script.

Thinking is disabled via `enable_thinking=False` in the model's chat template,
which supplies an empty closed `<think>` block. The launcher uses temperature
0.7, top-p 0.8, top-k 20, at most 512 reply tokens, and 512-token prefill chunks.
It does not use the unsupported `mlx_lm.chat` flags or a `/nothink` soft switch.

Type `q` to quit, `r` to reset, or `h` for help. Ctrl+C (including during
generation) and EOF exit cleanly. Each reply reports token speed and peak MLX
memory; conversation state stays in memory, with no saved transcripts.
The prompt cache is reused across turns, including the correct end-of-turn
boundary after a truncated reply.

**Memory bound:** Qwen3.5's hybrid cache ignores `max_kv_size`. Instead, every
turn must fit within **8,192 total tokens**, counting cached history, the new
prompt and its delimiters, and 512 reserved reply tokens. Oversized turns are
rejected before generation: reset or shorten the input. History is never
silently discarded. This bounds context growth, not total process RAM;
the approximately 6 GB of weights and other applications still need memory.

### Selective deployment

Once these changes are present in your primary dotfiles checkout, run these
commands **from its repository root**. Only the global Taskfile and launcher
are selected; Chezmoi scripts are explicitly excluded, and neither the venv
nor model caches are managed by Git or Chezmoi.

Create the launcher's parent directory first. When selecting individual files,
Chezmoi 2.73.0 requires that parent to exist; a fresh home otherwise fails with
`stat .../.config/mlx: no such file or directory`. Use `--verbose` to display
the proposed changes during the dry-run:

```sh
mkdir -p "$HOME/.config/mlx" &&
  chezmoi --source=. apply --exclude=scripts --dry-run --verbose "$HOME/Taskfile.yml" "$HOME/.config/mlx/chat.py"
```

Review that preview first, especially if you already maintain a home Taskfile.
Then apply and launch only if deployment succeeds:

```sh
chezmoi --source=. apply --exclude=scripts "$HOME/Taskfile.yml" "$HOME/.config/mlx/chat.py" &&
  task -g llm:chat
```

There is no need to activate the venv, set shell-specific environment variables,
or remove an earlier standalone launcher. For an intentionally relocated
existing setup, Task variables can be overridden explicitly:

```sh
task -g llm:chat MLX_VENV="/path/to/.venv" MLX_VOLUME="/Volumes/Another SSD"
```

Focused validation uses fake MLX/Hugging Face modules, a mock venv, and an
isolated Chezmoi destination. It covers installed/missing/broken environments
and setup ordering without real provisioning, downloads, or inference:

```sh
timeout 60 ./tests/bash/run-tests.sh --test global-mlx-chat.bats
```

## Mise (Tool Version Manager)

Mise manages tool versions defined in
[`.mise.toml`](https://github.com/DevSecNinja/dotfiles/blob/main/.mise.toml):

```bash
# Install mise-managed tools
mise install

# Show installed tools
mise list

# Upgrade all tools
mise upgrade

# Check mise configuration
mise doctor
```

**Full-mode installations** automatically install both Task and mise.
**Light mode** installs only mise.

## Pre-commit Hooks (Lefthook)

This repository uses [lefthook](https://github.com/evilmartians/lefthook)
for code quality checks:

```bash
# Install development tools (lefthook, shellcheck, shfmt, ...) via mise
mise install

# Setup lefthook git hooks (from repository root)
home/.chezmoiscripts/linux/run_once_setup-lefthook.sh

# Run manually on all files
lefthook run pre-commit --all-files
```

Hooks run automatically on `git commit`. The checks include:

- 🐚 Shell script linting (`shellcheck`)
- 🎨 Shell script formatting (`shfmt`)
- 🔧 Executable bit enforcement on shell scripts

These scripts and hooks are also used in the GitHub Actions CI pipeline
to ensure quality.
