# Test Coverage Overview

Last regenerated: April 2026 (PR #220 — Phase 2-4)

This document tracks the test coverage for every script and function in the
repository. It is updated whenever new tests are added.

## Summary

| Category | Total | Tested | Coverage |
|----------|------:|-------:|---------:|
| Shell functions (`home/dot_config/shell/functions/*.sh`) | 18 | 13 | 72% |
| Fish functions (`home/dot_config/fish/functions/*.fish`) | 13 | 6 | 46% |
| PowerShell module functions (`DotfilesHelpers/Public/*.ps1`) | 16 | 16 | **100%** |
| PowerShell aliases (`aliases.ps1`) | 21 | 21 | **100%** |
| Chezmoi run scripts (`home/.chezmoiscripts/`) | 11 | 11 | **100%** |
| Installation scripts (`install.sh`, `install.ps1`) | 2 | 2 | **100%** |
| **Total tracked items** | **81** | **69** | **85%** |

| Test framework | Test files | Test cases |
|----------------|-----------:|-----------:|
| Bats (Bash)    | 36         | 413        |
| Pester (PS)    | 13         | 315        |
| **Total**      | **49**     | **728**    |

> _Coverage percentage refers to **the fraction of source items that have at
> least one test**. Bats and Pester do not natively measure line/branch
> coverage; for Bash-line coverage you would need a tool like
> [kcov](https://github.com/SimonKagstrom/kcov)._

## Shell Functions (`home/dot_config/shell/functions/`)

| Function | Test file | Notes |
|----------|-----------|-------|
| `brewup.sh` | `brewup.bats` | ✅ |
| `calculate-points-value.sh` | `calculate-points-value.bats` | ✅ |
| `dns-flush.sh` | `dns-flush.bats` | ✅ |
| `extract-file.sh` | `extract-file.bats` | ✅ |
| `file-set-execution-bit.sh` | `file-set-execution-bit.bats` | ✅ |
| `find-broken-symlinks.sh` | `find-broken-symlinks.bats` | ✅ |
| `generate-passwords.sh` | `generate-passwords.bats` | ✅ |
| `get-external-ip.sh` | `get-external-ip.bats` | ✅ |
| `get-internal-ip.sh` | `get-internal-ip.bats` | ✅ |
| `gh-add-ssh-keys.sh` | `gh-add-ssh-keys.bats` | ✅ |
| `gh-check-ssh-keys.sh` | `gh-check-ssh-keys.bats` | ✅ |
| `git-https-to-ssh.sh` | `git-https-to-ssh.bats` | ✅ |
| `silent-background.sh` | `silent-background.bats` | ✅ |
| `git-release.sh` | _none_ | ⚠️ Untested |
| `git-undo.sh` | _none_ | ⚠️ Untested |
| `git-update-forked-repo.sh` | _none_ | ⚠️ Untested |
| `mcd.sh` | _none_ | ⚠️ Untested |
| `refreshenv.sh` | _none_ | ⚠️ Untested |

## Fish Functions (`home/dot_config/fish/functions/`)

| Function | Test file | Notes |
|----------|-----------|-------|
| `chezmoi_reset.fish` | `chezmoi_reset.bats` | ✅ |
| `dns_flush.fish` | `dns_flush.bats` | ✅ |
| `extract_file.fish` | `extract_file.bats` | ✅ |
| `fish_greeting.fish` | `test-fish-config.bats` | ✅ Loading + syntax |
| `generate_passwords.fish` | `generate_passwords.bats` | ✅ |
| `get_external_ip.fish` | `get_external_ip.bats` | ✅ |
| `get_internal_ip.fish` | `get_internal_ip.bats` | ✅ |
| `check_video_codecs.fish` | _none_ | ⚠️ Untested |
| `git_https_to_ssh.fish` | _none_ | ⚠️ Untested |
| `git_new_branch.fish` | _none_ | ⚠️ Untested |
| `git_undo_commit.fish` | _none_ | ⚠️ Untested |
| `mcd.fish` | _none_ | ⚠️ Untested |
| `refreshenv.fish` | _none_ | ⚠️ Untested |

`_template.fish` is excluded as it is a template, not a real function.

## PowerShell Module Functions (`DotfilesHelpers/Public/`)

| Function | Test file | Notes |
|----------|-----------|-------|
| `Test-WingetUpdates` | `WingetUpgrade.Tests.ps1` | ✅ |
| `Invoke-WingetUpgrade` | `WingetUpgrade.Tests.ps1` | ✅ |
| `Reset-ChezmoiScripts` | `ChezmoiUtilities.Tests.ps1` | ✅ |
| `Reset-ChezmoiEntries` | `ChezmoiUtilities.Tests.ps1` | ✅ |
| `Invoke-ChezmoiSigning` | `ChezmoiUtilities.Tests.ps1` | ✅ |
| `Install-PowerShellModule` | `ModuleInstallation.Tests.ps1` | ✅ |
| `Install-GitPowerShellModule` | `ModuleInstallation.Tests.ps1` | ✅ Path-traversal + URL allow-list |
| `Add-ToPSModulePath` | `ModuleInstallation.Tests.ps1` | ✅ Idempotency |
| `Set-LocationUp` | `Navigation.Tests.ps1` | ✅ |
| `Set-LocationUpUp` | `Navigation.Tests.ps1` | ✅ |
| `Edit-Profile` | `ProfileManagement.Tests.ps1` | ✅ |
| `Import-Profile` | `ProfileManagement.Tests.ps1` | ✅ |
| `Show-Aliases` | `ProfileManagement.Tests.ps1` | ✅ |
| `which` | `SystemUtilities.Tests.ps1` | ✅ |
| `touch` | `SystemUtilities.Tests.ps1` | ✅ |
| `mkcd` | `SystemUtilities.Tests.ps1` | ✅ |

## PowerShell Aliases (`aliases.ps1`)

All 21 aliases and helper functions are covered by `Aliases.Tests.ps1`:

- Navigation: `..`, `...`
- Listing: `ll`, `la`
- Git: `g`, `gs`, `ga`, `gc`, `gps`, `gpl`, `gl`, `gd`, `gco`, `gb`
- Docker: `d`, `dc`, `dps`, `dpsa`, `di`, `dex`
- Profile: `ep`, `reload`, `aliases`
- Introspection: `paths`, `functions`
- System info: `ff`, `sysinfo`, `motd`
- SSH: `pubkey`
- Winget: `wup`, `winup`

## Chezmoi Run Scripts (`home/.chezmoiscripts/`)

All chezmoi run scripts are exercised structurally by `test-chezmoi-scripts.bats`
(syntax after stripping templates, idempotency markers, mode handling, etc.):

- Linux: `run_once_before_00-setup.sh.tmpl`, `run_once_before_01-install-ppas.sh.tmpl`,
  `run_once_before_05-install-homebrew.sh.tmpl`, `run_once_install-precommit.sh.tmpl`,
  `run_once_setup-precommit.sh`, `run_once_setup-gh-telemetry.sh`,
  `run_onchange_00-apt-upgrade.sh.tmpl`, `run_onchange_01-brew-upgrade.sh.tmpl`,
  `run_onchange_02-mise-upgrade.sh.tmpl`, `run_onchange_10-install-packages.sh.tmpl`
- Darwin: `run_once_before_10-setup-fish-default-shell.sh.tmpl`

## Installation Scripts

| Script | Test file |
|--------|-----------|
| `install.sh` (root wrapper) | `validate-shell-scripts.bats` (syntax) |
| `install.ps1` (root wrapper) | `Install.Tests.ps1` |
| `home/install.sh` | `validate-shell-scripts.bats` (syntax), `test-install` CI job (E2E) |
| `home/install.ps1` | `Install.Tests.ps1` |

## Generating coverage locally

```bash
# Bash test counts
ls tests/bash/*.bats | wc -l                    # Test files
grep -h '^@test' tests/bash/*.bats | wc -l       # Test cases

# PowerShell test counts
ls tests/powershell/*.Tests.ps1 | wc -l          # Test files
grep -hE '^\s+It [\"'\'']' tests/powershell/*.Tests.ps1 | wc -l   # Test cases
```

## Untested items - planned next steps

The five remaining untested shell functions and seven fish functions are git
helpers with destructive side effects (`git-release`, `git-undo`, etc.) and
small wrappers (`mcd`, `refreshenv`). Tests for these are tracked under the
[Test Coverage Gaps issue](../../../issues?q=test+coverage+gaps).
