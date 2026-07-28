#!/bin/bash
# chezmoi-up - Pull, re-init if needed, and apply your dotfiles in one go.
#
# Replaces the usual `chezmoi update && chezmoi init && chezmoi apply` dance.
# Each step is a gate: if one fails the run stops there, so a failed pull can
# never be followed by an apply of half-updated source.
#
# The steps are:
#   0. Branch guard — warn when the source repo is not on its default branch
#      (usually main), and offer to switch and pull. `chezmoi update` pulls
#      whatever branch is checked out, so a forgotten feature branch would
#      otherwise be applied to the machine silently.
#   1. `chezmoi update --apply=false` — pull the source repo only. Applying
#      here would use the OLD config, which breaks when the pull introduces a
#      template variable the current config does not have yet.
#   2. `chezmoi init` — only when the config template actually changed, which
#      is the same check chezmoi uses for its "config file template has
#      changed" warning: the SHA256 stored in its configState bucket versus
#      the template now on disk. Skipping is logged.
#   3. `chezmoi apply` — apply with the freshly generated config.
#
# Usage: chezmoi-up [-f|--force-init] [-h|--help]
#   -f, --force-init   Run `chezmoi init` even if the template is unchanged
#   -h, --help         Show this help message
#
# Environment:
#   CHEZMOI_UP_BRANCH             Expected branch (default: the source repo's
#                                 default branch, else main)
#   CHEZMOI_UP_SKIP_BRANCH_CHECK  Set to 1 to skip the branch guard entirely
#   CHEZMOI_UP_ASSUME_YES=1       Switch branch without asking
#   CHEZMOI_UP_ASSUME_NO=1        Never switch, even on a TTY
#
# Alias: czu

# _chezmoi_up_config_template -> print the path of the chezmoi config template
# (usually <source>/.chezmoi.yaml.tmpl), or nothing when there is none.
_chezmoi_up_config_template() {
    local source_dir candidate ext
    source_dir="$(chezmoi source-path 2>/dev/null)" || return 0
    [ -n "${source_dir}" ] || return 0

    for ext in yaml toml json jsonc yml; do
        candidate="${source_dir}/.chezmoi.${ext}.tmpl"
        if [ -f "${candidate}" ]; then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    return 0
}

# _chezmoi_up_sha256 FILE -> print the file's SHA256, or nothing.
_chezmoi_up_sha256() {
    local out=""
    if command -v sha256sum >/dev/null 2>&1; then
        out="$(sha256sum "${1}" 2>/dev/null || true)"
    elif command -v shasum >/dev/null 2>&1; then
        out="$(shasum -a 256 "${1}" 2>/dev/null || true)"
    fi
    [ -n "${out}" ] || return 0
    printf '%s\n' "${out%% *}"
}

# _chezmoi_up_needs_init -> 0 when `chezmoi init` should run.
# Compares the SHA256 chezmoi recorded for the config template with the
# template on disk. When either side cannot be determined we return 0 and let
# init run: a redundant init is harmless, a skipped one is not.
_chezmoi_up_needs_init() {
    local template stored actual
    template="$(_chezmoi_up_config_template)"
    [ -n "${template}" ] || return 0

    local state
    state="$(chezmoi state get --bucket=configState --key=configState 2>/dev/null || true)"
    [ -n "${state}" ] || return 0
    # Keep only hex so the parse survives both chezmoi's pretty-printed JSON
    # and a compact one-line object (where a trailing } would otherwise stick).
    stored="$(awk -F: '/configTemplateContentsSHA256/ { gsub(/[^0-9a-fA-F]/, "", $2); print $2 }' <<<"${state}")"
    [ -n "${stored}" ] || return 0

    actual="$(_chezmoi_up_sha256 "${template}")"
    [ -n "${actual}" ] || return 0

    [ "${stored}" != "${actual}" ]
}

