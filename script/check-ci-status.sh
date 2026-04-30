#!/usr/bin/env bash
# script/check-ci-status.sh
#
# Verify that GitHub Actions checks for a given commit (default: HEAD on
# origin/main) have all completed successfully. Used as a precondition for
# `task release:bump` to avoid cutting a release on a red main.
#
# Usage:
#   script/check-ci-status.sh             # check origin/main HEAD
#   script/check-ci-status.sh <sha>       # check a specific commit
#   FORCE=1 script/check-ci-status.sh     # bypass with a warning (still
#                                           prints status)
#
# Exit codes:
#   0 - all required check runs concluded as success / neutral / skipped
#   1 - at least one failure / cancelled / timed_out / action_required
#   2 - checks still in progress, queued, or commit not yet seen by CI
#   3 - usage / dependency error

set -euo pipefail

# shellcheck source=/dev/null
. "$(git rev-parse --show-toplevel)/home/dot_config/shell/functions/log.sh"
export LOG_TAG="check-ci-status"

if ! command -v jq >/dev/null 2>&1; then
	log_fatal "jq is required but not on PATH"
	exit 3
fi

# Prefer gh (handles auth, rate limits, pagination), fall back to curl for
# public repos when gh isn't authenticated.
fetch_check_runs() {
	local repo="$1" sha="$2"
	if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
		gh api \
			-H "Accept: application/vnd.github+json" \
			--paginate \
			"repos/${repo}/commits/${sha}/check-runs" \
			--jq '[.check_runs[] | {name, status, conclusion}]' |
			jq -s 'add // []'
	else
		# Unauthenticated fallback (60 req/hour per IP). Pulls page 1 only;
		# good enough for our typical <30 check runs.
		curl -fsSL \
			-H "Accept: application/vnd.github+json" \
			"https://api.github.com/repos/${repo}/commits/${sha}/check-runs?per_page=100" |
			jq '[.check_runs[] | {name, status, conclusion}]'
	fi
}

sha="${1:-}"
if [ -z "${sha}" ]; then
	if ! sha="$(git rev-parse origin/main 2>/dev/null)"; then
		log_fatal "No SHA argument and origin/main not available"
		exit 3
	fi
fi

# Resolve the repository slug from origin URL so the script is portable.
remote_url="$(git remote get-url origin 2>/dev/null || true)"
case "${remote_url}" in
*github.com[:/]*)
	repo="${remote_url#*github.com[:/]}"
	repo="${repo%.git}"
	;;
*)
	log_fatal "Could not derive GitHub repo slug from remote: ${remote_url}"
	exit 3
	;;
esac

log_state "Checking CI for ${repo}@${sha:0:7}"

# Pull every check run for the commit.
runs_json="$(fetch_check_runs "${repo}" "${sha}")"

count="$(printf '%s' "${runs_json}" | jq 'length')"
if [ "${count}" = "0" ]; then
	log_warn "No check runs found for ${sha:0:7} (CI may not have started yet)"
	[ "${FORCE:-0}" = "1" ] || exit 2
	log_warn "FORCE=1: continuing anyway"
	exit 0
fi

# Anything still running blocks the gate.
in_progress="$(printf '%s' "${runs_json}" |
	jq -r '[.[] | select(.status != "completed")] | length')"
if [ "${in_progress}" != "0" ]; then
	log_warn "${in_progress} check run(s) still in progress for ${sha:0:7}"
	printf '%s\n' "${runs_json}" |
		jq -r '.[] | select(.status != "completed") | "  - \(.name): \(.status)"'
	[ "${FORCE:-0}" = "1" ] || exit 2
	log_warn "FORCE=1: continuing anyway"
	exit 0
fi

# Bad conclusions block the gate. neutral/skipped/success are accepted.
bad="$(printf '%s' "${runs_json}" |
	jq -r '[.[] | select(.conclusion as $c
        | ["success","neutral","skipped"] | index($c) | not)] | length')"
if [ "${bad}" != "0" ]; then
	log_error "${bad} check run(s) failed for ${sha:0:7}:"
	printf '%s\n' "${runs_json}" |
		jq -r '.[] | select(.conclusion as $c
        | ["success","neutral","skipped"] | index($c) | not)
        | "  - \(.name): \(.conclusion)"'
	log_hint "Fix CI on main, push, wait for green, then retry."
	log_hint "Override with FORCE=1 task release:bump -- ... (NOT recommended)."
	[ "${FORCE:-0}" = "1" ] || exit 1
	log_warn "FORCE=1: continuing despite failures"
fi

log_result "All ${count} check run(s) green for ${sha:0:7}"
