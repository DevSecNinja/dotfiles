# Homebrew initialization
# This file handles Homebrew shell environment setup

# Initialize Homebrew (macOS/Linux)
if test -f /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
else if test -f /usr/local/bin/brew
    eval (/usr/local/bin/brew shellenv)
else if test -f /home/linuxbrew/.linuxbrew/bin/brew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end
