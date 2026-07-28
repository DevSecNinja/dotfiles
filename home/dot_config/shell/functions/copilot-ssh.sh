#!/bin/bash
# copilot-ssh - SSH into a host with GitHub tokens forwarded from 1Password.
#
# Reads COPILOT_GITHUB_TOKEN (for GitHub Copilot CLI) and, if present, GH_TOKEN
# (for the GitHub CLI) from a 1Password Environment on this (workstation)
# machine via `op run`, then forwards them to the remote session using SSH
# SendEnv. This lets both tools authenticate on headless servers that have no
# secure vault (no gnome-keyring needed). The tokens are never written to disk;
# they live only in 1Password, transiently in this function's memory, the
# encrypted SSH channel, and the remote session's environment.
#
# The remote sshd must `AcceptEnv COPILOT_GITHUB_TOKEN GH_TOKEN` (handled by the
# docker repo's `system_setup` Ansible role). Copilot CLI reads
# COPILOT_GITHUB_TOKEN (precedence over GH_TOKEN); the `gh` CLI reads GH_TOKEN.
# Using separate variables keeps each tool's token independently scoped.
#
# Requirements:
#   - 1Password CLI (`op`) >= 2.33.0-beta.02 with the desktop-app integration on.
#   - OP_COPILOT_ENVIRONMENT_ID set to your 1Password Environment ID (rendered
#     from the chezmoi `opCopilotEnvironmentId` variable). The Environment must
#     contain COPILOT_GITHUB_TOKEN; GH_TOKEN is optional (forwarded if present).
#
# Usage: copilot-ssh [ssh options...] <host>
#   e.g. copilot-ssh svldev
#
# If `op` or the Environment ID is unavailable, it falls back to a plain ssh so
# the command still connects (the tools just won't receive a token).
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
#   COPILOT_SSH_START_TIMEOUT      Wait for SSH after `az vm start` (default 180)
#   COPILOT_SSH_ASSUME_YES=1       Start a stopped VM without asking
#   COPILOT_SSH_ASSUME_NO=1        Never start a VM, even on a TTY

# _copilot_ssh_tcp_probe HOST PORT TIMEOUT -> 0 open, 1 closed, 2 undetermined.
_copilot_ssh_tcp_probe() {
    local host="${1}" port="${2}" timeout_s="${3}"

    if command -v nc >/dev/null 2>&1; then
        nc -z -w "${timeout_s}" "${host}" "${port}" >/dev/null 2>&1
        return $?
    fi

    if command -v timeout >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then
        # /dev/tcp is a bash feature; run it in a child so a build without
        # net-redirections cannot take down the caller.
        timeout "${timeout_s}" bash -c "exec 3<>/dev/tcp/${host}/${port}" >/dev/null 2>&1
        return $?
    fi

    return 2
}

# _copilot_ssh_resolve ARGS... -> print "<hostname>\t<port>" as ssh resolves it
# (honours ~/.ssh/config aliases, HostName/Port overrides and -o flags).
_copilot_ssh_resolve() {
    local config
    config="$(command ssh -G "$@" 2>/dev/null || true)"
    [ -n "${config}" ] || return 0
    awk '
        $1 == "hostname" { host = $2 }
        $1 == "port"     { port = $2 }
        END { if (host != "") printf "%s\t%s\n", host, (port == "" ? "22" : port) }
    ' <<<"${config}"
}

# _copilot_ssh_az_lookup HOST -> print "name\tresourceGroup\tpowerState" for
# matching VMs (one per line). Matches the VM name against the host and its
# short form (vm01.example.com -> vm01), then falls back to matching the host
# against the VM's public/private IPs.
_copilot_ssh_az_lookup() {
    local host="${1}" short="${1%%.*}" vms
    vms="$(az vm list -d --only-show-errors -o tsv \
        --query '[].[name,resourceGroup,powerState,publicIps,privateIps]' 2>/dev/null || true)"
    [ -n "${vms}" ] || return 0

    awk -F'\t' -v host="${host}" -v short="${short}" '
        BEGIN { lhost = tolower(host); lshort = tolower(short) }
        {
            name = tolower($1)
            if (name == lhost || name == lshort) { print $1 "\t" $2 "\t" $3; next }
            # publicIps/privateIps may hold a comma-separated list.
            n = split($4 "," $5, ips, ",")
            for (i = 1; i <= n; i++) {
                gsub(/^[ \t]+|[ \t]+$/, "", ips[i])
                if (ips[i] != "" && ips[i] == host) { print $1 "\t" $2 "\t" $3; next }
            }
        }
    ' <<<"${vms}"
}

