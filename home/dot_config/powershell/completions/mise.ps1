# mise (rtx) initialization for PowerShell
# Note: 'mise activate' handles its own completion setup

# Initialize mise if available
if (Get-Command mise -ErrorAction SilentlyContinue) {
    mise activate pwsh | Invoke-Expression
}
