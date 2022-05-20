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

function download_dotfiles () {
  SOURCE="https://github.com/DevSecNinja/dotfiles"
  CODESPACES_DOTFILES_PATH="/workspaces/.codespaces/.persistedshare/dotfiles"
  TARBALL="$SOURCE/tarball/main"
  TARGET="$HOME/.dotfiles"
  TAR_CMD="tar -xzv -C "$TARGET" --strip-components=1 --exclude='{.gitignore}' --exclude='{LICENSE}' --exclude='{README.md}'"

  is_executable() {
    type "$1" > /dev/null 2>&1
  }

  if [ -d "$CODESPACES_DOTFILES_PATH" ]; then
    echo "Found dotfiles location. Running in Codespaces..."
    mkdir -p "$TARGET"
    cp -nrf $CODESPACES_DOTFILES_PATH $TARGET
    return;
  fi

  if is_executable "git"; then
    CMD="git clone $SOURCE $TARGET"
  elif is_executable "curl"; then
    CMD="curl -#L $TARBALL | $TAR_CMD"
  elif is_executable "wget"; then
    CMD="wget --no-check-certificate -O - $TARBALL | $TAR_CMD"
  fi

  if [ -z "$CMD" ]; then
    echo "No git, curl or wget available. Aborting."
  else
    echo "Installing dotfiles..."
    mkdir -p "$TARGET"
    eval "$CMD"
  fi
}

function move_dotfiles () {
  # Resolve DOTFILES_DIR (assuming ~/.dotfiles on distros without readlink and/or $BASH_SOURCE/$0)

  CURRENT_SCRIPT=$BASH_SOURCE

  if [[ -n $CURRENT_SCRIPT && -x readlink ]]; then
    SCRIPT_PATH=$(readlink -n $CURRENT_SCRIPT)
    DOTFILES_DIR="${PWD}/$(dirname $(dirname $SCRIPT_PATH))"
  elif [ -d "$HOME/.dotfiles" ]; then
    DOTFILES_DIR="$HOME/.dotfiles"
  else
    echo "Unable to find dotfiles, exiting."
    return
  fi

  # Make utilities available

  PATH="$DOTFILES_DIR/bin:$PATH"

  # Source the dotfiles (order matters)

  for DOTFILE in "$DOTFILES_DIR"/system/.{function,function_*,path,env,exports,alias,fnm,grep,prompt,completion,fix}; do
    [ -f "$DOTFILE" ] && . "$DOTFILE"
  done

  if is-macos; then
    for DOTFILE in "$DOTFILES_DIR"/system/.{env,alias,function,path}.macos; do
      [ -f "$DOTFILE" ] && . "$DOTFILE"
    done
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
    sudo apt-get -y install "${packages[@]}"
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

  move_dotfiles
  setup_git
  setup_go

  if [[ $LOGIN_SHELL == 'bash' ]] ; then
    echo "Operating System setup complete."
    echo "Reloading session"

    source ~/.bashrc
  elif [[ $LOGIN_SHELL == 'zsh' ]] ; then
    echo "Changing shells to ZSH"
    # chsh -s /bin/zshd - requires a password

    echo "Operating System setup complete."
    echo "Reloading session"
    exec zsh
  fi
)