# Common aliases for Fish shell

# Navigation
alias .. 'cd ..'
alias ... 'cd ../..'
alias .... 'cd ../../..'

# List files
alias l 'ls -lah'
alias la 'ls -A'
alias ll 'ls -lh'

# Git shortcuts
alias g 'git'
alias gs 'git status'
alias ga 'git add'
alias gc 'git commit'
alias gps 'git push'
alias gpl 'git pull'
alias gl 'git log --oneline --graph'
alias gd 'git diff'
alias gco 'git checkout'
alias gb 'git branch'

# Lefthook shortcut (run all pre-commit hooks across the repo)
alias pc 'lefthook run pre-commit --all-files'

# Safety
alias rm 'rm -i'
alias cp 'cp -i'
alias mv 'mv -i'

# Chezmoi shortcuts
alias cz 'chezmoi'
alias czd 'chezmoi diff'
alias cza 'chezmoi apply'
alias cze 'chezmoi edit'

# Docker shortcuts
alias d 'docker'
alias dc 'docker compose'
alias dps 'docker ps'
alias dpsa 'docker ps -a'
alias di 'docker images'
alias dex 'docker exec -it'

# Shell introspection
alias aliases "alias | sed 's/=.*//'"
# alias functions - Already built-in in Fish
alias paths 'string split : $PATH'

# System info
alias ff 'fastfetch'
alias sysinfo 'fastfetch'
alias motd 'fastfetch'

# SSH
# Print the first available public key (preferring hardware-backed) and copy
# it to the system clipboard via clipboard_copy (auto-detects backend).
# Discovers both the legacy un-suffixed `id_<type>_sk.pub` and per-serial
# `id_<type>_sk_<serial>.pub` files written by `yk_enroll`.
function pubkey --description "Print and copy the first available SSH public key"
    set -l key
    # Prefer hardware-backed FIDO2 keys: per-serial files first, then
    # legacy un-suffixed, then non-FIDO2.
    for pattern in \
            "$HOME/.ssh/id_ed25519_sk_"*.pub \
            "$HOME/.ssh/id_ed25519_sk.pub" \
            "$HOME/.ssh/id_ecdsa_sk_"*.pub \
            "$HOME/.ssh/id_ecdsa_sk.pub" \
            "$HOME/.ssh/id_ed25519.pub" \
            "$HOME/.ssh/id_rsa.pub"
        for candidate in $pattern
            if test -f "$candidate"
                set key "$candidate"
                break
            end
        end
        test -n "$key"; and break
    end
    if test -z "$key"
        echo "No SSH public key found in ~/.ssh" >&2
        return 1
    end
    cat $key
    if functions -q clipboard_copy; and clipboard_copy --check >/dev/null 2>&1
        clipboard_copy <$key
        echo "=> Public key ("(basename $key)") copied to clipboard."
    else
        echo "=> "(basename $key)" (no clipboard backend; not copied)."
    end
end

echo "✅ Aliases loaded"
