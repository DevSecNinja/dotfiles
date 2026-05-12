# syntax=docker/dockerfile:1.7
# Devcontainer image with dotfiles and tools pre-installed
# Built and pushed by .github/workflows/devcontainer-prebuild.yaml
#
# Build context must be the repo root (set via "context": ".." in devcontainer.json)
# so that the home/ directory is available for COPY.

FROM mcr.microsoft.com/devcontainers/base:debian-12@sha256:23fa69fed758b7927c60061317d73baf7d66b9fca5c344e80bce3a940b229af0

ARG DOTFILES_DEVCONTAINER_VERSION=latest
ARG DOTFILES_DEVCONTAINER_REVISION=unknown
LABEL org.opencontainers.image.source="https://github.com/DevSecNinja/dotfiles" \
    org.opencontainers.image.version="${DOTFILES_DEVCONTAINER_VERSION}" \
    org.opencontainers.image.revision="${DOTFILES_DEVCONTAINER_REVISION}"

# Copy dotfiles source into the image for chezmoi to install tools during build
COPY --chown=vscode:vscode home/ /tmp/dotfiles-src/
COPY --chown=vscode:vscode .mise.toml /tmp/dotfiles-src/.mise.toml
COPY --chown=vscode:vscode script/devcontainer-software-manifest.sh /tmp/devcontainer-software-manifest.sh

# Pre-install dotfiles and all tools as vscode user (non-interactive)
#   REMOTE_CONTAINERS=true  → triggers devcontainer detection → full install mode
#   chezmoi run_once scripts install packages (fish, vim, jq, brew, mise, etc.)
#   After install, remove chezmoi config (but keep state DB) so postCreateCommand
#   re-initializes with correct env detection (CI, Codespaces, etc.)
#   The state DB is preserved so unchanged run_once scripts won't re-run
USER vscode
RUN --mount=type=secret,id=GITHUB_TOKEN \
    if [ -s /run/secrets/GITHUB_TOKEN ]; then \
        export GITHUB_TOKEN="$(cat /run/secrets/GITHUB_TOKEN)"; \
    fi \
    && curl https://mise.run | sh \
    && export PATH="${HOME}/.local/bin:${HOME}/.local/share/mise/shims:${PATH}" \
    && REMOTE_CONTAINERS=true /tmp/dotfiles-src/install.sh \
    && /tmp/devcontainer-software-manifest.sh /tmp/dotfiles-devcontainer \
    && manifest_dir=/usr/local/share/dotfiles-devcontainer \
    && sudo mkdir -p "${manifest_dir}" \
    && sudo cp /tmp/dotfiles-devcontainer/*.md "${manifest_dir}/" \
    && sudo chmod 0644 "${manifest_dir}"/*.md \
    && rm -f "${HOME}/.config/chezmoi/chezmoi.yaml" \
    && if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then \
        /home/linuxbrew/.linuxbrew/bin/brew cleanup --prune=all -s || echo "[WARN] Homebrew cleanup failed; continuing"; \
    fi \
    && rm -rf "${HOME}/.cache/Homebrew" \
    && rm -rf /tmp/dotfiles-devcontainer /tmp/devcontainer-software-manifest.sh \
    && sudo rm -rf /tmp/dotfiles-src \
    && sudo apt-get clean \
    && sudo rm -rf /var/lib/apt/lists/*
USER root
