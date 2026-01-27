# oh-my-posh initialization for PowerShell

# Initialize oh-my-posh if available
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    oh-my-posh init pwsh --eval --config ~/.ohmyposh.omp.yaml | Invoke-Expression
}
