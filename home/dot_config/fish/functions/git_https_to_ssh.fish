function git_https_to_ssh --description "Convert Git origin remote from HTTPS to SSH"
    set -l dry_run false

    # Parse arguments
    for arg in $argv
        switch $arg
            case --dry-run -n
                set dry_run true
            case -h --help
                echo "Usage: git_https_to_ssh [--dry-run|-n]"
                echo "Convert Git origin remote from HTTPS to SSH format"
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

    # Check if it's already SSH
    if string match -q 'git@*' $current_url
        echo "✅ Origin is already using SSH format"
        return 0
    end

    set -l ssh_url ""

    # GitHub
    if string match -qr '^https://github\.com/(.+)/(.+)\.git$' $current_url
        set -l matches (string match -r '^https://github\.com/(.+)/(.+)\.git$' $current_url)
        set ssh_url "git@github.com:$matches[2]/$matches[3].git"
    else if string match -qr '^https://github\.com/(.+)/(.+)$' $current_url
        set -l matches (string match -r '^https://github\.com/(.+)/(.+)$' $current_url)
        set ssh_url "git@github.com:$matches[2]/$matches[3].git"
    # GitLab
    else if string match -qr '^https://gitlab\.com/(.+)/(.+)\.git$' $current_url
        set -l matches (string match -r '^https://gitlab\.com/(.+)/(.+)\.git$' $current_url)
        set ssh_url "git@gitlab.com:$matches[2]/$matches[3].git"
    else if string match -qr '^https://gitlab\.com/(.+)/(.+)$' $current_url
        set -l matches (string match -r '^https://gitlab\.com/(.+)/(.+)$' $current_url)
        set ssh_url "git@gitlab.com:$matches[2]/$matches[3].git"
    # Bitbucket
    else if string match -qr '^https://bitbucket\.org/(.+)/(.+)\.git$' $current_url
        set -l matches (string match -r '^https://bitbucket\.org/(.+)/(.+)\.git$' $current_url)
        set ssh_url "git@bitbucket.org:$matches[2]/$matches[3].git"
    else if string match -qr '^https://bitbucket\.org/(.+)/(.+)$' $current_url
        set -l matches (string match -r '^https://bitbucket\.org/(.+)/(.+)$' $current_url)
        set ssh_url "git@bitbucket.org:$matches[2]/$matches[3].git"
    # Generic HTTPS to SSH conversion
    else if string match -qr '^https://([^/]+)/(.+)/(.+)\.git$' $current_url
        set -l matches (string match -r '^https://([^/]+)/(.+)/(.+)\.git$' $current_url)
        set ssh_url "git@$matches[2]:$matches[3]/$matches[4].git"
    else if string match -qr '^https://([^/]+)/(.+)/(.+)$' $current_url
        set -l matches (string match -r '^https://([^/]+)/(.+)/(.+)$' $current_url)
        set ssh_url "git@$matches[2]:$matches[3]/$matches[4].git"
    else
        echo "❌ Unsupported URL format: $current_url"
        echo "💡 This function supports GitHub, GitLab, Bitbucket, and generic Git hosting services"
        return 1
    end

    if test "$dry_run" = true
        echo "🔍 DRY RUN - No changes will be made"
        echo "🔄 Would convert to SSH: $ssh_url"
        echo "💡 Run without --dry-run to apply the changes"
    else
        echo "🔄 Converting to SSH: $ssh_url"

        # Update the origin remote
        if git remote set-url origin "$ssh_url"
            echo "✅ Successfully converted origin to SSH format"
            echo "🔗 New origin: "(git remote get-url origin)
            echo ""
            echo "💡 Make sure you have SSH keys configured for this Git host"
            # Extract hostname from git@hostname:user/repo.git format
            set -l hostname (string replace -r '^.*@(.+):.*$' '$1' $ssh_url)
            echo "   You can test the connection with: ssh -T git@$hostname"
        else
            echo "❌ Failed to update origin remote"
            return 1
        end
    end
end
