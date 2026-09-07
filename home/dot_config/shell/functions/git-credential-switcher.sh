#!/bin/bash
# Wrap Git push/pull so an HTTPS authentication failure can switch gh accounts.

_git_credential_switcher_operation() {
    local argument

    for argument in "$@"; do
        case "${argument}" in
        push | pull)
            printf '%s\n' "${argument}"
            return 0
            ;;
        *) ;;
        esac
    done

    return 1
}

_git_credential_switcher_host() {
    local error_file="$1"
    local auth_url
    local host

    auth_url="$(
        sed -n "s#.*fatal: Authentication failed for ['\"]\(https://[^'\"]*\)['\"].*#\1#p" "${error_file}" |
            sed -n '1p'
    )"
    [ -n "${auth_url}" ] || return 1

    host="${auth_url#https://}"
    host="${host#*@}"
    host="${host%%/*}"
    [ -n "${host}" ] || return 1

    printf '%s\n' "${host}"
}

_git_credential_switcher_can_prompt() {
    [ "${GIT_CREDENTIAL_SWITCHER_FORCE:-0}" = "1" ] || {
        [ -t 0 ] && [ -t 2 ]
    }
}

_git_credential_switcher_accounts() {
    command gh auth status --hostname "$1" --json hosts \
        --jq '.hosts | .[] | .[] | [.login, .active] | @tsv' 2>/dev/null
}

_git_credential_switcher_confirm() {
    local message="$1"
    local reply

    printf '%s [y/N] ' "${message}" >&2
    read -r reply || return 1

    case "${reply}" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
    esac
}

_git_with_credential_switch() {
    local operation="$1"
    shift

    local error_file
    local first_status
    local host
    local account_data
    local account
    local active
    local current_account=""
    local next_account=""

    error_file="$(mktemp "${TMPDIR:-/tmp}/git-auth-error.XXXXXX")" || {
        command git "$@"
        return $?
    }

    command git "$@" 2>"${error_file}"
    first_status=$?
    command cat "${error_file}" >&2

    if [ "${first_status}" -eq 0 ] ||
        ! grep -Fq "fatal: Authentication failed for" "${error_file}"; then
        command rm -f "${error_file}"
        return "${first_status}"
    fi

    host="$(_git_credential_switcher_host "${error_file}")" || {
        command rm -f "${error_file}"
        return "${first_status}"
    }
    command rm -f "${error_file}"

    if ! _git_credential_switcher_can_prompt; then
        return "${first_status}"
    fi

    if ! command -v gh >/dev/null 2>&1; then
        log_warn "GitHub CLI is unavailable; credentials for ${host} were not switched"
        return "${first_status}"
    fi

    account_data="$(_git_credential_switcher_accounts "${host}")" || {
        log_warn "Could not read GitHub accounts for ${host}"
        return "${first_status}"
    }

    while IFS="$(printf '\t')" read -r account active; do
        [ -n "${account}" ] || continue
        if [ "${active}" = "true" ] && [ -z "${current_account}" ]; then
            current_account="${account}"
        fi
    done <<EOF
${account_data}
EOF

    while IFS="$(printf '\t')" read -r account active; do
        [ -n "${account}" ] || continue
        if [ "${account}" != "${current_account}" ] && [ -z "${next_account}" ]; then
            next_account="${account}"
        fi
    done <<EOF
${account_data}
EOF

    if [ -z "${next_account}" ]; then
        log_warn "No alternate GitHub account is configured for ${host}"
        return "${first_status}"
    fi

    if [ -z "${current_account}" ]; then
        current_account="the current account"
    fi

    if ! _git_credential_switcher_confirm \
        "Failed to authenticate with GitHub credential ${current_account}. Switch context to ${next_account} and retry git ${operation}?"; then
        log_notice "GitHub credential switch declined"
        return "${first_status}"
    fi

    if ! env -u GH_TOKEN -u GITHUB_TOKEN \
        gh auth switch --hostname "${host}" --user "${next_account}"; then
        log_warn "GitHub account switch failed"
        return "${first_status}"
    fi

    log_result "Active GitHub account switched from ${current_account} to ${next_account}"
    log_state "Retrying git ${operation}"
    env -u GH_TOKEN -u GITHUB_TOKEN git "$@"
}

git() {
    local operation

    if [ "${GIT_CREDENTIAL_SWITCHER_DISABLE:-0}" = "1" ]; then
        command git "$@"
        return $?
    fi

    operation="$(_git_credential_switcher_operation "$@")" || {
        command git "$@"
        return $?
    }

    _git_with_credential_switch "${operation}" "$@"
}
