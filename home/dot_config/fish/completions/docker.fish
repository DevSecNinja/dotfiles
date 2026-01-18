# Docker completion for Fish shell
# Generate completion dynamically if docker is available

if type -q docker
    docker completion fish | source
end
