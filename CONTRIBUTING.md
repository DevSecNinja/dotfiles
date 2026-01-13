# Contributing to Dotfiles

## Making Changes

### Local Development

1. **Edit files in the repository**:
   ```bash
   cd /path/to/dotfiles-new
   # Edit files directly
   vim dot_config/fish/config.fish
   ```

2. **Test your changes**:
   ```bash
   # Dry run to see what would happen
   chezmoi apply --dry-run --source=.

   # Apply locally for testing
   chezmoi apply --source=.
   ```

3. **Verify everything works**:
   ```bash
   chezmoi verify
   ```

### Adding New Configurations

#### Adding a new dotfile

```bash
# If file already exists in your home
chezmoi add ~/.newconfig

# Or create directly in the repo
touch dot_newconfig
```

#### Adding a new script

```bash
# Create a new installation script
touch run_once_install-newtool.sh.tmpl
chmod +x run_once_install-newtool.sh.tmpl
```

#### Adding Fish functions

```bash
# Create a new function file
vim dot_config/fish/functions/mynewfunction.fish
```

### Testing Changes

The CI pipeline runs automatically on push and will:
- 🎯 Run pre-commit hooks (formatting, linting)
- ✅ Validate all shell script syntax
- ✅ Check Fish configuration files
- ✅ Run dry-run installation
- ✅ Verify all managed files
- ✅ Test Fish configuration loads correctly

You can run similar checks locally:

```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Run pre-commit checks
pre-commit run --all-files

# Or install hooks to run automatically on commit
./scripts/setup-precommit.sh

# Check shell script syntax
find . -name "*.sh" -type f -exec sh -n {} \;

# Check Fish files (if Fish is installed)
fish -n dot_config/fish/config.fish
```

## Best Practices

1. **Keep it simple**: Don't overcomplicate configurations
2. **Document changes**: Add comments to explain complex configurations
3. **Test before commit**: Always test with `chezmoi apply --dry-run`
4. **Use templates wisely**: Only use `.tmpl` when you need Chezmoi variables
5. **Organize logically**: Group related configurations together

## Questions?

Check the [README.md](README.md) and [STRUCTURE.md](STRUCTURE.md) for more information.
