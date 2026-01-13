# Fish Shell Configuration
# This file is sourced on every new shell session

# Set greeting
set -g fish_greeting ""

# Environment variables
set -gx EDITOR vim
set -gx VISUAL vim

# Add custom paths
fish_add_path $HOME/.local/bin
fish_add_path $HOME/bin

# Load custom functions from conf.d/
# Files in conf.d/ are automatically sourced

echo "🐠 Fish shell configured successfully!"
