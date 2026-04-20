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

## Pre-commit Hooks

This repository uses [pre-commit](https://pre-commit.com/) for code
quality checks:

```bash
# Install dependencies
pip3 install -r requirements.txt

# Setup pre-commit hooks (from repository root)
home/.chezmoiscripts/linux/run_once_setup-precommit.sh

# Run manually on all files
pre-commit run --all-files
```

Hooks run automatically on `git commit`. The checks include:

- ✂️ Trailing whitespace removal
- 📄 End-of-file fixes
- 🔍 YAML validation
- 🎨 Shell script formatting (`shfmt`)

These scripts and hooks are also used in the GitHub Actions CI pipeline
to ensure quality.
