# Chezmoi completion for Fish shell
# Cache generated completions to avoid regenerating on every load

if type -q chezmoi
    # Determine cache directory for generated completions
    set -l chezmoi_cache_dir
    if set -q XDG_CACHE_HOME
        set chezmoi_cache_dir "$XDG_CACHE_HOME/fish"
    else
        set chezmoi_cache_dir "$HOME/.cache/fish"
    end

    set -l chezmoi_completion_cache "$chezmoi_cache_dir/chezmoi_completions.fish"

    # Generate cached completions once, if chezmoi is available and cache file is missing or outdated
    set -l __chezmoi_cmd_path (command -s chezmoi)
    if not test -f "$chezmoi_completion_cache"; or test $__chezmoi_cmd_path -nt "$chezmoi_completion_cache"
        mkdir -p "$chezmoi_cache_dir"
        chezmoi completion fish >"$chezmoi_completion_cache" 2>/dev/null
    end

    # Load cached completions if they exist
    if test -f "$chezmoi_completion_cache"
        source "$chezmoi_completion_cache"
    end
end