# _chezmoi_up_expected_branch -> print the branch the source repo should be on.
# Honours CHEZMOI_UP_BRANCH, else asks git which branch origin's HEAD points at
# (so a repo that renames its default branch keeps working), else falls back to
# main.
_chezmoi_up_expected_branch() {
    local source_dir="${1}" head=""

    if [ -n "${CHEZMOI_UP_BRANCH:-}" ]; then
        printf '%s\n' "${CHEZMOI_UP_BRANCH}"
        return 0
    fi

    head="$(git -C "${source_dir}" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
    if [ -n "${head}" ]; then
        printf '%s\n' "${head#origin/}"
        return 0
    fi

    printf 'main\n'
}

# _chezmoi_up_confirm PROMPT -> 0 when the user answers yes. Non-interactive
# shells always answer no, so an automated run is warned but never blocked.
_chezmoi_up_confirm() {
    [ "${CHEZMOI_UP_ASSUME_YES:-0}" = "1" ] && return 0
    [ "${CHEZMOI_UP_ASSUME_NO:-0}" = "1" ] && return 1
    [ -t 0 ] || return 1

    local reply=""
    printf '%s [y/N] ' "${1}" >&2
    read -r reply || return 1
    case "${reply}" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
    esac
}

# _chezmoi_up_check_branch -> warn when the source repo is off its default
# branch, and offer to switch and pull.
#
# Always returns 0: being on a feature branch is a legitimate way to test
# dotfiles changes, so this warns and offers rather than blocking the run.
_chezmoi_up_check_branch() {
    [ "${CHEZMOI_UP_SKIP_BRANCH_CHECK:-0}" = "1" ] && return 0

    local source_dir
    source_dir="$(chezmoi source-path 2>/dev/null)" || return 0
    [ -n "${source_dir}" ] && [ -d "${source_dir}" ] || return 0

    # A source directory that is not a git checkout has no branch to be wrong.
    git -C "${source_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    local expected current
    expected="$(_chezmoi_up_expected_branch "${source_dir}")"
    current="$(git -C "${source_dir}" symbolic-ref --short -q HEAD 2>/dev/null || true)"

    [ "${current}" = "${expected}" ] && return 0

    if [ -z "${current}" ]; then
        _chezmoi_up_say warn "Source repository is in detached HEAD state, not on '${expected}'."
    else
        _chezmoi_up_say warn "Source repository is on '${current}', not '${expected}'."
    fi
    _chezmoi_up_say warn "chezmoi update pulls whichever branch is checked out."

    if ! _chezmoi_up_confirm "Switch to '${expected}' and pull?"; then
        _chezmoi_up_say info "Staying on '${current:-detached HEAD}'."
        return 0
    fi

    # Switching with uncommitted changes would either fail or drag the changes
    # onto the default branch; neither is something to do behind the user's back.
    local dirty=""
    dirty="$(git -C "${source_dir}" status --porcelain 2>/dev/null || true)"
    if [ -n "${dirty}" ]; then
        _chezmoi_up_say error "Source repository has uncommitted changes; commit or stash them first."
        _chezmoi_up_say info "Continuing on '${current:-detached HEAD}'."
        return 0
    fi

    _chezmoi_up_say step "Switching to '${expected}'"
    if ! git -C "${source_dir}" checkout "${expected}"; then
        _chezmoi_up_say error "Could not check out '${expected}'; continuing on '${current:-detached HEAD}'."
        return 0
    fi

    # --ff-only: never create a merge commit in the dotfiles source behind the
    # user's back. A diverged branch is reported instead.
    if ! git -C "${source_dir}" pull --ff-only; then
        _chezmoi_up_say error "Could not fast-forward '${expected}'; resolve it manually."
        return 0
    fi

    return 0
}

