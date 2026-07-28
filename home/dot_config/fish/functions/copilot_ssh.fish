function copilot_ssh --description "SSH with COPILOT_GITHUB_TOKEN and GH_TOKEN forwarded from a 1Password Environment"
    # copilot_ssh - SSH into a host with GitHub tokens forwarded from 1Password.
    #
    # Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present,
    # GH_TOKEN (for the GitHub CLI) from a 1Password Environment on this
    # (workstation) machine via `op run`, then forwards them to the remote
    # session using SSH SendEnv, so both tools can authenticate on headless
    # servers that have no secure vault. The tokens are never written to disk.
    #
    # The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` (handled by
    # the docker repo's system_setup Ansible role). Copilot CLI reads
    # COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); `gh` reads GH_TOKEN.
    #
    # Requirements:
    #   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration.
    #   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (from the
    #     chezmoi `opCopilotEnvironmentId` variable). The Environment must contain
    #     COPILOT_GITHUB_TOKEN; GH_TOKEN is optional (forwarded if present).
    #
    # Usage: copilot_ssh [ssh options...] <host>   (e.g. copilot_ssh svldev)
    #
    # Pre-flight: before unlocking 1Password, a short TCP probe checks that the
    # host's SSH port answers, so an unreachable host fails in ~3s instead of
    # hanging. When the probe fails and the Azure CLI is installed, the VM is
    # looked up by name (`az vm list -d`); if it is stopped/deallocated you are
    # offered to start it and the connection continues once the port is up.
    #
    # Environment:
    #   COPILOT_SSH_SKIP_PREFLIGHT=1   Skip the reachability probe entirely
    #   COPILOT_SSH_PREFLIGHT_TIMEOUT  TCP probe timeout in seconds (default 3)
    #   COPILOT_SSH_START_TIMEOUT      Wait for SSH after `az vm start` (def. 180)
    #   COPILOT_SSH_ASSUME_YES=1       Start a stopped VM without asking

    if contains -- -h $argv; or contains -- --help $argv
        echo "Usage: copilot_ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment."
        return 0
    end

    # Fail fast on an unreachable host before unlocking 1Password.
    if not _copilot_ssh_preflight $argv
        return 1
    end

    if not command -q op
        echo "copilot_ssh: 'op' (1Password CLI) not found; using plain ssh (no token forwarded)." >&2
        command ssh $argv
        return
    end

    if test -z "$OP_COPILOT_ENVIRONMENT_ID"
        echo "copilot_ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh $argv
        return
    end

    # Read both tokens in a single `op run` (one 1Password unlock) so the
    # interactive ssh below is not wrapped by op run. `--no-masking` is required
    # because Environment values are hidden by default. Tab-separated because
    # GitHub tokens never contain a tab.
    set -l tab (printf '\t')
    set -l creds (op run --environment "$OP_COPILOT_ENVIRONMENT_ID" --no-masking -- sh -c 'printf "%s\t%s" "${COPILOT_GITHUB_TOKEN:-}" "${GH_TOKEN:-}"' 2>/dev/null)
    set -l op_status $status
    if test $op_status -ne 0
        echo "copilot_ssh: failed to read tokens from 1Password Environment '$OP_COPILOT_ENVIRONMENT_ID'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02, the desktop-app integration is enabled, and the Environment ID is correct." >&2
        return 1
    end

    set -l parts (string split -- $tab $creds)
    set -l copilot_token $parts[1]
    set -l gh_token ""
    if test (count $parts) -ge 2
        set gh_token $parts[2]
    end

    if test -z "$copilot_token"
        echo "copilot_ssh: COPILOT_GITHUB_TOKEN not found in Environment '$OP_COPILOT_ENVIRONMENT_ID'." >&2
        return 1
    end

    # Forward COPILOT_GITHUB_TOKEN always; GH_TOKEN only when it is set.
    set -l ssh_env_opts -o SendEnv=COPILOT_GITHUB_TOKEN
    if test -n "$gh_token"
        set -a ssh_env_opts -o SendEnv=GH_TOKEN
    end

    # Export the tokens locally (function-scoped) for the ssh child, and use
    # `command ssh` to avoid any alias/function shadowing (matches the fallback
    # branches above).
    set -lx COPILOT_GITHUB_TOKEN $copilot_token
    set -lx GH_TOKEN $gh_token
    command ssh $ssh_env_opts $argv
end

# Completions: delegate to ssh's own completions for host/option arguments.
complete -c copilot_ssh -w ssh

# --- pre-flight reachability helpers ---------------------------------------
# Defined alongside copilot_ssh: fish sources this whole file when it autoloads
# copilot_ssh, so these helpers come along with it.

function _copilot_ssh_tcp_probe --description "TCP probe: 0 open, 1 closed, 2 undetermined" --argument-names host port timeout_s
    if command -q nc
        command nc -z -w $timeout_s $host $port >/dev/null 2>&1
        return $status
    end
    if command -q timeout; and command -q bash
        # /dev/tcp is a bash feature; run it in a child process.
        command timeout $timeout_s bash -c "exec 3<>/dev/tcp/$host/$port" >/dev/null 2>&1
        return $status
    end
    return 2
end

function _copilot_ssh_resolve --description "Print 'hostname port' as ssh resolves it for the given args"
    set -l config (command ssh -G $argv 2>/dev/null)
    or return 0
    set -l host ""
    set -l port ""
    for line in $config
        set -l parts (string split -m 1 ' ' -- $line)
        if test (count $parts) -lt 2
            continue
        end
        switch $parts[1]
            case hostname
                set host $parts[2]
            case port
                set port $parts[2]
        end
    end
    if test -z "$host"
        return 0
    end
    test -n "$port"; or set port 22
    echo "$host $port"
