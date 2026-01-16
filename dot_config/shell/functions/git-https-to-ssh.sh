#!/bin/bash
# git-https-to-ssh - Convert Git origin remote from HTTPS to SSH
#
# This function converts the current repository's origin remote URL
# from HTTPS format to SSH format for GitHub, GitLab, and Bitbucket.
#
# Usage: git-https-to-ssh [--dry-run|-n]
#   --dry-run, -n    Show what would be changed without making changes

git-https-to-ssh() {
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                dry_run=true
                shift
                ;;
            -h|--help)
                echo "Usage: git-https-to-ssh [--dry-run|-n]"
                echo "Convert Git origin remote from HTTPS to SSH format"
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

    # Get the current origin URL
    local current_url
    current_url=$(git remote get-url origin 2>/dev/null)
    
    if [ $? -ne 0 ] || [ -z "$current_url" ]; then
        echo "❌ No origin remote found"
        return 1
    fi

    echo "🔍 Current origin: $current_url"

    # Check if it's already SSH
    if [[ "$current_url" == git@* ]]; then
        echo "✅ Origin is already using SSH format"
        return 0
    fi

    # Check if it's HTTPS and convert to SSH
    local ssh_url=""
    
    # GitHub
    if [[ "$current_url" =~ ^https://github\.com/(.+)/(.+)\.git$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@github.com:${user}/${repo}.git"
    # GitHub without .git suffix
    elif [[ "$current_url" =~ ^https://github\.com/(.+)/(.+)$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@github.com:${user}/${repo}.git"
    # GitLab
    elif [[ "$current_url" =~ ^https://gitlab\.com/(.+)/(.+)\.git$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@gitlab.com:${user}/${repo}.git"
    # GitLab without .git suffix
    elif [[ "$current_url" =~ ^https://gitlab\.com/(.+)/(.+)$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@gitlab.com:${user}/${repo}.git"
    # Bitbucket
    elif [[ "$current_url" =~ ^https://bitbucket\.org/(.+)/(.+)\.git$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@bitbucket.org:${user}/${repo}.git"
    # Bitbucket without .git suffix
    elif [[ "$current_url" =~ ^https://bitbucket\.org/(.+)/(.+)$ ]]; then
        local user="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        ssh_url="git@bitbucket.org:${user}/${repo}.git"
    # Generic HTTPS to SSH conversion
    elif [[ "$current_url" =~ ^https://([^/]+)/(.+)/(.+)\.git$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local user="${BASH_REMATCH[2]}"
        local repo="${BASH_REMATCH[3]}"
        ssh_url="git@${host}:${user}/${repo}.git"
    elif [[ "$current_url" =~ ^https://([^/]+)/(.+)/(.+)$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local user="${BASH_REMATCH[2]}"
        local repo="${BASH_REMATCH[3]}"
        ssh_url="git@${host}:${user}/${repo}.git"
    else
        echo "❌ Unsupported URL format: $current_url"
        echo "💡 This function supports GitHub, GitLab, Bitbucket, and generic Git hosting services"
        return 1
    fi

    if [[ "$dry_run" == true ]]; then
        echo "🔍 DRY RUN - No changes will be made"
        echo "🔄 Would convert to SSH: $ssh_url"
        echo "💡 Run without --dry-run to apply the changes"
    else
        echo "🔄 Converting to SSH: $ssh_url"
        
        # Update the origin remote
        if git remote set-url origin "$ssh_url"; then
            echo "✅ Successfully converted origin to SSH format"
            echo "🔗 New origin: $(git remote get-url origin)"
            echo ""
            echo "💡 Make sure you have SSH keys configured for this Git host"
            echo "   You can test the connection with: ssh -T git@$(echo "$ssh_url" | sed 's/.*@\([^:]*\):.*/\1/')"
        else
            echo "❌ Failed to update origin remote"
            return 1
        fi
    fi
}