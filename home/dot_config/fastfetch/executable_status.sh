#!/bin/bash
# fastfetch status.sh - Cached system status lines for fastfetch
#
# Emits short, self-hiding status lines that fastfetch renders as extra
# modules: available package updates, pending reboots and (when the host is
# managed by the DevSecNinja/docker ansible-pull project) the ansible-pull
# run status.
#
# Speed is the priority: this script is invoked once per section on every
# shell login (via fastfetch), so the section commands ONLY read a small
# cache and never run package managers, git or systemctl inline. The
# expensive work happens in `refresh`, which the section commands spawn in
# the background (fully detached) using a stale-while-revalidate strategy:
# the current (possibly slightly stale) cache is printed instantly while a
# fresh copy is computed for the next login. fastfetch hides a `command`
# module entirely when it prints nothing, so a section with nothing to
# report simply disappears.
#
# Relative times ("ran 5m ago", "next in 20m") are NOT baked into the cache
# — that would freeze them until the next refresh. The collectors store
# absolute epoch tokens (@ago:<epoch>@ / @in:<epoch>@) that expand to a bare
# duration phrase ("5m ago" / "in 20m"), and the section commands expand them
# against the current clock on every fastfetch run. Expansion itself is pure
# shell arithmetic; reading the clock uses the EPOCHSECONDS builtin on
# bash >= 5.0 and falls back to one `date` call on older bash, so the emit
# path costs at most a single fork.
#
# Usage: status.sh <section|command>
#   updates            Print cached "updates available" line (may be empty)
#   reboot             Print cached "reboot required" line (may be empty)
#   ansible            Print cached ansible-pull status line (may be empty)
#   refresh            Recompute the cache (respects a single-runner lock)
#   refresh --force    Recompute even if a refresh lock is held
#   clear              Remove the cache
#   -h, --help         Show this help
#
# Environment:
#   FASTFETCH_STATUS_TTL       Cache lifetime in seconds (default 3600)
#   FASTFETCH_STATUS_DISABLE   When set to 1, all sections print nothing
#   ANSIBLE_PULL_WORKDIR       ansible-pull checkout (default /var/lib/ansible/local)
#   XDG_CACHE_HOME             Base cache dir (default ~/.cache)
#
# Notes:
#   - Never requires root and never touches the network. Update counts are
#     read from already-downloaded package metadata; ansible/reboot status is
#     read from local files and systemd/git state.
#   - Update checks cover apt, dnf, pacman, zypper, apk (Linux) and brew
#     (macOS / Linuxbrew). Reboot detection is Linux-only; it prints nothing
#     elsewhere.
#   - Safe to run on any host; unmanaged hosts simply omit the ansible line.

set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/fastfetch-status"
STAMP="${CACHE_DIR}/.refreshed-at"
LOCK_DIR="${CACHE_DIR}/.refresh.lock"
TTL="${FASTFETCH_STATUS_TTL:-3600}"
ANSIBLE_WORKDIR="${ANSIBLE_PULL_WORKDIR:-/var/lib/ansible/local}"

# --- small helpers ----------------------------------------------------------

# _epoch_of FILE -> modification time in seconds since epoch (0 if missing).
_epoch_of() {
    stat -c %Y "${1}" 2>/dev/null || stat -f %m "${1}" 2>/dev/null || echo 0
}

# _fmt_duration SECONDS -> set REL_DURATION to a compact human duration
# (e.g. 45s, 12m, 3h, 2d). Fork-free so it is cheap on the emit path.
_fmt_duration() {
    local s="${1}"
    [ "${s}" -lt 0 ] && s=0
    if [ "${s}" -lt 60 ]; then
        REL_DURATION="${s}s"
    elif [ "${s}" -lt 3600 ]; then
        REL_DURATION="$((s / 60))m"
    elif [ "${s}" -lt 86400 ]; then
        REL_DURATION="$((s / 3600))h"
    else
        REL_DURATION="$((s / 86400))d"
    fi
}

