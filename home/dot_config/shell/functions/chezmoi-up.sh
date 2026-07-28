#!/bin/bash
# chezmoi-up - Pull, re-init if needed, and apply your dotfiles in one go.
#
# Replaces the usual `chezmoi update && chezmoi init && chezmoi apply` dance.
# Each step is a gate: if one fails the run stops there, so a failed pull can
# never be followed by an apply of half-updated source.
#
# The steps are:
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
    stored="$(awk -F: '/configTemplateContentsSHA256/ { gsub(/[ ",]/, "", $2); print $2 }' <<<"${state}")"
    [ -n "${stored}" ] || return 0

    actual="$(_chezmoi_up_sha256 "${template}")"
    [ -n "${actual}" ] || return 0

    [ "${stored}" != "${actual}" ]
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

    # log.sh is sourced by config.bash/config.zsh, but this file sorts before
    # it, so pull it in when running standalone.
    if ! command -v log_step >/dev/null 2>&1 && [ -f "${HOME}/.config/shell/functions/log.sh" ]; then
        # shellcheck source=/dev/null
        . "${HOME}/.config/shell/functions/log.sh"
    fi
    # shellcheck disable=SC2034  # consumed by log.sh
    local LOG_TAG="chezmoi-up"

    log_step "Pulling the source repository"
    if ! chezmoi update --apply=false; then
        log_error "chezmoi update failed; not continuing to init/apply"
        return 1
    fi

    if [ "${force_init}" = true ]; then
        log_step "Regenerating the config file (forced)"
        if ! chezmoi init; then
            log_error "chezmoi init failed; not continuing to apply"
            return 1
        fi
    elif _chezmoi_up_needs_init; then
        log_step "Config template changed, regenerating the config file"
        if ! chezmoi init; then
            log_error "chezmoi init failed; not continuing to apply"
            return 1
        fi
    else
        log_info "Config template unchanged, skipping chezmoi init"
    fi

    log_step "Applying"
    if ! chezmoi apply; then
        log_error "chezmoi apply failed"
        return 1
    fi

    log_result "Dotfiles are up to date"
    return 0
}

# Defined here rather than in aliases.sh so the function and its shorthand stay
# together; every file in this directory is sourced at shell startup.
alias czu='chezmoi-up'

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    chezmoi-up "$@"
fi
