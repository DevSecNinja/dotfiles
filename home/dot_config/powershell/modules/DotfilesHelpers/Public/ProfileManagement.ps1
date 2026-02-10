# Profile management

function Edit-Profile {
    code $PROFILE
}

function Import-Profile {
    . $PROFILE
    Write-Host "Profile reloaded!" -ForegroundColor Green
}

# Show all aliases and functions
function Show-Aliases {
    Write-Host "`n=== Navigation ===" -ForegroundColor Cyan
    Write-Host "..      - Go up one directory"
    Write-Host "...     - Go up two directories"

    Write-Host "`n=== File Operations ===" -ForegroundColor Cyan
    Write-Host "ll/la   - List files (including hidden)"
    Write-Host "touch   - Create or update file timestamp"
    Write-Host "mkcd    - Create directory and cd into it"
    Write-Host "which   - Find command location"

    Write-Host "`n=== Git ===" -ForegroundColor Cyan
    Write-Host "gs      - git status"
    Write-Host "ga      - git add"
    Write-Host "gc      - git commit"
    Write-Host "gp      - git push"
    Write-Host "gl      - git pull"
    Write-Host "gd      - git diff"
    Write-Host "gco     - git checkout"
    Write-Host "gb      - git branch"
    Write-Host "glog    - git log (formatted)"

    Write-Host "`n=== Docker ===" -ForegroundColor Cyan
    Write-Host "dps     - docker ps"
    Write-Host "dpsa    - docker ps -a"
    Write-Host "di      - docker images"
    Write-Host "dex     - docker exec -it"

    Write-Host "`n=== Chezmoi ===" -ForegroundColor Cyan
    Write-Host "Reset-ChezmoiScripts  - Clear script state to re-run scripts"
    Write-Host "Reset-ChezmoiEntries  - Clear entry state to reprocess files"

    Write-Host "`n=== Winget ===" -ForegroundColor Cyan
    Write-Host "wup/winup           - Invoke winget package upgrades"
    Write-Host "Test-WingetUpdates  - Check for available updates"

    Write-Host "`n=== Profile ===" -ForegroundColor Cyan
    Write-Host "ep      - Edit profile"
    Write-Host "reload  - Import profile (reload)"
    Write-Host ""
}