# _now -> current epoch seconds. Uses the EPOCHSECONDS builtin on bash >= 5.0
# and falls back to a single `date` fork on older bash.
_now() {
    if [ -n "${EPOCHSECONDS:-}" ]; then
        printf '%s\n' "${EPOCHSECONDS}"
    else
        date +%s
    fi
}

# _render LINE NOW -> print LINE with relative-time tokens expanded:
#   @ago:<epoch>@  -> "5m ago"        (elapsed since <epoch>)
#   @in:<epoch>@   -> "in 20m", or "due" once <epoch> has passed
# Tokens expand to a bare duration phrase; the collectors own the wording
# around them (e.g. "ran @ago:…@", "next @in:…@", "checked @ago:…@").
# Unknown or malformed tokens are left untouched.
_render() {
    local line="${1}" now="${2}" tail="" pre kind epoch token
    local re='^(.*)@(ago|in):([0-9]+)@(.*)$'
    while [[ "${line}" =~ ${re} ]]; do
        pre="${BASH_REMATCH[1]}"
        kind="${BASH_REMATCH[2]}"
        epoch="${BASH_REMATCH[3]}"
        token=""
        if [ "${kind}" = "ago" ]; then
            _fmt_duration "$((now - epoch))"
            token="${REL_DURATION} ago"
        elif [ "${epoch}" -gt "${now}" ]; then
            _fmt_duration "$((epoch - now))"
            token="in ${REL_DURATION}"
        else
            token="due"
        fi
        tail="${token}${BASH_REMATCH[4]}${tail}"
        line="${pre}"
    done
    printf '%s%s\n' "${line}" "${tail}"
}

# _is_stale -> 0 (true) when the cache is missing or older than the TTL.
_is_stale() {
    [ -f "${STAMP}" ] || return 0
    local now stamp_epoch
    now="$(_now)"
    stamp_epoch="$(_epoch_of "${STAMP}")"
    [ "$((now - stamp_epoch))" -ge "${TTL}" ]
}

# _spawn_refresh -> kick off a background refresh, fully detached so fastfetch
# never blocks on it. A refresh lock in the child prevents multiple section
# calls from all launching a refresh at once.
_spawn_refresh() {
    if command -v setsid >/dev/null 2>&1; then
        setsid "${0}" refresh >/dev/null 2>&1 </dev/null &
    else
        ("${0}" refresh >/dev/null 2>&1 </dev/null &)
    fi
}

# _emit SECTION -> print the cached section (with relative-time tokens
# expanded against the current clock) and trigger a background refresh when
# the cache is stale.
_emit() {
    [ "${FASTFETCH_STATUS_DISABLE:-0}" = "1" ] && return 0
    if _is_stale; then
        _spawn_refresh
    fi
    local file="${CACHE_DIR}/${1}"
    [ -f "${file}" ] || return 0

    local now="" line
    while IFS= read -r line || [ -n "${line}" ]; do
        if [[ "${line}" == *@* ]]; then
            [ -n "${now}" ] || now="$(_now)"
            _render "${line}" "${now}"
        else
            printf '%s\n' "${line}"
        fi
    done <"${file}"
    return 0
}

# --- collectors (run only inside refresh) -----------------------------------

