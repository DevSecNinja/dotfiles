# mise (rtx) initialization
# This file handles mise shell integration (PATH, hooks)
# Completions are loaded from ~/.config/fish/completions/mise.fish (if present)

# Initialize mise if available
if type -q mise
    mise activate fish | source
    mise completion fish | source
    echo "✅ mise initialized"
end
