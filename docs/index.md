# 🐠 Dotfiles

Modern dotfiles repository managed with [Chezmoi](https://chezmoi.io/),
featuring [Fish shell](https://fishshell.com/) configuration and automated
setup scripts for Linux, macOS, Windows, and WSL.

[![CI](https://github.com/DevSecNinja/dotfiles/actions/workflows/ci.yaml/badge.svg)](https://github.com/DevSecNinja/dotfiles/actions/workflows/ci.yaml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/DevSecNinja/dotfiles/blob/main/LICENSE)

## ✨ Features

- **Multi-Shell Support**: Configurations for Fish, Bash, Zsh
  (Linux/macOS) and PowerShell (Windows) with unified aliases and custom
  functions.
- **Git Configuration**: Pre-configured with templates for user info and
  global ignore patterns.
- **Editor Configurations**: Vim and Tmux with sensible defaults.
- **Cross-Platform**: Works seamlessly on Linux, macOS, Windows
  (PowerShell), and WSL.
- **Custom Functions Library**: Reusable shell functions for common tasks
  (git operations, brew updates, file management).
- **Automated Validation**: Pre-commit hooks and validation scripts ensure
  configuration quality.
- **Windows Enterprise Detection**: Automatic detection of Entra ID
  (Azure AD) and Intune enrollment status.
- **Task Automation**: Integrated [Task](https://taskfile.dev/) runner for
  common operations (validation, testing, installation).
- **Tool Version Management**: [mise](https://mise.jdx.dev/) for managing
  development tool versions.

## 🚀 Quick Start

Jump to the [Installation guide](installation.md) for platform-specific
instructions, or explore the [repository structure](structure.md) to
understand how everything fits together.

## 📚 Navigate the Docs

- [Installation](installation.md) &mdash; Linux/macOS, Windows, WSL, and
  Coder workspaces.
- [Customization](customization.md) &mdash; Personal info, installation
  modes, and common commands.
- [Structure](structure.md) &mdash; Directory layout and Chezmoi naming
  conventions.
- [Chezmoi Variables](chezmoi-variables.md) &mdash; Template variables and
  environment variables exposed to shells.
- [Development Tools](development-tools.md) &mdash; Task, mise, and
  pre-commit workflows.
- [Contributing](contributing.md) &mdash; Make changes and validate them.

## 📄 License

Released under the [MIT License](https://github.com/DevSecNinja/dotfiles/blob/main/LICENSE).
