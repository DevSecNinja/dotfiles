# mise (rtx) initialization
# This file handles mise shell integration (PATH, hooks)
# Completions are loaded from ~/.config/fish/completions/mise.fish (if present)

# Initialize mise if available
if type -q mise
    # Set MISE_YES=1 in non-interactive environments to auto-accept trust prompts
    # This prevents mise from hanging when it encounters .mise.toml files in Codespaces/CI
    # Check for common non-interactive environment indicators
    if set -q CI; or set -q CODESPACES; or set -q GITHUB_ACTIONS; or not isatty stdin
        set -gx MISE_YES 1
    end

    mise activate fish | source
    mise completion fish | source
    echo "✅ mise initialized"
end
