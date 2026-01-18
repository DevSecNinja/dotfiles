function chezmoi_reset --description 'Reset chezmoi run_once_ or run_onchange_ script states'
    # Parse arguments
    argparse --name=chezmoi_reset h/help 'f/force' -- $argv
    or return 1

    # Show help if requested
    if set -q _flag_help
        echo "Usage: chezmoi_reset [OPTIONS] TYPE"
        echo
        echo "Reset chezmoi script execution states to force scripts to run again."
        echo
        echo "Arguments:"
        echo "  TYPE          Type of scripts to reset:"
        echo "                  once      - Reset run_once_ scripts (scriptState bucket)"
        echo "                  onchange  - Reset run_onchange_ scripts (entryState bucket)"
        echo "                  all       - Reset both types"
        echo
        echo "Options:"
        echo "  -h, --help    Show this help message"
        echo "  -f, --force   Skip confirmation prompt"
        echo
        echo "Examples:"
        echo "  chezmoi_reset once        # Reset run_once_ scripts"
        echo "  chezmoi_reset onchange    # Reset run_onchange_ scripts"
        echo "  chezmoi_reset all -f      # Reset all without confirmation"
        return 0
    end

    # Check if chezmoi is available
    if not command -q chezmoi
        set_color red
        echo "Error: chezmoi is not installed or not in PATH"
        set_color normal
        return 1
    end

    # Validate argument count
    if test (count $argv) -ne 1
        set_color red
        echo "Error: Expected exactly one argument (once, onchange, or all)"
        set_color normal
        echo "Run 'chezmoi_reset --help' for usage information"
        return 1
    end

    set -l reset_type $argv[1]

    # Define bucket mappings
    set -l buckets
    switch $reset_type
        case once
            set buckets scriptState
        case onchange
            set buckets entryState
        case all
            set buckets entryState scriptState
        case '*'
            set_color red
            echo "Error: Invalid type '$reset_type'. Use 'once', 'onchange', or 'all'"
            set_color normal
            return 1
    end

    # Confirmation prompt (unless --force)
    if not set -q _flag_force
        set_color yellow
        echo "⚠️  This will reset the following chezmoi state:"
        set_color normal
        for bucket in $buckets
            switch $bucket
                case scriptState
                    echo "  • run_once_ scripts (will run again on next apply)"
                case entryState
                    echo "  • run_onchange_ scripts (will run again if changed)"
            end
        end
        echo
        set_color yellow
        read -l -P "Continue? [y/N] " confirm
        set_color normal

        switch $confirm
            case Y y
                # Continue
            case '*'
                echo "Cancelled"
                return 0
        end
    end

    # Delete buckets
    set -l success true
    for bucket in $buckets
        echo "🔄 Deleting bucket: $bucket"

        if chezmoi state delete-bucket --bucket=$bucket 2>&1
            set_color green
            echo "✓ Successfully reset $bucket"
            set_color normal
        else
            set_color red
            echo "✗ Failed to reset $bucket"
            set_color normal
            set success false
        end
    end

    # Final message
    echo
    if test $success = true
        set_color green --bold
        echo "✓ Chezmoi state reset complete!"
        set_color normal
        echo "Run 'chezmoi apply' to execute the scripts again"
        return 0
    else
        set_color red
        echo "Some operations failed"
        set_color normal
        return 1
    end
end

# Completions for chezmoi_reset
complete -c chezmoi_reset -f

# Help option
complete -c chezmoi_reset -s h -l help -d "Show help message"

# Force option
complete -c chezmoi_reset -s f -l force -d "Skip confirmation prompt"

# Reset type arguments (only suggest if no other arguments provided)
complete -c chezmoi_reset -n "not __fish_seen_subcommand_from once onchange all" -a "once" -d "Reset run_once_ scripts"
complete -c chezmoi_reset -n "not __fish_seen_subcommand_from once onchange all" -a "onchange" -d "Reset run_onchange_ scripts"
complete -c chezmoi_reset -n "not __fish_seen_subcommand_from once onchange all" -a "all" -d "Reset all script states"
