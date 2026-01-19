#!/usr/bin/env bats
# Tests for clean shell startup without errors
# Validates that shells start cleanly with only expected output

# Setup function runs before each test
setup() {
	# Get repository root
	REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
	export REPO_ROOT
}

@test "test-clean-shell-startup: bash starts cleanly" {
	if ! command -v bash >/dev/null 2>&1; then
		skip "Bash not installed"
	fi

	# Check if bash config exists
	if [ ! -f "$HOME/.bashrc" ] && [ ! -f "$HOME/.config/shell/config.bash" ]; then
		skip "Bash config not applied yet"
	fi

	# Start bash non-interactively and capture output
	# Use --norc and source our config manually to avoid system-wide configs
	local output
	output=$(bash --norc -c "
		if [ -f \$HOME/.config/shell/config.bash ]; then
			source \$HOME/.config/shell/config.bash
		fi
		echo 'Shell startup complete'
	" 2>&1)

	echo "Bash output: $output"

	# Check for common error patterns
	# Should NOT contain error messages, exceptions, or warnings
	[[ ! "$output" =~ "error" ]] || {
		echo "ERROR: Found 'error' in bash output"
		return 1
	}
	[[ ! "$output" =~ "Error" ]] || {
		echo "ERROR: Found 'Error' in bash output"
		return 1
	}
	[[ ! "$output" =~ "exception" ]] || {
		echo "ERROR: Found 'exception' in bash output"
		return 1
	}
	[[ ! "$output" =~ "Exception" ]] || {
		echo "ERROR: Found 'Exception' in bash output"
		return 1
	}
	[[ ! "$output" =~ "warning" ]] || {
		echo "ERROR: Found 'warning' in bash output"
		return 1
	}
	[[ ! "$output" =~ "Warning" ]] || {
		echo "ERROR: Found 'Warning' in bash output"
		return 1
	}
	[[ ! "$output" =~ "command not found" ]] || {
		echo "ERROR: Found 'command not found' in bash output"
		return 1
	}
	[[ ! "$output" =~ "No such file or directory" ]] || {
		echo "ERROR: Found 'No such file or directory' in bash output"
		return 1
	}

	# Should contain our marker that shell completed
	[[ "$output" =~ "Shell startup complete" ]] || {
		echo "ERROR: Shell did not complete startup successfully"
		return 1
	}
}

@test "test-clean-shell-startup: zsh starts cleanly" {
	if ! command -v zsh >/dev/null 2>&1; then
		skip "Zsh not installed"
	fi

	# Check if zsh config exists
	if [ ! -f "$HOME/.zshrc" ] && [ ! -f "$HOME/.config/shell/config.zsh" ]; then
		skip "Zsh config not applied yet"
	fi

	# Start zsh and capture output
	local output
	output=$(zsh --no-rcs -c "
		if [[ -f \$HOME/.config/shell/config.zsh ]]; then
			source \$HOME/.config/shell/config.zsh
		fi
		echo 'Shell startup complete'
	" 2>&1)

	echo "Zsh output: $output"

	# Check for common error patterns
	[[ ! "$output" =~ "error" ]] || {
		echo "ERROR: Found 'error' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "Error" ]] || {
		echo "ERROR: Found 'Error' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "exception" ]] || {
		echo "ERROR: Found 'exception' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "Exception" ]] || {
		echo "ERROR: Found 'Exception' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "warning" ]] || {
		echo "ERROR: Found 'warning' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "Warning" ]] || {
		echo "ERROR: Found 'Warning' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "command not found" ]] || {
		echo "ERROR: Found 'command not found' in zsh output"
		return 1
	}
	[[ ! "$output" =~ "No such file or directory" ]] || {
		echo "ERROR: Found 'No such file or directory' in zsh output"
		return 1
	}

	# Should contain our marker that shell completed
	[[ "$output" =~ "Shell startup complete" ]] || {
		echo "ERROR: Shell did not complete startup successfully"
		return 1
	}
}

@test "test-clean-shell-startup: fish starts cleanly" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Check if fish config exists
	if [ ! -f "$HOME/.config/fish/config.fish" ]; then
		skip "Fish config not applied yet"
	fi

	# Start fish and capture output
	# Fish automatically loads config from ~/.config/fish/config.fish
	local output
	output=$(fish -c "echo 'Shell startup complete'" 2>&1)

	echo "Fish output: $output"

	# Check for common error patterns
	[[ ! "$output" =~ "error" ]] || {
		echo "ERROR: Found 'error' in fish output"
		return 1
	}
	[[ ! "$output" =~ "Error" ]] || {
		echo "ERROR: Found 'Error' in fish output"
		return 1
	}
	[[ ! "$output" =~ "exception" ]] || {
		echo "ERROR: Found 'exception' in fish output"
		return 1
	}
	[[ ! "$output" =~ "Exception" ]] || {
		echo "ERROR: Found 'Exception' in fish output"
		return 1
	}
	[[ ! "$output" =~ "warning" ]] || {
		echo "ERROR: Found 'warning' in fish output"
		return 1
	}
	[[ ! "$output" =~ "Warning" ]] || {
		echo "ERROR: Found 'Warning' in fish output"
		return 1
	}
	[[ ! "$output" =~ "command not found" ]] || {
		echo "ERROR: Found 'command not found' in fish output"
		return 1
	}
	[[ ! "$output" =~ "No such file or directory" ]] || {
		echo "ERROR: Found 'No such file or directory' in fish output"
		return 1
	}

	# Should contain expected Fish config message
	[[ "$output" =~ "Fish shell configured successfully" ]] || {
		echo "ERROR: Expected Fish greeting not found"
		return 1
	}

	# Should contain our marker that shell completed
	[[ "$output" =~ "Shell startup complete" ]] || {
		echo "ERROR: Shell did not complete startup successfully"
		return 1
	}
}

@test "test-clean-shell-startup: fish greeting shows without errors" {
	if ! command -v fish >/dev/null 2>&1; then
		skip "Fish not installed"
	fi

	# Check if fish config exists
	if [ ! -f "$HOME/.config/fish/config.fish" ]; then
		skip "Fish config not applied yet"
	fi

	# Start fish interactively (simulated) to trigger greeting
	# Use TERM=dumb to avoid terminal control codes
	local output
	output=$(TERM=dumb fish -c "fish_greeting 2>&1; echo 'Greeting complete'" 2>&1)

	echo "Fish greeting output: $output"

	# Check for error patterns
	[[ ! "$output" =~ "error" ]] || {
		echo "ERROR: Found 'error' in fish greeting"
		return 1
	}
	[[ ! "$output" =~ "Error" ]] || {
		echo "ERROR: Found 'Error' in fish greeting"
		return 1
	}
	[[ ! "$output" =~ "exception" ]] || {
		echo "ERROR: Found 'exception' in fish greeting"
		return 1
	}
	[[ ! "$output" =~ "Exception" ]] || {
		echo "ERROR: Found 'Exception' in fish greeting"
		return 1
	}

	# Should complete successfully
	[[ "$output" =~ "Greeting complete" ]] || {
		echo "ERROR: Fish greeting did not complete"
		return 1
	}

	# Should contain the expected greeting message
	[[ "$output" =~ "Welcome to Fish Shell" ]] || {
		echo "Warning: Expected greeting message not found (may be OK if fastfetch not installed)"
	}
}
