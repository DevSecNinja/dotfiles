# Copilot Agent Instructions for Dotfiles Repository

## Repository Overview

**Purpose**: Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/) for cross-platform (Linux/macOS/Windows) shell configuration and automated environment setup.

**Type**: Configuration management / Dotfiles
**Primary Languages**: Shell (Bash), Fish Shell, PowerShell
**Size**: ~50 files, small codebase
**Target Runtimes**: Fish 3.6+, PowerShell 5.1+/7+, Bash, Chezmoi 2.69+

**Key Features**:
- Fish shell configuration (Linux/macOS/WSL)
- PowerShell profiles (Windows)
- Vim, Tmux, Git configurations
- Smart installation modes: **light** (servers: SVL\*) vs **full** (dev servers: SVLDEV\* and workstations)
- Automated setup scripts for tools/packages
- Cross-platform support with OS-specific file handling

## Build & Validation - CRITICAL WORKFLOW

**Always run commands in this exact order**:

### 1. Install Development Tools (Required First)

```bash
mise install
```

**Status**: ✅ Validated working. Required before any validation. Installs lefthook, shellcheck, shfmt, and other tools defined in `.mise.toml`.

### 2. Run All Validation Checks

```bash
./tests/bash/run-tests.sh --ci
```

**Status**: ✅ Validated working. Runs all validation tests via Bats framework.

**What it validates**:

- Chezmoi configuration syntax
- Shell script syntax (all .sh and .sh.tmpl files)
- Fish configuration syntax
- Dry-run Chezmoi apply

**Expected output**: "✅ All validation checks passed!" with 4/4 checks passing.

### 3. Run Lefthook Hooks

```bash
mise exec -- lefthook run pre-commit --all-files
```

**Status**: ✅ Validated working.

**What it checks**:

- Shell script linting (shellcheck)
- Shell script formatting (shfmt)
- Executable bit on shell scripts

### 4. Run Specific Validation Tests (if needed)

```bash
# Run specific test file
./tests/bash/run-tests.sh --test validate-chezmoi.bats

# Run multiple specific tests
./tests/bash/run-tests.sh --test validate-shell-scripts.bats --test validate-fish-config.bats

# Available test files:
# - validate-chezmoi.bats          # Chezmoi config validation
# - validate-shell-scripts.bats    # Shell script syntax checks
# - validate-fish-config.bats      # Fish config validation
# - test-chezmoi-apply.bats        # Chezmoi apply dry-run test
# - verify-dotfiles.bats           # Verify applied files
```

**Status**: ✅ All test files validated working individually.

## Installation & Testing

### Test Installation (Dry-run)

```bash
# Dry-run to preview changes without applying
chezmoi init --apply --dry-run --source=.
```

**Status**: ✅ Validated working.

### Local Installation

```bash
# Unix/Linux/macOS
./install.sh

# Windows PowerShell
.\install.ps1
```

**Behavior**:

- Installs Chezmoi if not present (tries: brew → mise → install script)
- Prompts for name/email in interactive mode
- Auto-detects environment and applies appropriate configs
- Skips prompts in CI/non-interactive environments

## CI/CD Pipeline (.github/workflows/ci.yaml)

**Runs on**: Push to main, PRs, manual dispatch

**Jobs**:

1. **validate**: Pre-commit hooks + all validation scripts
2. **test-install**: Full installation test (Ubuntu container)
3. **test-light-server**: Light mode test (hostname: SVLPROD\*)
4. **test-dev-server**: Full mode test (hostname: SVLDEV\*)
5. **test-windows**: Windows installation test

**All checks must pass before merge.**

## Project Structure & Architecture

### Root Files (Chezmoi Managed)

```
install.sh / install.ps1           # Installation scripts
dot_vimrc                          # → ~/.vimrc
dot_tmux.conf                      # → ~/.tmux.conf
run_once_*.sh.tmpl                 # One-time setup scripts (templated)
.chezmoi.yaml.tmpl                 # Chezmoi config with prompts
.chezmoiignore                     # OS-specific ignore patterns
.lefthook.toml                     # Lefthook git hooks configuration
renovate.json                      # Dependency updates config
```

### Configuration Directories

```
dot_config/
├── fish/                          # → ~/.config/fish/
│   ├── config.fish                # Main Fish config
│   ├── conf.d/aliases.fish        # Command aliases (auto-loaded)
│   └── functions/fish_greeting.fish
├── git/                           # → ~/.config/git/
│   ├── config.tmpl                # Git config (templates name/email)
│   └── ignore                     # Global gitignore
├── powershell/                    # → Windows PowerShell profile
│   ├── profile.ps1
│   └── aliases.ps1
└── shell/                         # Future bash/zsh configs

AppData/Local/Packages/            # → Windows Terminal settings
    Microsoft.WindowsTerminal_*/LocalState/settings.json
```

