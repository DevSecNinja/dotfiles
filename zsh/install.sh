#!/bin/zsh
# Install Oh My Zsh
if ! test omz # command -v doesn't seem to work for some reason via script in zsh
then
  echo "Installing Oh My ZSH"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)" "" --unattended --keep-zshrc
else
  echo "Oh My ZSH already installed"
fi
