# Install the correct homebrew for each OS type
if test "$(uname)" = "Darwin"
then
  if ! echo "$PATH" | grep -q "/opt/homebrew/bin"
  then
    export PATH="/opt/homebrew/bin:$PATH"
  fi
elif test "$(expr substr $(uname -s) 1 5)" = "Linux"
then
  if ! echo "$PATH" | grep -q "/home/linuxbrew/.linuxbrew/bin"
  then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
  fi
fi
