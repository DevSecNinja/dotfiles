#!/bin/sh
# Common shell aliases for Bash and Zsh
# This file should be sourced by config.bash and config.zsh

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# List files
alias l='ls -lah'
alias la='ls -A'
alias ll='ls -lh'

# Git shortcuts
alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gps='git push'
alias gpl='git pull'
alias gl='git log --oneline --graph'
alias gd='git diff'
alias gco='git checkout'
alias gb='git branch'

# Lefthook shortcut (run all pre-commit hooks across the repo)
alias pc='lefthook run pre-commit --all-files'

# Safety
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Chezmoi shortcuts
alias cz='chezmoi'
alias czd='chezmoi diff'
alias cza='chezmoi apply'
alias cze='chezmoi edit'

# Docker shortcuts
alias d='docker'
alias dc='docker compose'
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dex='docker exec -it'

# Shell introspection
alias aliases="alias | sed 's/=.*//'"
alias functions="declare -f | grep '^[a-z].* ()' | sed 's/{$//'"
alias paths='echo -e ${PATH//:/\\n}'

# System info
alias ff='fastfetch'
alias sysinfo='fastfetch'
alias motd='fastfetch'

# SSH
# Print the first available public key (preferring hardware-backed) and copy
# it to the system clipboard via clipboard-copy (auto-detects backend).
# Discovers both the legacy un-suffixed `id_<type>_sk.pub` and per-serial
# `id_<type>_sk_<serial>.pub` files written by `yk-enroll`.
pubkey() {
	_pubkey_key=""
	# Prefer hardware-backed FIDO2 keys: per-serial files first (newest
	# wins via natural sort), then legacy un-suffixed, then non-FIDO2 keys.
	for _pubkey_pattern in \
		"$HOME/.ssh/id_ed25519_sk_"*.pub \
		"$HOME/.ssh/id_ed25519_sk.pub" \
		"$HOME/.ssh/id_ecdsa_sk_"*.pub \
		"$HOME/.ssh/id_ecdsa_sk.pub" \
		"$HOME/.ssh/id_ed25519.pub" \
		"$HOME/.ssh/id_rsa.pub"; do
		for _pubkey_candidate in $_pubkey_pattern; do
			if [ -f "$_pubkey_candidate" ]; then
				_pubkey_key="$_pubkey_candidate"
				break 2
			fi
		done
	done
	unset _pubkey_pattern _pubkey_candidate
	if [ -z "$_pubkey_key" ]; then
		echo "No SSH public key found in ~/.ssh" >&2
		unset _pubkey_key
		return 1
	fi
	cat "$_pubkey_key"
	if command -v clipboard-copy >/dev/null 2>&1 && clipboard-copy --check >/dev/null 2>&1; then
		clipboard-copy <"$_pubkey_key"
		echo "=> Public key ($(basename "$_pubkey_key")) copied to clipboard."
	else
		echo "=> $(basename "$_pubkey_key") (no clipboard backend; not copied)."
	fi
	unset _pubkey_key
}
