#!/bin/sh
#
# Homebrew
#
# This installs some of the common dependencies needed (or at least desired)
# using Homebrew.

# Check for Homebrew
if test ! $(which brew)
then
  echo "  Installing Homebrew for you."

  # Install the correct homebrew for each OS type
  if test "$(uname)" = "Darwin"
  then
    brewRepo="Homebrew"
  elif test "$(expr substr $(uname -s) 1 5)" = "Linux"
  then
    brewRepo="Linuxbrew"
  fi

  if [[ $(command -v ruby) == "" ]]; then
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/$brewRepo/install/master/install)"
  else
    CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/$brewRepo/install/HEAD/install.sh)"
  fi

fi

exit 0
