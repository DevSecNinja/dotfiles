#!/bin/bash
# Sourced after log.sh. SUDO_CMD is set by the package setup script.

# Print installed selectors for the manager in $1, propagating query failures.
# Canonicalize official Homebrew prefixes while retaining third-party tap names.
package_uninstall_inventory() (
    set -o pipefail
    case "$1" in
    apt)
        dpkg-query --show '--showformat=${Package} ${Architecture} ${db:Status-Status}\n' |
            awk '$3 != "not-installed" && $3 != "config-files" { print $1; print $1 ":" $2 }'
        ;;
    dnf)
        rpm --query --all --queryformat '%{NAME}\n'
        ;;
    brew-formula)
        brew list --formula --full-name -1 | sed 's#^homebrew/core/##'
        ;;
    brew-cask)
        brew list --cask --full-name -1 | sed 's#^homebrew/cask/##'
        ;;
    mas)
        mas list | awk '{ print $1 }'
        ;;
    *)
        log_error "Unsupported uninstall manager: $1" >&2
        return 1
        ;;
    esac
)

# Remove selector $2 through manager $1, skipping absent packages and verifying removal.
# Qualified Homebrew selectors must not match the same basename in another tap.
uninstall_package() {
    local manager="$1" package="$2" match_package="$2" inventory output
    local -a remove_command elevate
    elevate=()
    [ -z "${SUDO_CMD:-}" ] || elevate=("${SUDO_CMD}")

    # Reject options, globs and paths; managers may otherwise expand selectors.
    case "${manager}" in
    apt)
        [[ "${package}" =~ ^[a-z0-9][a-z0-9.+-]*(:[a-z0-9-]+)?$ ]] || {
            log_error "Invalid APT package: ${package}"
            return 1
        }
        remove_command=("${elevate[@]}" apt-get remove -y -- "${package}")
        ;;
    dnf)
        [[ "${package}" =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || {
            log_error "Invalid DNF package: ${package}"
            return 1
        }
        remove_command=("${elevate[@]}" dnf remove -y --setopt=clean_requirements_on_remove=False -- "${package}")
        ;;
    brew-formula | brew-cask)
        [[ "${package}" =~ ^([A-Za-z0-9_-]+/[A-Za-z0-9_-]+/)?[A-Za-z0-9][A-Za-z0-9@+._-]*$ ]] || {
            log_error "Invalid Homebrew package: ${package}"
            return 1
        }
        remove_command=(brew uninstall "--${manager#brew-}")
        # --force removes all formula versions, but must not be used for casks:
        # cask --force can ignore removal errors. Keep dependency checks enabled.
        [ "${manager}" != brew-formula ] || remove_command+=(--force)
        remove_command+=(-- "${package}")
        ;;
    mas)
        [[ "${package}" =~ ^[1-9][0-9]*$ ]] || {
            log_error "Invalid Mac App Store ID: ${package}"
            return 1
        }
        remove_command=("${elevate[@]}" mas uninstall "${package}")
        ;;
    *)
        log_error "Unsupported uninstall manager: ${manager}"
        return 1
        ;;
    esac

    if ! inventory=$(package_uninstall_inventory "${manager}" 2>&1); then
        printf '%s\n' "${inventory}" | log_data ERROR "Could not list ${manager} packages"
        return 1
    fi
    if [[ "${manager}" == brew-formula && "${package}" == homebrew/core/* ]] ||
        [[ "${manager}" == brew-cask && "${package}" == homebrew/cask/* ]]; then
        match_package="${package##*/}"
    fi
    # Only an originally unqualified selector can match another tap's basename.
    if [[ "${manager}" == brew-* && "${package}" != */* ]]; then
        inventory=$(printf '%s\n' "${inventory}" | awk -F/ '{ print $NF }')
    fi
    if ! printf '%s\n' "${inventory}" | grep -Fx -- "${match_package}" >/dev/null; then
        log_step "${package} (${manager}) is not installed"
        return 0
    fi

    log_step "Uninstalling ${package} (${manager})"
    if ! output=$(HOMEBREW_NO_AUTOREMOVE=1 "${remove_command[@]}" 2>&1); then
        printf '%s\n' "${output}" | log_data ERROR "Failed to uninstall ${package} (${manager})"
        return 1
    fi
    if ! inventory=$(package_uninstall_inventory "${manager}" 2>&1); then
        printf '%s\n' "${inventory}" | log_data ERROR "Could not verify removal of ${package} (${manager})"
        return 1
    fi
    if [[ "${manager}" == brew-* && "${package}" != */* ]]; then
        inventory=$(printf '%s\n' "${inventory}" | awk -F/ '{ print $NF }')
    fi
    if printf '%s\n' "${inventory}" | grep -Fx -- "${match_package}" >/dev/null; then
        log_error "${package} (${manager}) is still installed after uninstalling"
        return 1
    fi
    log_result "Uninstalled ${package} (${manager})"
}
