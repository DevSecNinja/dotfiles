# Install the correct homebrew for each OS type
if test "$(uname)" = "Darwin"
then
  export PATH="/opt/homebrew/bin:$PATH"
elif test "$(expr substr $(uname -s) 1 5)" = "Linux"
then
  export PATH="/home/linuxbrew/.linuxbrew/bin/brew:$PATH"
fi