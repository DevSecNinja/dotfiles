#!/bin/sh

# Check if the folder ~/Library/KeyBindings/ exists. If not, create it
if [ ! -d ~/Library/KeyBindings/ ]; then
  echo "[+] Creating KeyBindings folder"
  mkdir -p ~/Library/KeyBindings/
fi

# Copy the DefaultKeyBinding.dict file to the ~/Library/KeyBindings/ folder
# TODO: Check if this can be linked instead of copied with link_file function
echo "[+] Copy DefaultKeyBinding.dict to ~/Library/KeyBindings/"
cp DefaultKeyBinding.dict ~/Library/KeyBindings/
