# Devcontainer image with dotfiles and tools pre-installed
# Built and pushed by .github/workflows/devcontainer-prebuild.yaml
#
# Build context must be the repo root (set via "context": ".." in devcontainer.json)
# so that the home/ directory is available for COPY.

FROM mcr.microsoft.com/devcontainers/base:debian-12

# Copy dotfiles source into the image for chezmoi to install tools during build
COPY --chown=vscode:vscode home/ /tmp/dotfiles-src/

# Pre-install dotfiles and all tools as vscode user (non-interactive)
#   REMOTE_CONTAINERS=true  → triggers devcontainer detection → full install mode
#   chezmoi run_once scripts install packages (fish, vim, jq, brew, mise, etc.)
#   postCreateCommand in devcontainer.json re-applies from workspace source on start
USER vscode
RUN REMOTE_CONTAINERS=true /tmp/dotfiles-src/install.sh \
    && sudo rm -rf /tmp/dotfiles-src \
    && sudo apt-get clean \
    && sudo rm -rf /var/lib/apt/lists/*
USER root
