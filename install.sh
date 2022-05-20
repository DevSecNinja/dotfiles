#!/bin/bash

# Function to get the package manager
function get_package_manager() {
  which yum > /dev/null && {
    echo "yum"
    export OSPACKMAN="yum"
    return;
  }
  which apt-get > /dev/null && {
    echo "apt-get"
    export OSPACKMAN="aptget"
    return;
  }
  which brew > /dev/null && {
    echo "homebrew"
    export OSPACKMAN="homebrew"
    return;
  }
}

function setup_zsh() {
  echo 'Adding oh-my-zsh to dotfiles...'
  OMZDIR=~/.dotfiles/oh-my-zsh

  if [ -d "$OMZDIR" ] ; then
    echo 'Updating oh-my-zsh to latest version'
    cd ~/.dotfiles/oh-my-zsh
    git pull origin master
    cd -
  else
    echo 'Adding oh-my-zsh to dotfiles...'
    git clone https://www.github.com/robbyrussell/oh-my-zsh.git
  fi
}

function setup_git() {
  echo 'Setting up git config...'
  git config --global user.name "Jean-Paul van Ravensberg"
  git config --global color.ui true
  git config --global color.diff auto
  git config --global color.status auto
  git config --global color.branch auto
}

function setup_go() {
  # set PATH so it includes Go binaries
  if [ -d "/usr/local/go/bin" ] ; then
      echo 'Setting up Go'
      
      PATH="/usr/local/go/bin:$PATH"
      GOPATH="/workspaces/go"

      if [ ! -d "$GOPATH" ] ; then
          mkdir $GOPATH
      fi

      if [ ! -d "$GOPATH/bin" ] ; then
          mkdir "$GOPATH/bin"
      fi
  fi
}

set -e
(
  get_package_manager
  # general package array
  declare -a packages=('vim' 'git' 'tree' 'htop' 'wget' 'curl')

  LOGIN_SHELL="zsh"

  if [[ $LOGIN_SHELL == 'bash' ]] ; then
    packages=(${packages[@]} 'bash')
  elif [[ $LOGIN_SHELL == 'zsh' ]] ; then
    packages=(${packages[@]} 'zsh')
  fi

  if [[ $OSPACKMAN == "homebrew" ]]; then
    echo "You are running homebrew."
    echo "Using Homebrew to install packages..."
    brew update
    declare -a macpackages=('findutils' 'macvim' 'the_silver_searcher')
    brew install "${packages[@]}" "${macpackages[@]}"
    brew cleanup
  elif [[ "$OSPACKMAN" == "yum" ]]; then
    echo "You are running yum."
    echo "Using yum to install packages...."
    sudo yum update
    sudo yum install "${packages[@]}"
  elif [[ "$OSPACKMAN" == "aptget" ]]; then
    echo "You are running apt-get"
    echo "Using apt-get to install packages...."
    sudo apt-get update
    sudo apt-get install "${packages[@]}"
  else
    echo "Could not determine OS. Exiting..."
    exit 1
  fi

  if [[ $LOGIN_SHELL == 'bash' ]] ; then
    # setup_bash
    echo 'No extra bash configs yet...'
  elif [[ $LOGIN_SHELL == 'zsh' ]] ; then
    setup_zsh
  fi

  setup_git
  setup_go

  if [[ $LOGIN_SHELL == 'bash' ]] ; then
    echo "Operating System setup complete."
    echo "Reloading session"

    source ~/.bashrc
  elif [[ $LOGIN_SHELL == 'zsh' ]] ; then
    echo "Changing shells to ZSH"
    chsh -s /bin/zsh

    echo "Operating System setup complete."
    echo "Reloading session"
    exec zsh
  fi

)