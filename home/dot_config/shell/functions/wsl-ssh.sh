#!/bin/bash
# WSL <-> Windows SSH integration for Bash and Zsh.
#
# In WSL there is no local SSH agent holding your keys: the private keys live
# in 1Password on the Windows host. WSL therefore forwards whole SSH requests
# to the Windows OpenSSH client (ssh.exe), which talks to the 1Password SSH
# agent and prompts for approval on Windows.
# See https://www.1password.dev/ssh/integrations/wsl and docs/wsl.md.
#
# Git already does this through `core.sshCommand = ssh.exe` (set in
# dot_config/git/config.tmpl); these aliases give interactive `ssh` and
# `ssh-add` the same behaviour, which 1Password documents as optional.
#
# Guarded on WSL_DISTRO_NAME (set by WSL itself) so the aliases never leak
# into a native Linux or macOS session, and on ssh.exe actually being
# reachable, which requires WSL interop to be enabled.

if [ -n "${WSL_DISTRO_NAME:-}" ] && command -v ssh.exe >/dev/null 2>&1; then
    alias ssh='ssh.exe'
    alias ssh-add='ssh-add.exe'
fi
