alias reload!='. ~/.zshrc'

alias cls='clear' # Good 'ol Clear Screen command

# For the occasions sudo isn't sufficient, this loads
# existing ZSH config into root shell so that I can run a function like resize-disk
alias root-and-load='sudo -E su -p'

alias git-rebase='git pull --rebase origin main && echo "==> Now run git push origin --force on your branch after resolving potential conflicts"'

# Gets the token for the Kubernetes Dashboard
alias get-kubedash-token='kubectl -n observability create token kubernetes-dashboard --duration=24h'

# Get Kubernetes node stats
alias k-get-node-cpu-req='kubectl get pods --all-namespaces -o=custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,CPU-REQ:.spec.containers[*].resources.requests.cpu"  | grep -v "<none>"'
alias k-get-node-mem-req='kubectl get pods --all-namespaces -o=custom-columns="NAMESPACE:.metadata.namespace,NAME:.metadata.name,MEM-REQ:.spec.containers[*].resources.requests.memory" | grep -v "<none>"'
