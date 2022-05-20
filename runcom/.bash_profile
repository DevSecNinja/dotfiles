# If not running interactively, don't do anything

[ -z "$PS1" ] && return

# Set LSCOLORS

eval "$(dircolors -b "$DOTFILES_DIR"/system/.dir_colors)"

# Clean up

unset CURRENT_SCRIPT SCRIPT_PATH DOTFILE

# Export

export DOTFILES_DIR