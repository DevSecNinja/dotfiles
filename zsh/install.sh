# Install Oh My Zsh
if test $(which omz);
then
  echo "Installing Oh My ZSH"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)" "" --unattended --keep-zshrc
fi
