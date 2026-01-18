# Fish Shell Configuration
# This file is sourced on every new shell session

# Set greeting
set -g fish_greeting ""

# Environment variables
# Use VS Code if available, otherwise vim
if type -q code
    set -gx EDITOR "code --wait"
    set -gx VISUAL "code --wait"
else
    set -gx EDITOR vim
    set -gx VISUAL vim
end

# Add custom paths
fish_add_path $HOME/.local/bin
fish_add_path $HOME/bin

# Homebrew initialization is now in conf.d/homebrew.fish
# mise initialization is now in conf.d/mise.fish
# Docker and gh completions are in completions/ directory

# Load custom functions from conf.d/
# Files in conf.d/ are automatically sourced
# TODO: Decide to migrate functions to fish syntax or keep bash scripts
if test -d $HOME/.config/shell/functions
    for script in $HOME/.config/shell/functions/*.sh
        set -l func_name (basename $script .sh)

        # Create Fish function wrapper
        eval "function $func_name --description 'Run bash script: $script'
            bash $script \$argv
        end"
    end
end

echo "🐠 Fish shell configured successfully!"
