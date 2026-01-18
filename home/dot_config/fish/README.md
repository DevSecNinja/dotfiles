# 🐠 Fish Shell Configuration

This directory contains your Fish shell configuration managed by Chezmoi.

## 📂 Directory Structure

```
fish/
├── config.fish           # Main configuration (loaded on shell start)
├── conf.d/              # Configuration snippets (auto-loaded)
│   └── aliases.fish     # Command aliases
├── functions/           # Custom Fish functions
│   └── fish_greeting.fish
└── completions/         # Custom tab completions
```

## 🔄 Load Order

1. **conf.d/*.fish** - Loaded first, in alphabetical order
2. **config.fish** - Main config file
3. **functions/** - Functions loaded on-demand

## ✏️ Customization

### Adding Aliases

Edit [conf.d/aliases.fish](conf.d/aliases.fish):

```fish
# Add your custom aliases
alias myalias 'my command here'
```

### Creating Functions

Create a new file in [functions/](functions/):

```bash
# File: functions/myfunction.fish
function myfunction
    echo "Hello from my function!"
end
```

The function name **must match** the filename (without .fish extension).

### Adding Completions

Create completion files in [completions/](completions/):

```bash
# File: completions/mycommand.fish
complete -c mycommand -s h -l help -d 'Show help'
```

## 🎨 Tips

- **List all aliases**: `alias`
- **List all functions**: `functions`
- **Get function source**: `functions function_name`
- **Edit config**: `chezmoi edit ~/.config/fish/config.fish`
- **Reload config**: Close and reopen terminal, or run `source ~/.config/fish/config.fish`

## 📚 Learning Resources

- [Fish Tutorial](https://fishshell.com/docs/current/tutorial.html)
- [Fish Documentation](https://fishshell.com/docs/current/)
- [Fish Functions](https://fishshell.com/docs/current/language.html#functions)
- [Fish Completions](https://fishshell.com/docs/current/completions.html)

## 🚀 Useful Fish Features

### Command Substitution
```fish
echo (date)
```

### Variables
```fish
set -gx MY_VAR "value"  # Global export
set -l my_var "value"   # Local variable
```

### Conditionals
```fish
if test -f myfile
    echo "File exists"
end
```

### Loops
```fish
for file in *.txt
    echo $file
end
```

---

**Managed by Chezmoi** - Edit via `chezmoi edit`, not directly!
