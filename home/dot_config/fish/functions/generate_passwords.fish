function generate_passwords --description 'Generate secure random passwords'
    # Set default values
    set -l pass_length 64
    set -l pass_count 5

    # Parse arguments
    argparse 'h/help' 'c/count=' -- $argv
    or return 1

    # Show help
    if set -q _flag_help
        echo "Usage: generate_passwords [OPTIONS] [LENGTH]"
        echo "Generate secure random alphanumeric passwords"
        echo ""
        echo "Arguments:"
        echo "  LENGTH           Length of passwords (default: 64)"
        echo ""
        echo "Options:"
        echo "  --count, -c N    Number of passwords to generate (default: 5)"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  generate_passwords              # Generate 5 passwords of 64 characters"
        echo "  generate_passwords 32           # Generate 5 passwords of 32 characters"
        echo "  generate_passwords --count 10   # Generate 10 passwords of 64 characters"
        echo "  generate_passwords 16 --count 3 # Generate 3 passwords of 16 characters"
        return 0
    end

    # Set count if provided
    if set -q _flag_count
        if not string match -qr '^\d+$' -- $_flag_count
            echo "❌ Count must be a positive integer" >&2
            return 1
        end
        set pass_count $_flag_count
    end

    # Handle positional argument (password length)
    if test (count $argv) -gt 0
        if not string match -qr '^\d+$' -- $argv[1]
            echo "❌ Password length must be a positive integer" >&2
            return 1
        end
        set pass_length $argv[1]
    end

    # Validation checks
    if not test -r /dev/urandom
        echo "❌ Cannot read from /dev/urandom" >&2
        return 1
    end

    if test $pass_length -lt 1
        echo "❌ Password length must be at least 1 character" >&2
        return 1
    end

    if test $pass_count -lt 1
        echo "❌ Password count must be at least 1" >&2
        return 1
    end

    # Main logic
    echo "🔐 Generating $pass_count password(s) of $pass_length characters each:"
    echo ""

    for i in (seq 1 $pass_count)
        env LC_ALL=C tr -cd '[:alnum:]' < /dev/urandom | fold -w$pass_length | head -n 1
    end

    return 0
end
