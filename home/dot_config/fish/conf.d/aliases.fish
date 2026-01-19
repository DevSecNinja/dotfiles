# Common aliases for Fish shell

# Navigation
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

# List files
alias l 'ls -lah'
alias la 'ls -A'
alias ll 'ls -lh'

# Git shortcuts
alias g 'git'
alias gs 'git status'
alias ga 'git add'
alias gc 'git commit'
alias gps 'git push'
alias gpl 'git pull'
alias gl 'git log --oneline --graph'
alias gd 'git diff'
alias gco 'git checkout'
alias gb 'git branch'

# Pre-commit shortcuts
alias pc 'pre-commit run --all-files'

# Safety
alias rm 'rm -i'
alias cp 'cp -i'
alias mv 'mv -i'

# Chezmoi shortcuts
alias cz 'chezmoi'
alias czd 'chezmoi diff'
alias cza 'chezmoi apply'
alias cze 'chezmoi edit'

# Docker shortcuts
alias d 'docker'
alias dc 'docker compose'
alias dps 'docker ps'
alias dpsa 'docker ps -a'
alias di 'docker images'
alias dex 'docker exec -it'

# Shell introspection
alias aliases "alias | sed 's/=.*//'"
# alias functions - Already built-in in Fish
alias paths 'string split : $PATH'

# System info
alias ff 'fastfetch'
alias sysinfo 'fastfetch'
alias motd 'fastfetch'

# SSH
alias pubkey "cat ~/.ssh/id_rsa.pub | pbcopy; and echo '=> Public key copied to pasteboard.'"

echo "✅ Aliases loaded"