# _collect_updates -> line describing available package updates, or nothing.
# Reads already-synced package-manager metadata; never syncs (no root/network).
_collect_updates() {
    local count=0 mgr=""

    if command -v apt-get >/dev/null 2>&1; then
        mgr="apt"
        count="$(apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null | grep -c '^Inst ' || true)"
    elif command -v dnf >/dev/null 2>&1; then
        mgr="dnf"
        # -C = cache only, so no network access.
        count="$(dnf -q -C check-update 2>/dev/null | grep -cE '^[a-zA-Z0-9]' || true)"
    elif command -v pacman >/dev/null 2>&1; then
        mgr="pacman"
        count="$(pacman -Qu 2>/dev/null | grep -c . || true)"
    elif command -v zypper >/dev/null 2>&1; then
        mgr="zypper"
        count="$(zypper --non-interactive -q list-updates 2>/dev/null | grep -c '^v ' || true)"
    elif command -v apk >/dev/null 2>&1; then
        mgr="apk"
        count="$(apk version -l '<' 2>/dev/null | grep -c . || true)"
    elif command -v brew >/dev/null 2>&1; then
        # macOS (and Linuxbrew as a fallback). Reads local state only; does
        # not run `brew update`, so no network access.
        mgr="brew"
        count="$(brew outdated --quiet 2>/dev/null | grep -c . || true)"
    else
        return 0
    fi

    count="${count//[!0-9]/}"
    [ -z "${count}" ] && count=0
    if [ "${count}" -gt 0 ]; then
        # The "checked" suffix is an absolute epoch token so it keeps counting
        # up between refreshes instead of freezing at the value it had when
        # the cache was written.
        local checked_at
        checked_at="$(_now)"
        printf '\360\237\223\246 %s update(s) available (%s) \302\267 checked @ago:%s@\n' \
            "${count}" "${mgr}" "${checked_at}"
    fi
}

# _collect_reboot -> line describing a pending reboot, or nothing.
_collect_reboot() {
    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
        local pkgs="" f
        for f in /var/run/reboot-required.pkgs /run/reboot-required.pkgs; do
            if [ -f "${f}" ]; then
                pkgs="$(tr '\n' ' ' <"${f}" | sed 's/ *$//' || true)"
                break
            fi
        done
        if [ -n "${pkgs}" ]; then
            printf '\360\237\224\204 Reboot required \342\200\224 %s\n' "${pkgs}"
        else
            printf '\360\237\224\204 Reboot required\n'
        fi
        return 0
    fi

    # RHEL/Fedora: needs-restarting -r returns 1 when a reboot is needed.
    if command -v needs-restarting >/dev/null 2>&1; then
        if ! needs-restarting -r >/dev/null 2>&1; then
            printf '\360\237\224\204 Reboot required\n'
        fi
    fi
    return 0
}

# _systemd_prop UNIT PROP -> value of a systemd unit property ("" on failure).
_systemd_prop() {
    systemctl show "${1}" -p "${2}" --value 2>/dev/null || true
}

