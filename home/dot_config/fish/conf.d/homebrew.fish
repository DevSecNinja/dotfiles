# Homebrew initialization
# Note: Fish shell automatically uses Homebrew's completion paths when using Homebrew's Fish.
# See: https://docs.brew.sh/Shell-Completion#configuring-completions-in-fish
# Homebrew completions are in:
#   - /opt/homebrew/share/fish/completions
#   - /opt/homebrew/share/fish/vendor_completions.d

# Initialize Homebrew (macOS/Linux)
if test -f /opt/homebrew/bin/brew
    eval (/opt/homebrew/bin/brew shellenv)
else if test -f /usr/local/bin/brew
    eval (/usr/local/bin/brew shellenv)
else if test -f /home/linuxbrew/.linuxbrew/bin/brew
    eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)
end