# _copilot_ssh_confirm PROMPT -> 0 when the user answers yes (non-interactive
# shells always answer no, so scripts never block on the prompt;
# COPILOT_SSH_ASSUME_YES=1 answers yes and COPILOT_SSH_ASSUME_NO=1 answers no
# without asking).
_copilot_ssh_confirm() {
    [ "${COPILOT_SSH_ASSUME_YES:-0}" = "1" ] && return 0
    [ "${COPILOT_SSH_ASSUME_NO:-0}" = "1" ] && return 1
    [ -t 0 ] || return 1
    local reply=""
    printf '%s [y/N] ' "${1}" >&2
    read -r reply || return 1
    case "${reply}" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
    esac
}

# _copilot_ssh_wait_for_ssh HOST PORT -> poll the SSH port until it answers.
_copilot_ssh_wait_for_ssh() {
    local host="${1}" port="${2}" waited=0
    local limit="${COPILOT_SSH_START_TIMEOUT:-180}"

    printf 'copilot-ssh: waiting for %s:%s to accept connections' "${host}" "${port}" >&2
    while [ "${waited}" -lt "${limit}" ]; do
        _copilot_ssh_tcp_probe "${host}" "${port}" 3
        case $? in
        0)
            printf ' up\n' >&2
            return 0
            ;;
        2)
            # No probe tool available: don't spin for the whole timeout,
            # let ssh report the real state instead.
            printf ' (cannot probe)\n' >&2
            return 0
            ;;
        *) ;;
        esac
        printf '.' >&2
        sleep 5
        waited=$((waited + 5))
    done
    printf ' timed out\n' >&2
    return 1
}

# _copilot_ssh_recover_azure HOST PORT -> try to bring an Azure VM back up.
# Returns 0 when the host is reachable again, 1 otherwise.
_copilot_ssh_recover_azure() {
    local host="${1}" port="${2}"

    if ! command -v az >/dev/null 2>&1; then
        echo "copilot-ssh: install the Azure CLI ('az') to check whether the VM is stopped." >&2
        return 1
    fi

    echo "copilot-ssh: looking up '${host}' in Azure..." >&2
    local matches
    matches="$(_copilot_ssh_az_lookup "${host}")"

    if [ -z "${matches}" ]; then
        echo "copilot-ssh: no Azure VM matches '${host}' in the current subscription." >&2
        echo "            Check 'az account show' / 'az login', or the host may not be an Azure VM." >&2
        return 1
    fi

    local match_count
    match_count="$(wc -l <<<"${matches}")"
    if [ "${match_count}" -gt 1 ]; then
        echo "copilot-ssh: several Azure VMs match '${host}'; not guessing:" >&2
        awk -F'\t' '{ printf "            - %s (resource group %s, %s)\n", $1, $2, $3 }' <<<"${matches}" >&2
        return 1
    fi

    local vm_name vm_rg vm_state
    IFS=$'\t' read -r vm_name vm_rg vm_state <<<"${matches}"

    case "${vm_state}" in
    *running*)
        echo "copilot-ssh: Azure VM '${vm_name}' is running but ${host}:${port} is unreachable." >&2
        echo "            Check the NSG rules, the VPN/network path or sshd on the VM." >&2
        return 1
        ;;
    *) ;;
    esac

    echo "copilot-ssh: Azure VM '${vm_name}' (resource group ${vm_rg}) is ${vm_state:-in an unknown state}." >&2
    if ! _copilot_ssh_confirm "copilot-ssh: start it now?"; then
        echo "copilot-ssh: not starting the VM; aborting." >&2
        return 1
    fi

    if ! az vm start --only-show-errors -g "${vm_rg}" -n "${vm_name}" >/dev/null; then
        echo "copilot-ssh: 'az vm start' failed for '${vm_name}'." >&2
        return 1
    fi
    echo "copilot-ssh: started '${vm_name}'." >&2

    _copilot_ssh_wait_for_ssh "${host}" "${port}"
}