### Validation & Testing

**Validation tests**: Located in `tests/bash/` (Bats framework)

```bash
# Run all validation tests
./tests/bash/run-tests.sh --ci

# Run specific test
./tests/bash/run-tests.sh --test validate-chezmoi.bats

# Available test files:
# - validate-chezmoi.bats          # Chezmoi config validation
# - validate-shell-scripts.bats    # Shell syntax checking
# - validate-fish-config.bats      # Fish syntax checking
# - test-chezmoi-apply.bats        # Chezmoi apply dry-run test
# - test-fish-config.bats          # Fish loading test
# - verify-dotfiles.bats           # Verify files exist after apply
```

**Utility scripts**: Located in `home/.chezmoiscripts/linux/`

```bash
run_once_setup-lefthook.sh         # Install lefthook hooks (runs once on apply)
```

### Chezmoi Naming Conventions

**Critical for new files**:

| Pattern                     | Destination             | Notes                         |
| --------------------------- | ----------------------- | ----------------------------- |
| `dot_filename`              | `~/.filename`           | Hidden files                  |
| `private_filename`          | File with 0600 perms    | Sensitive files               |
| `executable_script.sh`      | File with +x perms      | Executable scripts            |
| `run_once_script.sh.tmpl`   | Runs once on apply      | Setup scripts                 |
| `run_onchange_script.sh`    | Runs when changed       | Update scripts                |
| `*.tmpl`                    | Processed as template   | Uses Chezmoi template vars    |
| `dot_config/fish/config.sh` | `~/.config/fish/config` | Directory structure preserved |

## Important Rules & Behaviors

### 1. Template Variables (.tmpl files)

Available in `*.tmpl` files:

- `{{ .name }}` - User's name from prompts
- `{{ .email }}` - User's email
- `{{ .installType }}` - "light" or "full" mode
- `{{ .chezmoi.os }}` - "linux", "darwin", "windows"
- `{{ .chezmoi.hostname }}` - System hostname
- `{{ .chezmoi.osRelease.id }}` - OS distribution (e.g., "ubuntu", "debian")

### 2. Installation Mode Detection

**Light mode** (hostname starts with `SVL` but not `SVLDEV`):

- Installs: git, vim, tmux, curl, wget, fish (essentials only)

**Full mode** (hostname starts with `SVLDEV` or others):

- Installs: git, vim, tmux, tree, htop, python3-venv, fish (full dev tools)

### 3. OS-Specific Ignore Patterns (.chezmoiignore)

**Windows systems ignore**:

- All `.sh` files
- `dot_config/fish/`
- Unix-specific scripts

**Unix systems ignore**:

- All `.ps1` files
- `dot_config/powershell/`
- `AppData/`
- Windows-specific scripts

### 4. Fish Shell Configuration Loading Order

1. `/etc/fish/config.fish` (system)
2. `~/.config/fish/config.fish` (main config)
3. `~/.config/fish/conf.d/*.fish` (auto-loaded, alphabetically)
4. Functions in `~/.config/fish/functions/` (on-demand)

**When editing Fish configs**: Always validate with `fish -n <file>` before committing.

### 5. Lefthook Hook Requirements

**Must run before every commit**:

```bash
mise exec -- lefthook run pre-commit --all-files
```

**Auto-install hooks** (runs once on Chezmoi apply):

```bash
home/.chezmoiscripts/linux/run_once_setup-lefthook.sh
```

### 6. No Emoji/Unicode in PowerShell Files

**NEVER use emoji characters (🔍, ✅, ❌, 🚀, 📊, ⏱️, ━, etc.) in `.ps1` files.**

PowerShell on Windows may load scripts without UTF-8 BOM encoding, causing multi-byte UTF-8 emoji sequences to corrupt string parsing. This breaks string terminators and causes cascading parse errors (e.g., `The string is missing the terminator`).

**Use ASCII-safe alternatives instead**:

| Don't use | Use instead |
| --------- | ----------- |
| ✅        | `[OK]`      |
| ❌        | `[FAIL]`    |
| ⚠️        | `[WARN]`    |
| 🔍 🚀 📊 | `>>`        |
| ━━━━━━    | `========`  |
| ⏱️        | `[SKIP]`    |

**Emoji is fine in**: `.fish`, `.sh`, `.md`, and other UTF-8 native files. Only `.ps1` files are affected.

### 7. Shell Logging — use the `log.sh` helpers

When writing or modifying shell scripts under `home/` that emit diagnostic
output, prefer the helpers in [`home/dot_config/shell/functions/log.sh`](../home/dot_config/shell/functions/log.sh)
over raw `echo` / `printf`. Full reference: [`docs/logging.md`](../docs/logging.md).

