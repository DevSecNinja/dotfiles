#!/bin/bash
# get-external-ip - Get your public/external IP address
#
# Retrieves your external IP address by querying the ipify.org API.
# This shows the IP address that external services see when you connect to them.
#
# Usage: get-external-ip [OPTIONS]
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   get-external-ip              # Display external IP
#   get-external-ip --verbose    # Display with verbose output
#
# Notes:
#   - Requires curl to be installed
#   - Requires internet connectivity
#   - Uses the ipify.org API service

get-external-ip() {
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
			echo "Usage: get-external-ip [OPTIONS]"
			echo "Get your public/external IP address"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Examples:"
			echo "  get-external-ip              # Display external IP"
			echo "  get-external-ip --verbose    # Display with verbose output"
			return 0
			;;
		-*)
			echo "❌ Unknown option: $1"
			echo "Use --help for usage information"
			return 1
			;;
		*)
			echo "❌ Too many arguments. This command takes no arguments."
			echo "Use --help for usage information"
			return 1
			;;
		esac
	done

	# Check for required commands
	if ! command -v curl >/dev/null 2>&1; then
		echo "❌ Required command 'curl' is not installed or not in PATH"
		return 1
	fi

	# Verbose output
	if [ "$verbose" = true ]; then
		echo "🔍 Fetching external IP address from ipify.org..."
	fi

	# Get external IP
	local external_ip
	if external_ip=$(curl -s https://api.ipify.org) && [ -n "$external_ip" ]; then
		if [ "$verbose" = true ]; then
			echo "✅ Successfully retrieved external IP address"
			echo "📋 External IP: $external_ip"
		else
			echo "$external_ip"
		fi
		return 0
	else
		echo "❌ Failed to retrieve external IP address"
		return 1
	fi
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	get-external-ip "$@"
fi