# _copilot_ssh_preflight ARGS... -> 0 when the host answers (or the check could
# not run), 1 when the connection should be abandoned.
_copilot_ssh_preflight() {
    [ "${COPILOT_SSH_SKIP_PREFLIGHT:-0}" = "1" ] && return 0

    local resolved host port
    resolved="$(_copilot_ssh_resolve "$@")"
    # No destination resolved (e.g. `ssh` could not parse the args): skip the
    # probe rather than blocking a connection that might still work.
    [ -n "${resolved}" ] || return 0
    IFS=$'\t' read -r host port <<<"${resolved}"

    _copilot_ssh_tcp_probe "${host}" "${port}" "${COPILOT_SSH_PREFLIGHT_TIMEOUT:-3}"
    case $? in
    0) return 0 ;;
    2) return 0 ;; # no probe tool available; let ssh decide
    *) ;;
    esac

    echo "copilot-ssh: ${host}:${port} is not reachable." >&2
    _copilot_ssh_recover_azure "${host}" "${port}"
}

copilot-ssh() {
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        echo "Usage: copilot-ssh [ssh options...] <host>"
        echo "SSH with COPILOT_GITHUB_TOKEN (and GH_TOKEN) forwarded from a 1Password Environment."
        return 0
    fi

    # Fail fast on an unreachable host before unlocking 1Password.
    _copilot_ssh_preflight "$@" || return 1

    if ! command -v op >/dev/null 2>&1; then
        echo "copilot-ssh: 'op' (1Password CLI) not found; using plain ssh (no token forwarded)." >&2
        command ssh "$@"
        return
    fi

    if [ -z "${OP_COPILOT_ENVIRONMENT_ID:-}" ]; then
        echo "copilot-ssh: OP_COPILOT_ENVIRONMENT_ID is not set (set the chezmoi 'opCopilotEnvironmentId' variable); using plain ssh." >&2
        command ssh "$@"
        return
    fi

    # Read both tokens in a single `op run` (one 1Password unlock) so the
    # *interactive* ssh below is not wrapped by op run, whose stdout/stderr
    # masking can disturb a TTY. `--no-masking` is required because Environment
    # values are hidden by default and would otherwise be returned as
    # "<concealed>". Tab-separated because GitHub tokens never contain a tab.
    local creds
    # SC2016: the ${…} expansions are intentionally single-quoted so they expand
    # inside the remote `sh -c`, reading the 1Password Environment values loaded
    # by `op run` — not in this local shell.
    # shellcheck disable=SC2016
    if ! creds="$(op run --environment "${OP_COPILOT_ENVIRONMENT_ID}" --no-masking -- \
        sh -c 'printf "%s\t%s" "${COPILOT_GITHUB_TOKEN:-}" "${GH_TOKEN:-}"' 2>/dev/null)"; then
        echo "copilot-ssh: failed to read tokens from 1Password Environment '${OP_COPILOT_ENVIRONMENT_ID}'." >&2
        echo "            Ensure 'op' >= 2.33.0-beta.02 and the desktop-app integration is enabled." >&2
        return 1
    fi

    local copilot_token="${creds%%$'\t'*}"
    local gh_token="${creds#*$'\t'}"

    if [ -z "${copilot_token}" ]; then
        echo "copilot-ssh: COPILOT_GITHUB_TOKEN not found in Environment '${OP_COPILOT_ENVIRONMENT_ID}'." >&2
        return 1
    fi

    # Forward COPILOT_GITHUB_TOKEN always; GH_TOKEN only when it is set.
    local -a ssh_env_opts=(-o SendEnv=COPILOT_GITHUB_TOKEN)
    if [ -n "${gh_token}" ]; then
        ssh_env_opts+=(-o SendEnv=GH_TOKEN)
    fi

    COPILOT_GITHUB_TOKEN="${copilot_token}" GH_TOKEN="${gh_token}" \
        command ssh "${ssh_env_opts[@]}" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    copilot-ssh "$@"
fi