# _chezmoi_up_load_log -> make log.sh's helpers available when we can.
# config.bash/config.zsh source every file in this directory, but this one
# sorts before log.sh, so pull it in on first use. Falls back to the copy next
# to this file, which is how it is reachable from a bare repo checkout.
_chezmoi_up_load_log() {
    command -v log_step >/dev/null 2>&1 && return 0

    local here="" candidate
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
        here="$(dirname -- "${BASH_SOURCE[0]}")"
    fi

    for candidate in "${HOME}/.config/shell/functions/log.sh" "${here}/log.sh"; do
        if [ -n "${candidate}" ] && [ -f "${candidate}" ]; then
            # shellcheck source=/dev/null
            . "${candidate}" && return 0
        fi
    done
    return 0
}

# _chezmoi_up_say KIND MESSAGE... -> print a message through log.sh when it is
# available, else through plain echo. Never let a missing log.sh swallow output
# (or abort the run) on a machine where the dotfiles are not applied yet.
_chezmoi_up_say() {
    local kind="${1}"
    shift

    case "${kind}" in
    step)
        if command -v log_step >/dev/null 2>&1; then log_step "$*"; else printf '==> %s\n' "$*"; fi
        ;;
    info)
        if command -v log_info >/dev/null 2>&1; then log_info "$*"; else printf '==> %s\n' "$*"; fi
        ;;
    warn)
        if command -v log_warn >/dev/null 2>&1; then log_warn "$*"; else printf '! %s\n' "$*" >&2; fi
        ;;
    result)
        if command -v log_result >/dev/null 2>&1; then log_result "$*"; else printf '\342\234\223 %s\n' "$*"; fi
        ;;
    error)
        if command -v log_error >/dev/null 2>&1; then log_error "$*"; else printf '\342\234\227 %s\n' "$*" >&2; fi
        ;;
    *) printf '%s\n' "$*" ;;
    esac
}

chezmoi-up() {
    local force_init=false

    while [ $# -gt 0 ]; do
        case "${1}" in
        -f | --force-init)
            force_init=true
            shift
            ;;
        -h | --help)
            echo "Usage: chezmoi-up [-f|--force-init] [-h|--help]"
            echo "Pull, re-init when the config template changed, then apply."
            echo ""
            echo "Options:"
            echo "  -f, --force-init   Run 'chezmoi init' even if the template is unchanged"
            echo "  -h, --help         Show this help message"
            return 0
            ;;
        *)
            echo "chezmoi-up: unknown option: ${1}" >&2
            echo "Use --help for usage information" >&2
            return 1
            ;;
        esac
    done

    if ! command -v chezmoi >/dev/null 2>&1; then
        echo "chezmoi-up: chezmoi is not installed or not in PATH" >&2
        return 1
    fi

    _chezmoi_up_load_log
    # shellcheck disable=SC2034  # consumed by log.sh
    local LOG_TAG="chezmoi-up"

    _chezmoi_up_check_branch

    _chezmoi_up_say step "Pulling the source repository"
    if ! chezmoi update --apply=false; then
        _chezmoi_up_say error "chezmoi update failed; not continuing to init/apply"
        return 1
    fi

    if [ "${force_init}" = true ]; then
        _chezmoi_up_say step "Regenerating the config file (forced)"
        if ! chezmoi init; then
            _chezmoi_up_say error "chezmoi init failed; not continuing to apply"
            return 1
        fi
    elif _chezmoi_up_needs_init; then
        _chezmoi_up_say step "Config template changed, regenerating the config file"
        if ! chezmoi init; then
            _chezmoi_up_say error "chezmoi init failed; not continuing to apply"
            return 1
        fi
    else
        _chezmoi_up_say info "Config template unchanged, skipping chezmoi init"
    fi

    _chezmoi_up_say step "Applying"
    if ! chezmoi apply; then
        _chezmoi_up_say error "chezmoi apply failed"
        return 1
    fi

    _chezmoi_up_say result "Dotfiles are up to date"
    return 0
}

# Defined here rather than in aliases.sh so the function and its shorthand stay
# together; every file in this directory is sourced at shell startup.
alias czu='chezmoi-up'

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    chezmoi-up "$@"
fi
