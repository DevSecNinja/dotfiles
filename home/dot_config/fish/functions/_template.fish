function function_name --description "Brief description of what this function does"
    # function_name - Detailed description of the function's purpose
    #
    # Automatically handles argument parsing using Fish's argparse.
    # Add more context about when and how to use this function.
    #
    # Usage: function_name [OPTIONS] [ARGUMENTS]
    #
    # Options:
    #   -v, --verbose    Enable verbose output
    #   -n, --dry-run    Show what would be changed without making changes
    #   -h, --help       Show help message and exit
    #
    # Examples:
    #   function_name                    # Run with default options
    #   function_name --dry-run          # Preview changes without executing
    #   function_name --verbose arg1     # Run with verbose output
    #
    # Notes:
    #   - Add any important notes or warnings here
    #   - Mention dependencies or requirements

    # Parse arguments using argparse (preferred over manual switch)
    argparse --name=function_name h/help v/verbose n/dry-run -- $argv
    or return 1

    # Show help if requested
    if set -q _flag_help
        echo "Usage: function_name [OPTIONS] [ARGUMENTS]"
        echo ""
        echo "Brief description of what this function does"
        echo ""
        echo "Options:"
        echo "  -v, --verbose    Enable verbose output"
        echo "  -n, --dry-run    Show what would be changed without making changes"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  function_name                    # Run with default options"
        echo "  function_name --dry-run          # Preview changes without executing"
        echo "  function_name --verbose arg1     # Run with verbose output"
        return 0
    end

    # Validate arguments
    # Example: Check for required commands
    if not command -q required_command
        echo "❌ Required command 'required_command' is not installed or not in PATH" >&2
        return 1
    end

    # Example: Validate positional arguments
    # if test (count $argv) -ne 1
    #     echo "❌ Expected exactly one argument" >&2
    #     return 1
    # end

    # Verbose output
    if set -q _flag_verbose
        echo "🔍 Running function_name..."
    end

    # Dry run mode
    if set -q _flag_dry_run
        echo "🔍 [DRY RUN] Would perform the following actions:"
        echo "   - Action 1 would be performed"
        echo "   - Action 2 would be performed"
        return 0
    end

    # Main logic starts here
    # Replace this section with your function's main logic

    # Example: Perform some action
    # if some_command
    #     echo "✅ Successfully completed action"
    # else
    #     echo "❌ Failed to complete action" >&2
    #     return 1
    # end

    return 0
end

# Completions for function_name
complete -c function_name -f

# Options
complete -c function_name -s h -l help -d "Show help message"
complete -c function_name -s v -l verbose -d "Enable verbose output"
complete -c function_name -s n -l dry-run -d "Show what would be changed"
