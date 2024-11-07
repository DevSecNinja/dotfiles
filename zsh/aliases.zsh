alias reload!='. ~/.zshrc'

alias cls='clear' # Good 'ol Clear Screen command

# For the occasions sudo isn't sufficient, this loads
# existing ZSH config into root shell so that I can run a function like resize-disk
alias root-and-load='sudo -E su -p'

# Gets the token for the Kubernetes Dashboard
alias get-kubedash-token='kubectl -n observability create token kubernetes-dashboard --duration=24h'
