# GitHub CLI completion for Fish shell
# Note: Homebrew provides gh completions in $(brew --prefix)/share/fish/vendor_completions.d/gh.fish
# which are automatically loaded by Homebrew's Fish. See: https://docs.brew.sh/Shell-Completion
# This file exists only for non-Homebrew installations and uses caching to avoid regeneration.

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
