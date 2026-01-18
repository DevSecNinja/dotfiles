#!/bin/zsh
# Docker completion for Zsh
# Generate completion dynamically if docker is available

if command -v docker >/dev/null 2>&1; then
    eval "$(docker completion zsh)"
fi