# _collect_ansible -> ansible-pull status line for hosts managed by the
# DevSecNinja/docker project, or nothing when the host is unmanaged.
_collect_ansible() {
    local have_systemd=0 managed=0 load_state=""
    if command -v systemctl >/dev/null 2>&1; then
        load_state="$(_systemd_prop ansible-pull.service LoadState)"
        if [ "${load_state}" = "loaded" ]; then
            have_systemd=1
            managed=1
        fi
    fi
    [ -d "${ANSIBLE_WORKDIR}/.git" ] && managed=1
    [ "${managed}" -eq 1 ] || return 0

    # Short SHA of the checked-out configuration (best effort; the workdir is
    # usually owned by a different user, hence safe.directory).
    local cfg=""
    if command -v git >/dev/null 2>&1 && [ -d "${ANSIBLE_WORKDIR}/.git" ]; then
        cfg="$(git -C "${ANSIBLE_WORKDIR}" -c safe.directory='*' log -1 --format='%h' 2>/dev/null || true)"
    fi

    if [ "${have_systemd}" -eq 0 ]; then
        # Managed but no systemd unit visible (e.g. cron-based scheduling).
        if [ -n "${cfg}" ]; then
            printf '\360\237\244\226 ansible-pull managed \302\267 config %s\n' "${cfg}"
        else
            printf '\360\237\244\226 ansible-pull managed\n'
        fi
        return 0
    fi

    local active result exit_code finished_ts now ran="" next=""
    active="$(_systemd_prop ansible-pull.service ActiveState)"
    result="$(_systemd_prop ansible-pull.service Result)"
    exit_code="$(_systemd_prop ansible-pull.service ExecMainStatus)"
    finished_ts="$(_systemd_prop ansible-pull.service InactiveEnterTimestamp)"
    now="$(_now)"

    # Relative times are stored as absolute epoch tokens and rendered on
    # every emit, so a cached line never shows a frozen "ran 29s ago".
    if [ -n "${finished_ts}" ]; then
        local finished_epoch
        finished_epoch="$(date -d "${finished_ts}" +%s 2>/dev/null || echo 0)"
        [ "${finished_epoch}" -gt 0 ] && ran="ran @ago:${finished_epoch}@"
    fi

    # Next scheduled run from the timer (microseconds since epoch).
    local next_us next_epoch
    next_us="$(_systemd_prop ansible-pull.timer NextElapseUSecRealtime)"
    next_us="${next_us//[!0-9]/}"
    if [ -n "${next_us}" ] && [ "${next_us}" -gt 0 ]; then
        next_epoch=$((next_us / 1000000))
        [ "${next_epoch}" -gt "${now}" ] && next="next @in:${next_epoch}@"
    fi

    local head tail="" part
    if [ "${active}" = "activating" ] || [ "${active}" = "active" ]; then
        head="\342\217\263 ansible-pull running\342\200\246"
    elif [ "${result}" = "success" ] && [ "${exit_code:-0}" = "0" ]; then
        head="\342\234\205 ansible-pull OK"
    else
        head="\342\235\214 ansible-pull FAILED"
        [ -n "${exit_code:-}" ] && [ "${exit_code}" != "0" ] && head="${head} (exit ${exit_code})"
    fi

    for part in "${ran}" "${next}" "${cfg:+config ${cfg}}"; do
        [ -n "${part}" ] && tail="${tail} \302\267 ${part}"
    done

    printf '%b%b\n' "${head}" "${tail}"
}

# --- refresh ----------------------------------------------------------------

# _write_section NAME VALUE -> atomically write (or remove) a cache section.
_write_section() {
    local value="${2}" file="${CACHE_DIR}/${1}"
    if [ -n "${value}" ]; then
        printf '%s\n' "${value}" >"${file}.tmp" && mv -f "${file}.tmp" "${file}"
    else
        rm -f "${file}"
    fi
}

_refresh() {
    local force="${1:-}"
    mkdir -p "${CACHE_DIR}"

    # Single-runner lock via atomic mkdir. Recover a stale lock (older than
    # 10 minutes) left behind by an interrupted refresh.
    if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
        if [ "${force}" = "--force" ]; then
            rmdir "${LOCK_DIR}" 2>/dev/null || true
            mkdir "${LOCK_DIR}" 2>/dev/null || return 0
        else
            local now lock_epoch
            now="$(_now)"
            lock_epoch="$(_epoch_of "${LOCK_DIR}")"
            if [ "$((now - lock_epoch))" -gt 600 ]; then
                rmdir "${LOCK_DIR}" 2>/dev/null || true
                mkdir "${LOCK_DIR}" 2>/dev/null || return 0
            else
                return 0
            fi
        fi
    fi
    trap 'rmdir "${LOCK_DIR}" 2>/dev/null || true' EXIT

    local updates reboot ansible
    updates="$(_collect_updates)"
    reboot="$(_collect_reboot)"
    ansible="$(_collect_ansible)"
    _write_section updates "${updates}"
    _write_section reboot "${reboot}"
    _write_section ansible "${ansible}"

    : >"${STAMP}"
}

_usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${0}"
}

# --- dispatch ---------------------------------------------------------------

case "${1:-}" in
updates | reboot | ansible)
    _emit "${1}"
    ;;
refresh)
    _refresh "${2:-}"
    ;;
clear)
    rm -rf "${CACHE_DIR}"
    ;;
-h | --help | help)
    _usage
    ;;
"")
    _usage
    exit 1
    ;;
*)
    echo "Unknown command: ${1}" >&2
    echo "Use --help for usage information" >&2
    exit 1
    ;;
esac
