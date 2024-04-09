#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

# Check if we can sudo
# https://unix.stackexchange.com/a/692109
sudo_response=$(SUDO_ASKPASS=/bin/false sudo -A whoami 2>&1 | wc -l)
if [ $sudo_response = 2 ];
then
    can_sudo=1
elif [ $sudo_response = 1 ];
then
    can_sudo=0
else
    echo "Unexpected sudo response: $sudo_response" >&2
fi

# Check for Homebrew & if not running interactively
if test ! $(which brew) && ! [ -z "$PS1" ] && [ "$DOTFILES_INSTALL_MODE" = "complete" ]
then
  echo "  Installing Homebrew for you."

  if [ $can_sudo = 0 ];
  then
    CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

fi

exit 0
