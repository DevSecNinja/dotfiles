if $(code &>/dev/null)
then
  export EDITOR='code'
else
  export EDITOR='nano'
fi

# History

export HISTSIZE=32768;
export HISTFILESIZE="${HISTSIZE}";
export SAVEHIST=4096
export HISTCONTROL=ignoredups:erasedups
