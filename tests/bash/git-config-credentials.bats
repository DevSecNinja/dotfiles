#!/usr/bin/env bats

# Test the GitHub CLI credential helper block in the Git config template.
#
# `gh auth setup-git` appends these sections to ~/.config/git/config, which
# chezmoi owns — so an apply used to wipe them and silently break HTTPS pushes.
# The block is managed in the template now; these tests keep it that way.

setup() {
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT

	export PATH="${HOME}/.local/bin:${PATH}"

	GIT_TEMPLATE="$REPO_ROOT/home/dot_config/git/config.tmpl"
	export GIT_TEMPLATE

	TEST_TEMPLATE="$(mktemp)"
	export TEST_TEMPLATE

	TEST_CONFIG="$(mktemp)"
	export TEST_CONFIG
}

teardown() {
	rm -f "$TEST_TEMPLATE" "$TEST_CONFIG"
}

@test "git-config-credentials: template declares the gh credential helper" {
	grep -q '\[credential "https://github.com"\]' "$GIT_TEMPLATE"
	grep -q '\[credential "https://gist.github.com"\]' "$GIT_TEMPLATE"
	grep -q "auth git-credential" "$GIT_TEMPLATE"
}

@test "git-config-credentials: gh helper is gated on gh being installed" {
	grep -q 'lookPath "gh"' "$GIT_TEMPLATE"
}

@test "git-config-credentials: helper list is reset before the gh helper" {
	# Without the bare `helper =` line, git keeps the generic helper (cache /
	# osxkeychain / manager) in the list for github.com too, so a stale entry
	# can answer before gh does.
	run grep -c '^	helper =$' "$GIT_TEMPLATE"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]
}

@test "git-config-credentials: github.com resolves to gh, other hosts do not" {
	if ! command -v chezmoi >/dev/null 2>&1; then
		skip "Chezmoi not installed"
	fi

	# Mirrors the template logic with a fixed gh path so the assertion does not
	# depend on gh being installed on the machine running the tests.
	cat >"$TEST_TEMPLATE" <<'EOF'
{{- $ghPath := "/usr/bin/gh" -}}
[credential]
	helper = cache
[credential "https://github.com"]
	helper =
	helper = !'{{ $ghPath }}' auth git-credential
[credential "https://gist.github.com"]
	helper =
	helper = !'{{ $ghPath }}' auth git-credential
EOF

	run chezmoi execute-template <"$TEST_TEMPLATE"
	[ "$status" -eq 0 ]

	printf '%s\n' "$output" >"$TEST_CONFIG"

	run git config -f "$TEST_CONFIG" --get-urlmatch credential https://github.com/DevSecNinja/dotfiles
	[ "$status" -eq 0 ]
	[[ "$output" == *"auth git-credential"* ]]
	[[ "$output" != *"cache"* ]]

	run git config -f "$TEST_CONFIG" --get-urlmatch credential https://gist.github.com
	[ "$status" -eq 0 ]
	[[ "$output" == *"auth git-credential"* ]]

	run git config -f "$TEST_CONFIG" --get-urlmatch credential https://gitlab.com
	[ "$status" -eq 0 ]
	[[ "$output" == *"cache"* ]]
	[[ "$output" != *"auth git-credential"* ]]
}
