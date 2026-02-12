#!/bin/bash
# dns-flush - Flush DNS cache on macOS
#
# Kills and restarts the mDNSResponder service to flush the DNS cache.
# This is useful when DNS records are not resolving correctly or after
# network changes.
#
# Usage: dns-flush [OPTIONS]
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   dns-flush                # Flush DNS cache
#   dns-flush --verbose      # Flush with verbose output
#
# Notes:
#   - Requires sudo privileges
#   - Only works on macOS systems

dns-flush() {
	# Initialize variables
	local verbose=false

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--verbose | -v)
			verbose=true
			shift
			;;
		-h | --help)
			echo "Usage: dns-flush [OPTIONS]"
			echo "Flush DNS cache on macOS"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Examples:"
			echo "  dns-flush                # Flush DNS cache"
			echo "  dns-flush --verbose      # Flush with verbose output"
			return 0
			;;
		*)
			echo "Unknown option: $1"
			echo "Use 'dns-flush --help' for usage information"
			return 1
			;;
		esac
	done

	# Check if running on macOS
	if [[ "$(uname)" != "Darwin" ]]; then
		echo "Error: This function only works on macOS"
		return 1
	fi

	# Flush DNS cache
	if [[ "$verbose" == true ]]; then
		echo "Flushing DNS cache..."
	fi

	if sudo killall -HUP mDNSResponder; then
		if [[ "$verbose" == true ]]; then
			echo "✓ DNS cache flushed successfully"
		else
			echo "DNS cache flushed"
		fi
		return 0
	else
		echo "Error: Failed to flush DNS cache"
		return 1
	fi
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	dns-flush "$@"
fi
