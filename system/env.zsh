if ! command -v code &> /dev/null
then
  export EDITOR='code'
else
  export EDITOR='nano'
fi