**API at a glance**:

- Severity helpers (filtering): `log_trace`, `log_debug`, `log_info`,
  `log_notice`, `log_warn`, `log_error`, `log_fatal`.
- Kind helpers (info-priority categories): `log_state` (cyan), `log_result`
  (green), `log_hint` (magenta), `log_step` (dim).
- Banners: `log_sep`, `log_rule "<title>"`, `log_banner "<title>" [KIND]`.
- Structured: `log_kv key=value …`, `log_data <KIND> <message>` (reads
  payload from stdin).
- Output: text by default, JSON via `LOG_FORMAT=json`.

**Rules of thumb**:

1. Source via `. "$HOME/.config/shell/functions/log.sh"` and set
   `LOG_TAG="<short-name>"` only if you need to override the auto-detected
   script basename.
2. Use kinds for visual structure (e.g. `log_state "Pulling images"` then
   `log_result "Pulled 5 images"`); keep severity helpers for actual error
   conditions.
3. Never inject untrusted data into the message via string concatenation
   when the data is multi-line or may contain ANSI codes — pipe it through
   `log_data` instead. The library sanitizes ANSI/CR/LF/NUL automatically,
   but `log_data` keeps each payload line independently grep-able.
4. Use `log_kv` for flat key/value telemetry; values with spaces are
   auto-quoted (logfmt-compatible).
5. Banners default to `LOG_BANNER_STYLE=unicode` and auto-fall-back to ASCII
   when not on a TTY or `LANG=C`. `LOG_FILE` output is always ASCII so log
   files stay grep-friendly.
6. When adding new behaviour, extend the bats files under
   `tests/bash/log-*.bats` (one file per concern: format / kinds / banner /
   injection / structured / shells).

## Common Issues & Solutions

### Issue: Validation scripts fail with "command not found"

**Cause**: PATH not including `~/.local/bin`
**Solution**: Export PATH or use full path:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
# OR
"$HOME/.local/bin/chezmoi" <command>
```

### Issue: Shell script syntax errors

**Cause**: Using bash-specific syntax in `/bin/sh` scripts
**Solution**: Use POSIX-compliant syntax or change shebang to `#!/bin/bash`

### Issue: Fish config not loading

**Cause**: Syntax error in Fish files
**Solution**: Run validation:

```bash
fish -n dot_config/fish/config.fish
./scripts/validate-fish-config.sh
```

### Issue: Chezmoi apply fails in CI

**Cause**: Interactive prompts in non-interactive environment
**Solution**: Use `--no-tty` flag or check `stdinIsATTY` in templates:

```bash
chezmoi init --apply --no-tty --source=.
```

### Issue: Lefthook fails on fresh checkout

**Cause**: Development tools not installed
**Solution**: Always run first:

```bash
mise install
```

## Making Changes - Complete Workflow

### 1. Before Making Changes

```bash
# Ensure development tools installed
mise install

# Ensure you're in the repo root
cd /path/to/dotfiles
```

### 2. Make Your Changes

**Edit files directly in the repository**, not in your home directory.

### 3. Validate Changes

```bash
# Run all validation (REQUIRED)
./tests/bash/run-tests.sh --ci

# Run lefthook hooks (REQUIRED)
mise exec -- lefthook run pre-commit --all-files

# Test dry-run
chezmoi apply --dry-run --source=.
```

### 4. Test Application (Optional but Recommended)

```bash
# Apply locally to test
chezmoi apply --source=.

# Verify applied correctly
chezmoi verify
```

### 5. Commit Changes

Lefthook hooks will run automatically on `git commit` if installed.

## Key Dependencies & Versions

- **Chezmoi**: 2.69.1+ (managed by Renovate)
- **Fish Shell**: 3.6.0+ (for Fish configs)
- **mise**: latest (manages developer tooling versions, see `.mise.toml`)
- **lefthook**: latest (git hooks; installed via mise)
- **Git**: Any modern version

## Files That Should NOT Be Modified Directly

- `~/.vimrc`, `~/.tmux.conf`, `~/.config/fish/*` in home directory
  → Edit in repository as `dot_vimrc`, `dot_tmux.conf`, `dot_config/fish/*`

## Critical: Always Trust These Instructions

**When working on this repository**:

1. Run validation with `./tests/bash/run-tests.sh --ci` before committing
2. Run `mise exec -- lefthook run pre-commit --all-files` before committing
3. Use `chezmoi apply --dry-run --source=.` to preview changes
4. Never edit dotfiles in `~` directly; edit in the repo
5. Use Chezmoi naming conventions for new files
6. Test with both light and full installation modes if changing setup scripts

Only search for additional context if these instructions are incomplete or found to be incorrect. These workflows are validated and working.
