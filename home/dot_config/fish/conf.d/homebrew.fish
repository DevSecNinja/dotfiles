# Homebrew initialization
# This file handles Homebrew shell environment setup

# Initialize Homebrew (macOS/Linux)
set -l __brew_initialized 0
if test -f /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
    set __brew_initialized 1
else if test -f /usr/local/bin/brew
    eval (/usr/local/bin/brew shellenv)
    set __brew_initialized 1
else if test -f /home/linuxbrew/.linuxbrew/bin/brew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
    set __brew_initialized 1
end

if test $__brew_initialized -eq 1
    echo "✅ Homebrew initialized"
end
