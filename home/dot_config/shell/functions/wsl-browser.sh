#!/bin/bash
# WSL -> Windows browser integration for Bash and Zsh.
#
# A WSL distro has no graphical browser and no xdg-open. Tools that "open a
# browser" — `gh auth login`, OAuth flows, `npm docs` — fall back to whatever
# terminal browser is installed (lynx, w3m), which is a miserable way to
# complete an OAuth flow. Pointing BROWSER at the wsl-browser helper in
# ~/.local/bin fixes every such tool at once. See docs/wsl.md.
#
# Guarded on WSL_DISTRO_NAME (set by WSL itself) so this never leaks into a
# native Linux or macOS session, and on powershell.exe being reachable, which
# requires WSL interop to be enabled.

if [ -n "${WSL_DISTRO_NAME:-}" ] && command -v powershell.exe >/dev/null 2>&1 &&
    [ -x "${HOME}/.local/bin/wsl-browser" ]; then
    BROWSER="${HOME}/.local/bin/wsl-browser"
    export BROWSER
fi
