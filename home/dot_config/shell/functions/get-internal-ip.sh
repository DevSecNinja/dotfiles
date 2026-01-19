#!/bin/bash
# get-internal-ip - Get your local/internal IP address
#
# Retrieves your internal IP address on the local network.
# This shows the IP address assigned by your router/DHCP server.
#
# Usage: get-internal-ip [OPTIONS]
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   get-internal-ip              # Display internal IP
#   get-internal-ip --verbose    # Display with verbose output
#
# Notes:
#   - Works on macOS and Linux
#   - macOS: Uses ipconfig to get en0 or en1 interface
#   - Linux: Uses hostname -I or ip command
#   - Shows the first IP address if multiple interfaces exist

get-internal-ip() {
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
			echo "Usage: get-internal-ip [OPTIONS]"
			echo "Get your local/internal IP address"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Examples:"
			echo "  get-internal-ip              # Display internal IP"
			echo "  get-internal-ip --verbose    # Display with verbose output"
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

	# Verbose output
	if [ "$verbose" = true ]; then
		echo "🔍 Retrieving internal IP address..."
	fi

	# Get internal IP (cross-platform approach)
	local internal_ip

	# Try different methods based on OS
	if [[ "$OSTYPE" == "darwin"* ]]; then
		# macOS
		internal_ip=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
	elif command -v hostname >/dev/null 2>&1; then
		# Linux with hostname -I
		internal_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
	elif command -v ip >/dev/null 2>&1; then
		# Linux with ip command
		internal_ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
	else
		echo "❌ Unable to determine internal IP address. No suitable command found."
		return 1
	fi

	if [ -n "$internal_ip" ]; then
		if [ "$verbose" = true ]; then
			echo "✅ Successfully retrieved internal IP address"
			echo "📋 Internal IP: $internal_ip"
		else
			echo "$internal_ip"
		fi
		return 0
	else
		echo "❌ Failed to retrieve internal IP address"
		return 1
	fi
}

# Auto-execute if script is run directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	get-internal-ip "$@"
fi
