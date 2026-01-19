function get_internal_ip --description "Get your local/internal IP address"
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
                echo "Use 'get_internal_ip --help' for usage information" >&2
                return 1
        end
    end

    if test "$show_help" = true
        echo "Usage: get_internal_ip [OPTIONS]"
        echo ""
        echo "Get your local/internal IP address"
        echo ""
        echo "Options:"
        echo "  -v, --verbose    Enable verbose output"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  get_internal_ip              # Display internal IP"
        echo "  get_internal_ip --verbose    # Display with verbose output"
        echo ""
        echo "Notes:"
        echo "  - Works on macOS and Linux"
        echo "  - macOS: Uses ipconfig to get en0 or en1 interface"
        echo "  - Linux: Uses hostname -I or ip command"
        echo "  - Shows the first IP address if multiple interfaces exist"
        return 0
    end

    # Verbose output
    if test "$verbose" = true
        echo "🔍 Retrieving internal IP address..."
    end

    # Get internal IP (cross-platform approach)
    set -l internal_ip ""

    # Try different methods based on OS
    if test (uname) = "Darwin"
        # macOS
        set internal_ip (ipconfig getifaddr en0 2>/dev/null; or ipconfig getifaddr en1 2>/dev/null)
    else if command -v hostname >/dev/null 2>&1
        # Linux with hostname -I
        set internal_ip (hostname -I 2>/dev/null | awk '{print $1}')
    else if command -v ip >/dev/null 2>&1
        # Linux with ip command
        set internal_ip (ip route get 1 2>/dev/null | awk '{print $7; exit}')
    else
        echo "❌ Unable to determine internal IP address. No suitable command found." >&2
        return 1
    end

    if test $status -eq 0 -a -n "$internal_ip"
        if test "$verbose" = true
            echo "✅ Successfully retrieved internal IP address"
            echo "📋 Internal IP: $internal_ip"
        else
            echo $internal_ip
        end
        return 0
    else
        echo "❌ Failed to retrieve internal IP address" >&2
        return 1
    end
end
