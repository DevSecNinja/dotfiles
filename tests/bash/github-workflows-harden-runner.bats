#!/usr/bin/env bats
# Tests for GitHub Actions Harden-Runner rollout.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
	WORKFLOWS_DIR="$REPO_ROOT/.github/workflows"
	export WORKFLOWS_DIR
	HARDEN_RUNNER_REF='DevSecNinja/.github/actions/harden-runner@[0-9a-f]{40} # main'
	export HARDEN_RUNNER_REF
}

@test "github workflows: harden-runner uses pinned central composite action" {
	run grep -R -n -E "uses: ${HARDEN_RUNNER_REF}" "$WORKFLOWS_DIR"
	[ "$status" -eq 0 ]

	run bash -c "grep -R -n 'uses: DevSecNinja/.github/actions/harden-runner@' '$WORKFLOWS_DIR' | grep -Ev 'uses: ${HARDEN_RUNNER_REF}'"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "github workflows: harden-runner has renovate metadata" {
	while IFS=: read -r file line _; do
		previous_line="$(sed -n "$((line - 1))p" "$file")"
		[[ "$previous_line" == *"renovate: datasource=github-tags depName=DevSecNinja/.github"* ]]
	done < <(grep -R -n 'uses: DevSecNinja/.github/actions/harden-runner@' "$WORKFLOWS_DIR")
}

@test "github workflows: eligible linux jobs include harden-runner" {
	assert_harden_count ".github/workflows/bats.yml" 1
	assert_harden_count ".github/workflows/ci.yaml" 2
	assert_harden_count ".github/workflows/devcontainer-prebuild.yaml" 3
	assert_harden_count ".github/workflows/docs.yml" 3
	assert_harden_count ".github/workflows/release-please.yml" 1
	assert_harden_count ".github/workflows/release.yml" 2
	assert_harden_count ".github/workflows/sync-develop.yaml" 1
	assert_harden_count ".github/workflows/todo-to-issue.yml" 1
}

@test "github workflows: harden-runner precedes checkout in hardened jobs" {
	while IFS= read -r workflow; do
		awk '
			function finish_job() {
				if (job_has_harden && checkout_before_harden) {
					printf "%s:%d: checkout appears before harden-runner\n", FILENAME, checkout_line
					failed = 1
				}
			}
			/^[[:space:]]{2}[A-Za-z0-9_-]+:/ {
				finish_job()
				job_has_harden = 0
				checkout_before_harden = 0
				checkout_line = 0
			}
			/uses: actions\/checkout@/ && !job_has_harden {
				checkout_before_harden = 1
				checkout_line = FNR
			}
			/uses: DevSecNinja\/\.github\/actions\/harden-runner@/ {
				job_has_harden = 1
			}
			END {
				finish_job()
				exit failed
			}
		' "$workflow"
	done < <(grep -R -l 'uses: DevSecNinja/.github/actions/harden-runner@' "$WORKFLOWS_DIR")
}

@test "github workflows: do not call upstream harden-runner directly" {
	run grep -R -n 'uses: step-security/harden-runner@' "$WORKFLOWS_DIR"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

assert_harden_count() {
	local workflow="$1"
	local expected="$2"
	local actual

	actual="$(grep -c -E "uses: ${HARDEN_RUNNER_REF}" "$REPO_ROOT/$workflow")"
	[ "$actual" -eq "$expected" ]
}
