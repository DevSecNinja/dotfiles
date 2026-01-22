# Fish Shell Configuration
# This file is sourced on every new shell session

# Set greeting
set -g fish_greeting ""

# Set working directory to projects folder if not already there
# Skip this if running in VS Code to preserve the opened folder location
if test "$TERM_PROGRAM" != "vscode"
    set current_path (pwd)
    set projects_path "$HOME/projects"

    # Check if current path contains 'projects' (case-insensitive)
    if not string match -qi "*projects*" $current_path
        # Not in projects directory, change to it if it exists
        if test -d $projects_path
            cd $projects_path
        end
    end
end

# Add custom paths
fish_add_path $HOME/.local/bin
fish_add_path $HOME/bin

# Environment variables
# Use VS Code if available, otherwise vim
if type -q code
    set -gx EDITOR "code --wait"
    set -gx VISUAL "code --wait"
else
    set -gx EDITOR vim
    set -gx VISUAL vim
end

# Load common aliases (from conf.d/aliases.fish - auto-loaded)
# Load all completions (from completions/ directory - auto-loaded)
# Homebrew initialization is in conf.d/homebrew.fish (auto-loaded)
# mise initialization is in conf.d/mise.fish (auto-loaded)

# Load all functions from shell/functions directory
# These are bash scripts wrapped as Fish functions
if test -d $HOME/.config/shell/functions
    for script in $HOME/.config/shell/functions/*.sh
        set -l func_name (basename $script .sh)
        set -l func_name_underscore (string replace -a '-' '_' $func_name)

        # Skip bash functions that have native Fish implementations
        # Check both hyphenated and underscored versions (Fish convention)
        if functions -q $func_name; or functions -q $func_name_underscore
            continue
        end

        # Create Fish function wrapper
        eval "function $func_name --description 'Run bash script: $script'
            bash $script \$argv
        end"
    end
end

echo "🐠 Fish shell configured successfully!"
