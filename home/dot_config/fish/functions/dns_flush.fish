function dns_flush --description "Flush DNS cache on macOS"
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
                echo "Use 'dns_flush --help' for usage information" >&2
                return 1
        end
    end

    if test "$show_help" = true
        echo "Usage: dns_flush [OPTIONS]"
        echo ""
        echo "Flush DNS cache on macOS"
        echo ""
        echo "Options:"
        echo "  -v, --verbose    Enable verbose output"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  dns_flush                # Flush DNS cache"
        echo "  dns_flush --verbose      # Flush with verbose output"
        return 0
    end

    # Check if running on macOS
    if test (uname) != Darwin
        echo "Error: This function only works on macOS" >&2
        return 1
    end

    # Flush DNS cache
    if test "$verbose" = true
        echo "Flushing DNS cache..."
    end

    sudo killall -HUP mDNSResponder

    if test $status -eq 0
        if test "$verbose" = true
            echo "✓ DNS cache flushed successfully"
        else
            echo "DNS cache flushed"
        end
        return 0
    else
        echo "Error: Failed to flush DNS cache" >&2
        return 1
    end
end
