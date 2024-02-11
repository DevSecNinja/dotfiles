#!/bin/zsh
# Install Oh My Zsh
if ! command -v omz &> /dev/null
then
  echo "Installing Oh My ZSH"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)" "" --unattended --keep-zshrc
else
  echo "Oh My ZSH already installed"
fi
