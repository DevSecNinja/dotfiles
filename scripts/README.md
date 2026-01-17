# 🧪 Scripts Directory

Reusable validation and testing scripts for your dotfiles repository. These scripts can be run locally during development or in CI/CD pipelines.

## 📁 Available Scripts

### Code Signing

#### `create-signing-cert.ps1`
Creates a self-signed code signing certificate for PowerShell scripts. This certificate is used by the GitHub Actions workflow to automatically sign all `.ps1` and `.ps1.tmpl` files.

**Usage** (Windows only):
```powershell
# Generate certificate and setup files
.\scripts\create-signing-cert.ps1

# Follow the on-screen instructions to upload secrets to GitHub
```

**What it does:**
- Creates a self-signed certificate valid for 5 years
- Exports it as a password-protected PFX file
- Generates a base64-encoded file for GitHub Secrets
- Displays step-by-step instructions for GitHub setup

**GitHub Secrets Required:**
- `CODE_SIGNING_CERT`: Base64-encoded certificate (from cert-base64-*.txt file)
- `CODE_SIGNING_PASSWORD`: Certificate password you entered

**GitHub Actions Integration:**
The workflow at `.github/workflows/sign-powershell.yml` automatically signs all PowerShell scripts when changes are pushed to the main branch.

---

### Validation Scripts

#### `validate-chezmoi.sh`
Validates that Chezmoi can read and parse the configuration.

```bash
./scripts/validate-chezmoi.sh [source-dir]
```

**What it does:**
- Installs Chezmoi if not present
- Verifies configuration syntax
- Reads and displays Chezmoi data

**Example:**
```bash
./scripts/validate-chezmoi.sh
./scripts/validate-chezmoi.sh /path/to/dotfiles
```

---

#### `validate-shell-scripts.sh`
Checks all shell scripts for syntax errors.

```bash
./scripts/validate-shell-scripts.sh [source-dir]
```

**What it does:**
- Finds all `.sh` and `.sh.tmpl` files
- Validates syntax with `sh -n`
- Reports any syntax errors

**Example:**
```bash
./scripts/validate-shell-scripts.sh
```

---

#### `validate-fish-config.sh`
Validates Fish shell configuration files.

```bash
./scripts/validate-fish-config.sh [source-dir]
```

**What it does:**
- Installs Fish if not present
- Validates all `.fish` files
- Checks for syntax errors

**Example:**
```bash
./scripts/validate-fish-config.sh
```

---

### Testing Scripts

#### `test-chezmoi-apply.sh`
Tests Chezmoi apply in dry-run mode.

```bash
./scripts/test-chezmoi-apply.sh [source-dir]
```

**What it does:**
- Runs `chezmoi init --apply --dry-run`
- Simulates file application without making changes
- Verifies no errors occur during application

**Example:**
```bash
./scripts/test-chezmoi-apply.sh
```

---

#### `test-fish-config.sh`
Tests Fish shell configuration.

```bash
./scripts/test-fish-config.sh
```

**What it does:**
- Verifies Fish is installed
- Tests Fish can start with your config
- Checks custom functions and aliases load

**Example:**
```bash
./scripts/test-fish-config.sh
```

---

#### `verify-dotfiles.sh`
Verifies dotfiles were applied correctly.

```bash
./scripts/verify-dotfiles.sh
```

**What it does:**
- Checks expected files exist in `$HOME`
- Validates dotfiles were copied correctly
- Reports missing files

**Example:**
```bash
./scripts/verify-dotfiles.sh
```

---

#### `setup-precommit.sh`
Installs and configures pre-commit hooks.

```bash
./scripts/setup-precommit.sh [--all]
```

**What it does:**
- Installs pre-commit if not present
- Sets up git hooks
- Optionally runs checks on all files (with --all)

**Example:**
```bash
# Install hooks
./scripts/setup-precommit.sh

# Install and run on all files
./scripts/setup-precommit.sh --all
```

---

### Utility Scripts

#### `validate-all.sh`
Runs all validation checks in sequence.

```bash
./scripts/validate-all.sh [source-dir]
```

**What it does:**
- Executes all validation scripts
- Provides summary of results
- Returns non-zero exit code if any check fails

**Example:**
```bash
./scripts/validate-all.sh
```

---

## 🚀 Usage Examples

### Quick Validation
```bash
# Validate everything
./scripts/validate-all.sh

# Or run individual checks
./scripts/validate-chezmoi.sh
./scripts/validate-shell-scripts.sh
./scripts/validate-fish-config.sh
```

### Pre-commit Checks
```bash
# Before committing changes
./scripts/validate-shell-scripts.sh
./scripts/test-chezmoi-apply.sh
```

### Testing After Installation
```bash
# After running ./install.sh
./scripts/verify-dotfiles.sh
chezmoi verify
```

### CI/CD Integration
These scripts are used in `.github/workflows/ci.yaml`:

```yaml
- name: Validate shell scripts
  run: ./scripts/validate-shell-scripts.sh

- name: Test Chezmoi apply
  run: ./scripts/test-chezmoi-apply.sh
```

---

## 🛠️ Customization

### Adding New Checks

1. **Create a new script:**
   ```bash
   touch scripts/validate-custom.sh
   chmod +x scripts/validate-custom.sh
   ```

2. **Follow the template:**
   ```bash
   #!/bin/bash
   set -e

   echo "🔍 Running custom validation..."

   # Your validation logic here

   echo "✅ Validation passed!"
   ```

3. **Add to CI pipeline:**
   ```yaml
   - name: Custom validation
     run: ./scripts/validate-custom.sh
   ```

### Modifying Expected Files

Edit `verify-dotfiles.sh` to add/remove expected files:

```bash
EXPECTED_FILES=(
    "$HOME/.vimrc"
    "$HOME/.tmux.conf"
    "$HOME/.mynewconfig"  # Add your file here
)
```

---

## 📊 Exit Codes

All scripts follow standard exit code conventions:

- `0` - Success
- `1` - Validation/test failed
- `127` - Command not found (missing dependency)

---

## 🔧 Dependencies

Scripts automatically install missing dependencies when possible:

- **Chezmoi**: Auto-installed if missing
- **Fish**: Auto-installed on Ubuntu/Debian/macOS
- **Standard tools**: sh, bash, curl, find, grep (usually pre-installed)

---

## 💡 Tips

1. **Run locally before pushing:**
   ```bash
   ./scripts/validate-all.sh
   ```

2. **Use in Git hooks:**
   ```bash
   # .git/hooks/pre-commit
   #!/bin/bash
   ./scripts/validate-shell-scripts.sh
   ```

3. **Debug specific issues:**
   ```bash
   # Run with verbose output
   bash -x ./scripts/validate-chezmoi.sh
   ```

4. **Test in isolation:**
   ```bash
   # Test with specific source directory
   ./scripts/test-chezmoi-apply.sh /tmp/dotfiles-test
   ```

---

## 🤝 Contributing

When adding new scripts:

1. Use `set -e` for error handling
2. Include helpful echo messages
3. Accept optional source directory parameter
4. Return appropriate exit codes
5. Make executable with `chmod +x`

---

## 📚 Related Documentation

- [README.md](../README.md) - Main documentation
- [CONTRIBUTING.md](../CONTRIBUTING.md) - Development guide
- [STRUCTURE.md](../STRUCTURE.md) - Repository structure

---

**Need help?** Run any script with `--help` or check the inline comments.
