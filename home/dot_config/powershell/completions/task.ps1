# Task (go-task) initialization for PowerShell
# https://taskfile.dev

# Initialize Task completion if available
if (Get-Command task -ErrorAction SilentlyContinue) {
    task --completion powershell | Invoke-Expression
}
