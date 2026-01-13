# PowerShell Aliases
# Loaded by profile.ps1

# Navigation
Set-Alias -Name .. -Value Set-LocationUp
function Set-LocationUp { Set-Location .. }
Set-Alias -Name ... -Value Set-LocationUpUp
function Set-LocationUpUp { Set-Location ..\.. }

# List files (Unix-like)
function ll { Get-ChildItem -Force @args }
function la { Get-ChildItem -Force @args }

# Git shortcuts
function gs { git status @args }
function ga { git add @args }
function gc { git commit @args }
function gp { git push @args }
function gl { git pull @args }
function gd { git diff @args }
function gco { git checkout @args }
function gb { git branch @args }
function glog { git log --oneline --graph --decorate @args }

# Docker shortcuts (if Docker is installed)
function dps { docker ps @args }
function dpsa { docker ps -a @args }
function di { docker images @args }
function dex { docker exec -it @args }

# System utilities
function which($name) {
    Get-Command $name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
}

function touch($file) {
    if (Test-Path $file) {
        (Get-Item $file).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $file | Out-Null
    }
}

function mkcd($path) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    Set-Location $path
}

# Quick edit of this profile
function Edit-Profile {
    code $PROFILE
}
Set-Alias -Name ep -Value Edit-Profile

# Reload profile
function Reload-Profile {
    . $PROFILE
    Write-Host "Profile reloaded!" -ForegroundColor Green
}
Set-Alias -Name reload -Value Reload-Profile

# Show all aliases
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

    Write-Host "`n=== Profile ===" -ForegroundColor Cyan
    Write-Host "ep      - Edit profile"
    Write-Host "reload  - Reload profile"
    Write-Host ""
}
Set-Alias -Name aliases -Value Show-Aliases
