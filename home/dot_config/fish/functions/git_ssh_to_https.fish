function git_ssh_to_https --description "Convert Git origin remote from SSH to HTTPS"
    set -l dry_run false

    # Parse arguments
    for arg in $argv
        switch $arg
            case --dry-run -n
                set dry_run true
            case -h --help
                echo "Usage: git_ssh_to_https [--dry-run|-n]"
                echo "Convert Git origin remote from SSH to HTTPS format"
                echo ""
                echo "Options:"
                echo "  --dry-run, -n    Show what would be changed without making changes"
                echo "  -h, --help       Show this help message"
                return 0
            case '*'
                echo "❌ Unknown option: $arg"
                echo "Use --help for usage information"
                return 1
        end
    end

    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "❌ Not in a git repository"
        return 1
    end

    # Get the current origin URL
    set -l current_url (git remote get-url origin 2>/dev/null)
    if test -z "$current_url"
        echo "❌ No origin remote found"
        return 1
    end

    echo "🔍 Current origin: $current_url"

    # Check if it's already HTTPS
    if string match -q 'https://*' $current_url
        echo "✅ Origin is already using HTTPS format"
        return 0
    end

    set -l https_url ""

    if string match -qr '^git@([^:]+):(.+)$' $current_url
        set -l matches (string match -r '^git@([^:]+):(.+)$' $current_url)
        set -l host $matches[2]
        set -l path (string replace -r '\.git$' '' $matches[3])
        set https_url "https://$host/$path.git"
    else if string match -qr '^ssh://git@([^/]+)/(.+)$' $current_url
        set -l matches (string match -r '^ssh://git@([^/]+)/(.+)$' $current_url)
        set -l host $matches[2]
        set -l path (string replace -r '\.git$' '' $matches[3])
        set https_url "https://$host/$path.git"
    else
        echo "❌ Unsupported URL format: $current_url"
        echo "💡 This function supports SSH URLs like git@github.com:user/repo.git and ssh://git@github.com/user/repo.git"
        return 1
    end

    if test "$dry_run" = true
        echo "🔍 DRY RUN - No changes will be made"
        echo "🔄 Would convert to HTTPS: $https_url"
        echo "💡 Run without --dry-run to apply the changes"
    else
        echo "🔄 Converting to HTTPS: $https_url"

        # Update the origin remote
        if git remote set-url origin "$https_url"
            echo "✅ Successfully converted origin to HTTPS format"
            echo "🔗 New origin: "(git remote get-url origin)
        else
            echo "❌ Failed to update origin remote"
            return 1
        end
    end
end
