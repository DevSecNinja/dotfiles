# Docker completion for Fish shell
# Cache generated completions to avoid regenerating on every load

if type -q docker
    # Path to cached completion script
    set -l __docker_fish_completion_cache "$HOME/.config/fish/completions/docker_generated.fish"

    # Resolve the docker binary path (may be absolute)
    set -l __docker_cmd_path (command -s docker)

    # Regenerate cache if it does not exist, or if docker binary is newer
    if not test -e $__docker_fish_completion_cache; or test $__docker_cmd_path -nt $__docker_fish_completion_cache
        docker completion fish >$__docker_fish_completion_cache 2>/dev/null
    end

    # Load the cached completions
    if test -r $__docker_fish_completion_cache
        source $__docker_fish_completion_cache
    end
end
