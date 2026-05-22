#!/usr/bin/env bats
# Tests for verifying applied dotfiles exist

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "verify-dotfiles: vimrc exists after apply" {
	if [ ! -f "$HOME/.vimrc" ]; then
		skip ".vimrc not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.vimrc" ]
}

@test "verify-dotfiles: tmux.conf exists after apply" {
	if [ ! -f "$HOME/.tmux.conf" ]; then
		skip ".tmux.conf not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.tmux.conf" ]
}

@test "verify-dotfiles: fish config.fish exists after apply" {
	if [ ! -f "$HOME/.config/fish/config.fish" ]; then
		skip "Fish config not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.config/fish/config.fish" ]
}

@test "verify-dotfiles: fish aliases exist after apply" {
	if [ ! -f "$HOME/.config/fish/conf.d/aliases.fish" ]; then
		skip "Fish aliases not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.config/fish/conf.d/aliases.fish" ]
}

@test "verify-dotfiles: fish_greeting function exists after apply" {
	if [ ! -f "$HOME/.config/fish/functions/fish_greeting.fish" ]; then
		skip "fish_greeting not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.config/fish/functions/fish_greeting.fish" ]
}

@test "verify-dotfiles: git config exists after apply" {
	if [ ! -f "$HOME/.config/git/config" ]; then
		skip "Git config not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.config/git/config" ]
}

@test "verify-dotfiles: git ignore exists after apply" {
	if [ ! -f "$HOME/.config/git/ignore" ]; then
		skip "Git ignore not applied (test only works after chezmoi apply)"
	fi

	[ -f "$HOME/.config/git/ignore" ]
}

@test "verify-dotfiles: global gitignore blocks security-sensitive files" {
	GIT_IGNORE="$REPO_ROOT/home/dot_config/git/ignore"
	TEST_DIR="$BATS_TEST_TMPDIR/git-ignore"
	mkdir -p "$TEST_DIR/.aws" "$TEST_DIR/.kube"
	cd "$TEST_DIR"
	git init --quiet

	ignored_files=(
		".env"
		".env.local"
		".env.production"
		".netrc"
		".aws/credentials"
		".kube/config"
		"private.pem"
		"tls-private.pem"
		"server.key"
		"client.key"
		"secret.p12"
		"secret.pfx"
		"id_rsa"
		"id_dsa"
		"id_ecdsa"
		"id_ed25519"
		"terraform.tfstate"
		"terraform.tfstate.backup"
		"core.1234"
		"core_dump"
		"core_12345"
	)
	touch "${ignored_files[@]}"

	run git -c "core.excludesFile=$GIT_IGNORE" check-ignore "${ignored_files[@]}"
	[ "$status" -eq 0 ]

	for ignored_file in "${ignored_files[@]}"; do
		printf '%s\n' "${lines[@]}" | grep -Fx -- "$ignored_file" >/dev/null
	done
}

@test "verify-dotfiles: global gitignore allows templates and public keys" {
	GIT_IGNORE="$REPO_ROOT/home/dot_config/git/ignore"
	TEST_DIR="$BATS_TEST_TMPDIR/git-ignore-templates"
	mkdir -p "$TEST_DIR"
	cd "$TEST_DIR"
	git init --quiet
	touch .env.example .env.sample .env.template public-cert.pem public.key

	run git -c "core.excludesFile=$GIT_IGNORE" check-ignore .env.example .env.sample .env.template public-cert.pem public.key
	[ "$status" -eq 1 ]
	[ -z "$output" ]
}

@test "verify-dotfiles: source files exist in repository" {
	# These should always exist in the repository
	[ -f "$REPO_ROOT/home/dot_vimrc" ]
	[ -f "$REPO_ROOT/home/dot_tmux.conf" ]
	[ -f "$REPO_ROOT/home/dot_config/fish/config.fish" ]
	[ -f "$REPO_ROOT/home/dot_config/git/config.tmpl" ]
}

@test "verify-dotfiles: required directories exist in repository" {
	[ -d "$REPO_ROOT/home/dot_config" ]
	[ -d "$REPO_ROOT/home/dot_config/fish" ]
	[ -d "$REPO_ROOT/home/dot_config/git" ]
}
