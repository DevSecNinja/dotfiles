#!/bin/bash
# work-checklist - Manual post-install steps for work (Microsoft) machines.
#
# Many work-only setup steps can't be automated by chezmoi: they involve
# corporate URLs that require the work network/VPN, browser-based MFA
# enrollment, or actions that must be taken in a specific browser profile.
# This helper prints the checklist so it's one command away on any new
# machine instead of buried in a wiki tab.
#
# It is intentionally non-interactive and side-effect free: it only
# prints. The URLs themselves are public-facing aka.ms / Microsoft URLs
# that resolve to corporate sign-in pages — viewing them does nothing
# without authenticated session.
#
# Usage: work-checklist

work-checklist() {
	cat <<'EOF'
Work machine — manual post-install checklist

These steps can't be automated by chezmoi (network-gated, browser flows,
or per-user MFA enrollment). Tick each one off after running install.sh.

  [ ] CloudMFA enrollment
        Open: https://aka.ms/CloudMFA
        Required for corporate SSO; resolves only on the work network/VPN.

  [ ] YubiKey: enroll for SSH + Git signing
        Run:  yk-enroll
        Then: yk-enroll --rotate-pin   # if FIPS, change the factory PIN

  [ ] Add YubiKey SSH pubkey(s) to GitHub — BOTH types per key
        For each ~/.ssh/id_ed25519_sk_<serial>.pub:
          gh ssh-key add <path> --type authentication --title "<title>"
          gh ssh-key add <path> --type signing       --title "<title>"
        Or via the GitHub UI:  https://github.com/settings/keys
        Signing isn't useful without the second one (no Verified badge).

  [ ] Wire git for SSH commit signing
        chezmoi apply                  # writes ~/.config/git/config + allowed_signers
        yk-git-sign-setup              # registers your pubkey(s) as trusted signers
        yk-git-sign-setup --check

  [ ] Sign in to GitHub CLI:        gh auth login
  [ ] Sign in to Azure CLI:         az login
  [ ] Sign in to 1Password CLI:     op signin   (if used)

Re-run `work-checklist` any time to see this list again.
EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	work-checklist "$@"
fi
