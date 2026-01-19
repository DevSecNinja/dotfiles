function get_external_ip --description "Get your public/external IP address"
    # Parse options
    set -l verbose false
    set -l show_help false

    for arg in $argv
        switch $arg
            case -h --help
                set show_help true
            case -v --verbose
                set verbose true
            case '*'
                echo "Unknown option: $arg" >&2
                echo "Use 'get_external_ip --help' for usage information" >&2
                return 1
        end
    end

    if test "$show_help" = true
        echo "Usage: get_external_ip [OPTIONS]"
        echo ""
        echo "Get your public/external IP address"
        echo ""
        echo "Options:"
        echo "  -v, --verbose    Enable verbose output"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  get_external_ip              # Display external IP"
        echo "  get_external_ip --verbose    # Display with verbose output"
        echo ""
        echo "Notes:"
        echo "  - Requires curl to be installed"
        echo "  - Requires internet connectivity"
        echo "  - Uses the ipify.org API service"
        return 0
    end

    # Check for required commands
    if not command -v curl >/dev/null 2>&1
        echo "❌ Required command 'curl' is not installed or not in PATH" >&2
        return 1
    end

    # Verbose output
    if test "$verbose" = true
        echo "🔍 Fetching external IP address from ipify.org..."
    end

    # Get external IP
    set -l external_ip (curl -s https://api.ipify.org)

    if test $status -eq 0 -a -n "$external_ip"
        if test "$verbose" = true
            echo "✅ Successfully retrieved external IP address"
            echo "📋 External IP: $external_ip"
        else
            echo $external_ip
        end
        return 0
    else
        echo "❌ Failed to retrieve external IP address" >&2
        return 1
    end
end
