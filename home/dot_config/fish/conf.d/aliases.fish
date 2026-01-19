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
alias gp 'git push'
alias gl 'git log --oneline --graph'

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

echo "✅ Aliases loaded"