end

function _copilot_ssh_az_lookup --description "Print 'name resourceGroup powerState' for Azure VMs matching a host" --argument-names host
    # Match the VM name against the host and its short form
    # (vm01.example.com -> vm01), then fall back to the VM's public/private IPs.
    set -l short (string split -m 1 '.' -- $host)[1]
    set -l lhost (string lower -- $host)
    set -l lshort (string lower -- $short)

    set -l rows (az vm list -d --only-show-errors -o tsv \
        --query '[].[name,resourceGroup,powerState,publicIps,privateIps]' 2>/dev/null)
    or return 0

    for row in $rows
        set -l cols (string split \t -- $row)
        if test (count $cols) -lt 3
            continue
        end
        set -l name (string lower -- $cols[1])
        if test "$name" = "$lhost" -o "$name" = "$lshort"
            echo "$cols[1]"\t"$cols[2]"\t"$cols[3]"
            continue
        end
        # publicIps/privateIps may hold a comma-separated list.
        set -l ips
        for field in $cols[4..-1]
            set -a ips (string trim -- (string split ',' -- $field))
        end
        if contains -- $host $ips
            echo "$cols[1]"\t"$cols[2]"\t"$cols[3]"
        end
    end
end

function _copilot_ssh_confirm --description "Ask a yes/no question; always no when non-interactive" --argument-names prompt
    test "$COPILOT_SSH_ASSUME_YES" = 1; and return 0
    isatty stdin; or return 1
    read -l -P "$prompt [y/N] " reply
    or return 1
    string match -qir '^(y|yes)$' -- $reply
end

function _copilot_ssh_wait_for_ssh --description "Poll an SSH port until it answers" --argument-names host port
    set -l limit (test -n "$COPILOT_SSH_START_TIMEOUT"; and echo $COPILOT_SSH_START_TIMEOUT; or echo 180)
    set -l waited 0

    printf 'copilot_ssh: waiting for %s:%s to accept connections' $host $port >&2
    while test $waited -lt $limit
        if _copilot_ssh_tcp_probe $host $port 3
            printf ' up\n' >&2
            return 0
        end
        printf '.' >&2
        sleep 5
        set waited (math $waited + 5)
    end
    printf ' timed out\n' >&2
    return 1
end

function _copilot_ssh_recover_azure --description "Try to bring a stopped Azure VM back up" --argument-names host port
    if not command -q az
        echo "copilot_ssh: install the Azure CLI ('az') to check whether the VM is stopped." >&2
        return 1
    end

    echo "copilot_ssh: looking up '$host' in Azure..." >&2
    set -l matches (_copilot_ssh_az_lookup $host)

    if test (count $matches) -eq 0
        echo "copilot_ssh: no Azure VM matches '$host' in the current subscription." >&2
        echo "            Check 'az account show' / 'az login', or the host may not be an Azure VM." >&2
        return 1
    end

    if test (count $matches) -gt 1
        echo "copilot_ssh: several Azure VMs match '$host'; not guessing:" >&2
        for match in $matches
            set -l cols (string split \t -- $match)
            echo "            - $cols[1] (resource group $cols[2], $cols[3])" >&2
        end
        return 1
    end

    set -l cols (string split \t -- $matches[1])
    set -l vm_name $cols[1]
    set -l vm_rg $cols[2]
    set -l vm_state $cols[3]

    if string match -q '*running*' -- $vm_state
        echo "copilot_ssh: Azure VM '$vm_name' is running but $host:$port is unreachable." >&2
        echo "            Check the NSG rules, the VPN/network path or sshd on the VM." >&2
        return 1
    end

    echo "copilot_ssh: Azure VM '$vm_name' (resource group $vm_rg) is $vm_state." >&2
    if not _copilot_ssh_confirm "copilot_ssh: start it now?"
        echo "copilot_ssh: not starting the VM; aborting." >&2
        return 1
    end

    if not az vm start --only-show-errors -g $vm_rg -n $vm_name >/dev/null
        echo "copilot_ssh: 'az vm start' failed for '$vm_name'." >&2
        return 1
    end
    echo "copilot_ssh: started '$vm_name'." >&2

    _copilot_ssh_wait_for_ssh $host $port
end

function _copilot_ssh_preflight --description "Fail fast when the SSH host is unreachable"
    if test "$COPILOT_SSH_SKIP_PREFLIGHT" = 1
        return 0
    end

    set -l resolved (_copilot_ssh_resolve $argv)
    # No destination resolved (e.g. ssh could not parse the args): skip the
    # probe rather than blocking a connection that might still work.
    if test (count $resolved) -eq 0
        return 0
    end
    set -l parts (string split ' ' -- $resolved[1])
    set -l host $parts[1]
    set -l port $parts[2]

    set -l timeout_s (test -n "$COPILOT_SSH_PREFLIGHT_TIMEOUT"; and echo $COPILOT_SSH_PREFLIGHT_TIMEOUT; or echo 3)
    _copilot_ssh_tcp_probe $host $port $timeout_s
    switch $status
        case 0 2 # reachable, or no probe tool available: let ssh decide
            return 0
    end

    echo "copilot_ssh: $host:$port is not reachable." >&2
    _copilot_ssh_recover_azure $host $port
end
