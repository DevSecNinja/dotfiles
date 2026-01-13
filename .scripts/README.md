# Chezmoi Scripts Directory

This directory contains scripts that Chezmoi runs automatically:

## Script Types

### `run_once_*`
Scripts that run only once, even after updates. Chezmoi tracks their execution.

### `run_onchange_*`
Scripts that run when their content changes.

### `run_*`
Scripts that run every time you apply your dotfiles.

### Execution Order
Scripts with numerical prefixes (e.g., `00-setup.sh`, `01-install.sh`) run in order.

## Current Scripts

- **00-setup.sh**: Creates necessary directories
- **install-fish.sh**: Installs Fish shell
- **install-packages.sh**: Installs common development tools

## Customization

Edit these scripts to match your needs. Use `.tmpl` extension to leverage Chezmoi templating.
