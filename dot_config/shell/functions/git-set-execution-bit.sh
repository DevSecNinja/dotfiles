#!/bin/bash
# git-set-execution-bit - Ensure executable permissions on shell scripts
#
# This function automatically sets executable permissions on shell scripts
# in the git repository and updates the git index accordingly.
# Processes both staged and unstaged files.
#
# Usage: git-set-execution-bit [--dry-run|-n]
#   --dry-run, -n    Show what would be changed without making changes
#
# Originally based on Stack Overflow solution by ixe013
# Retrieved 2026-01-16, License - CC BY-SA 4.0

git-set-execution-bit() {
    local dry_run=false
    local changes_made=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            -h|--help)
                echo "Usage: git-set-execution-bit [--dry-run|-n]"
                echo "Ensure executable permissions on shell scripts"
                echo ""
                echo "Options:"
                echo "  --dry-run, -n    Show what would be changed without making changes"
                echo "  -h, --help       Show this help message"
                return 0
                ;;
            *)
                echo "❌ Unknown option: $1"
                echo "Use --help for usage information"
                return 1
                ;;
        esac
    done

    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "❌ Not in a git repository"
        return 1
    fi

    echo "🔧 Checking executable permissions on shell scripts..."
    if [ "$dry_run" = true ]; then
        echo "🔍 Dry run mode: no changes will be made"
    fi

    # Get list of files (both staged and unstaged)
    local files
    files=$(
        {
            git diff-index --cached --name-only HEAD 2>/dev/null || true
            git diff-index --name-only HEAD 2>/dev/null || true
            git ls-files --others --exclude-standard 2>/dev/null || true
        } | sort -u
    )

    if [ -z "$files" ]; then
        echo "ℹ️  No files found to check"
        return 0
    fi

    # Process each file
    while IFS= read -r filename; do
        # Skip empty lines
        [ -z "$filename" ] && continue

        # Only check shell script files
        if [[ "$filename" =~ \.(sh|bash)$ ]]; then
            if [ -f "$filename" ]; then
                if [ ! -x "$filename" ]; then
                    changes_made=true
                    if [ "$dry_run" = true ]; then
                        echo "🔍 Would make executable: $filename"
                    else
                        echo "🔧 Making executable: $filename"
                        chmod +x "$filename"
                        # Update git index if file is tracked
                        if git ls-files --error-unmatch "$filename" >/dev/null 2>&1; then
                            git update-index --chmod=+x -- "$filename"
                        fi
                    fi
                else
                    echo "✅ Already executable: $filename"
                fi
            else
                echo "⚠️  File not found: $filename"
            fi
        fi
    done <<< "$files"

    # Final status
    if [ "$changes_made" = false ]; then
        echo "✅ All shell scripts already have correct permissions"
    elif [ "$dry_run" = true ]; then
        echo "🔍 Dry run completed - changes would be made above"
    else
        echo "✅ Execution permissions updated successfully"
    fi
}

# If script is executed directly (not sourced), run the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    git-set-execution-bit "$@"
fi
