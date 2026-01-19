# GitHub CLI completion for Fish shell
# Cache generated completions to avoid regenerating on every load

if type -q gh
    # Path to cached completion script
    set -l __gh_fish_completion_cache "$HOME/.config/fish/completions/gh_generated.fish"

    # Resolve the gh binary path (may be absolute)
    set -l __gh_cmd_path (command -s gh)

    # Regenerate cache if it does not exist, or if gh binary is newer
    if not test -e $__gh_fish_completion_cache; or test $__gh_cmd_path -nt $__gh_fish_completion_cache
        gh completion -s fish >$__gh_fish_completion_cache 2>/dev/null
    end

    # Load the cached completions
    if test -r $__gh_fish_completion_cache
        source $__gh_fish_completion_cache
    end
end
