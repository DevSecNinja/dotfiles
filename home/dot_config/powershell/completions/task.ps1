# Task (go-task) completion for PowerShell
# Documentation: https://taskfile.dev/docs/installation#setup-completions

# Initialize task completions if available
if (Get-Command task -ErrorAction SilentlyContinue) {
    task --completion powershell | Out-String | Invoke-Expression
}
