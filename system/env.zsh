# EDITOR
if command -v code &> /dev/null
then
  # vscode requires `--wait` if you're editing interactively in a prompt.
  export EDITOR='code --wait'
else
  export EDITOR='nano'
fi
