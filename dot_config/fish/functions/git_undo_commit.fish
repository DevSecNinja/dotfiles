function git_undo_commit --description "Remove or revert a git commit"
    # Parse options and arguments
    set -l reset_mode soft
    set -l commit_sha ""
    set -l show_help false

    if test "$show_help" = true
        echo "Usage: git_undo_commit [OPTIONS] [COMMIT_SHA]"
        echo ""
        echo "Remove or revert a git commit"
        echo ""
        echo "Arguments:"
        echo "  COMMIT_SHA  Specific commit to revert (creates new commit)"
        echo "              If omitted, removes the last commit"
        echo ""
        echo "Options:"
        echo "  --soft      Keep changes staged (default, only for last commit)"
        echo "  --mixed     Keep changes unstaged (only for last commit)"
        echo "  --hard      Discard all changes (DESTRUCTIVE, only for last commit)"
        echo "  -h, --help  Show this help message"
        echo ""
        echo "Examples:"
        echo "  git_undo_commit              # Remove last commit, keep changes staged"
        echo "  git_undo_commit --mixed      # Remove last commit, unstage changes"
        echo "  git_undo_commit abc123       # Revert commit abc123"
        return 0
    end

    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository" >&2
        return 1
    end

    # Check if there are any commits
    if not git rev-parse HEAD >/dev/null 2>&1
        echo "Error: No commits to undo" >&2
        return 1
    end

    for arg in $argv
        switch $arg
            case -h --help
                set show_help true
            case --soft
                set reset_mode soft
            case --mixed
                set reset_mode mixed
            case --hard
                set reset_mode hard
            case '*'
                # Assume it's a commit SHA
                if test -z "$commit_sha"
                    set commit_sha $arg
                else
                    echo "Error: Multiple commit SHAs provided" >&2
                    return 1
                end
        end
    end

    # If commit SHA is provided, revert that specific commit
    if test -n "$commit_sha"
        # Verify the commit exists
        if not git rev-parse --verify "$commit_sha^{commit}" >/dev/null 2>&1
            echo "Error: Commit '$commit_sha' not found" >&2
            return 1
        end

        echo "Reverting commit $commit_sha..."
        git revert $commit_sha

        if test $status -eq 0
            echo "✓ Commit $commit_sha reverted (new commit created)"
        else
            echo "Error: Failed to revert commit" >&2
            return 1
        end
    else
        # No SHA provided, remove last commit with reset

        # Warn if using --hard
        if test "$reset_mode" = hard
            echo "Warning: This will permanently delete your changes!"
            read -P "Are you sure? (y/N): " -l confirm
            if test "$confirm" != y -a "$confirm" != Y
                echo "Aborted"
                return 0
            end
        end

        # Perform the reset
        git reset --$reset_mode HEAD~1

        if test $status -eq 0
            echo "✓ Last commit removed (--$reset_mode)"
        else
            echo "Error: Failed to reset commit" >&2
            return 1
        end
    end
end
