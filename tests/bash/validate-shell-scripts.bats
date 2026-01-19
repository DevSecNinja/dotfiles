#!/usr/bin/env bats
# Tests for shell script syntax validation

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "validate-shell-scripts: can find shell scripts in repository" {
	cd "$REPO_ROOT"
	run bash -c "find . \( -name '*.sh' -o -name '*.sh.tmpl' \) | grep -v node_modules | head -1"
	[ "$status" -eq 0 ]
	[ -n "$output" ]
}

@test "validate-shell-scripts: install.sh has valid syntax" {
	if [ ! -f "$REPO_ROOT/home/install.sh" ]; then
		skip "install.sh not found"
	fi
	
	run bash -n "$REPO_ROOT/home/install.sh"
	[ "$status" -eq 0 ]
}

@test "validate-shell-scripts: all .sh files have valid bash syntax" {
	cd "$REPO_ROOT"
	
	# Find all .sh files with bash shebang
	local found_scripts=false
	while IFS= read -r script; do
		if [ -n "$script" ] && [ -f "$script" ]; then
			if head -n 1 "$script" | grep -q "#!/bin/bash\|#!/usr/bin/env bash"; then
				found_scripts=true
				run bash -n "$script"
				if [ "$status" -ne 0 ]; then
					echo "Syntax error in: $script"
					return 1
				fi
			fi
		fi
	done < <(find home tests .github/scripts -name "*.sh" 2>/dev/null | grep -v node_modules || true)
	
	if [ "$found_scripts" = false ]; then
		skip "No bash scripts found"
	fi
}

@test "validate-shell-scripts: all .sh files have valid sh syntax" {
	cd "$REPO_ROOT"
	
	# Find all .sh files with sh shebang
	local found_scripts=false
	while IFS= read -r script; do
		if [ -n "$script" ] && [ -f "$script" ]; then
			if head -n 1 "$script" | grep -q "#!/bin/sh" && ! grep -q "#!/bin/bash\|#!/usr/bin/env bash" "$script"; then
				found_scripts=true
				run sh -n "$script"
				if [ "$status" -ne 0 ]; then
					echo "Syntax error in: $script"
					return 1
				fi
			fi
		fi
	done < <(find home tests .github/scripts -name "*.sh" 2>/dev/null | grep -v node_modules || true)
	
	if [ "$found_scripts" = false ]; then
		skip "No sh scripts found"
	fi
}

@test "validate-shell-scripts: template files with chezmoi syntax are skipped" {
	cd "$REPO_ROOT"
	
	# Find template files with Chezmoi syntax
	local found_templates=false
	while IFS= read -r script; do
		if [ -n "$script" ] && [ -f "$script" ]; then
			if grep -q '{{' "$script"; then
				found_templates=true
				# These should be skipped in validation, so just verify they exist
				[ -f "$script" ]
			fi
		fi
	done < <(find home -name "*.sh.tmpl" 2>/dev/null || true)
	
	# This test just verifies the logic for finding templates
	[ "$found_templates" = true ] || skip "No template files found"
}
