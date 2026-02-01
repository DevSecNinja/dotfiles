function git_new_branch --description "Create and switch to a new branch for protected main workflows"
    # Check if we're in a git repository
    if not git rev-parse --git-dir >/dev/null 2>&1
        echo "Error: Not in a git repository" >&2
        return 1
    end

    # Parse options and arguments
    set -l branch_name ""
    set -l base_branch (git symbolic-ref --short HEAD 2>/dev/null; or echo "main")
    set -l push_branch false
    set -l create_pr false
    set -l show_help false

    for arg in $argv
        switch $arg
            case -h --help
                set show_help true
            case -p --push
                set push_branch true
            case --pr
                set push_branch true
                set create_pr true
            case -b --base
                set base_branch $argv[2]
                set -e argv[1..2]
                continue
            case '*'
                if test -z "$branch_name"
                    set branch_name $arg
                else
                    echo "Error: Multiple branch names provided" >&2
                    return 1
                end
        end
    end

    if test "$show_help" = true
        echo "Usage: git_new_branch [OPTIONS] [BRANCH_NAME]"
        echo ""
        echo "Create and switch to a new branch (helpful for protected main branches)"
        echo ""
        echo "Arguments:"
        echo "  BRANCH_NAME  Name for the new branch"
        echo "               If omitted, generates: feature/YYYY-MM-DD-HHMMSS"
        echo ""
        echo "Options:"
        echo "  -b, --base BRANCH  Base branch to create from (default: current or 'main')"
        echo "  -p, --push         Push the new branch to remote after creation"
        echo "  --pr               Push and open a PR in the browser (requires gh CLI)"
        echo "  -h, --help         Show this help message"
        echo ""
        echo "Examples:"
        echo "  git_new_branch fix-typo              # Create feature branch 'fix-typo'"
        echo "  git_new_branch -p update-readme      # Create and push 'update-readme'"
        echo "  git_new_branch --pr add-feature      # Create, push, and open PR"
        echo "  git_new_branch -b develop my-branch  # Create from 'develop' branch"
        return 0
    end

    # Generate branch name if not provided
    if test -z "$branch_name"
        set branch_name "feature/"(date +%Y-%m-%d-%H%M%S)
        echo "Generated branch name: $branch_name"
    end

    # Ensure we're on the base branch and up to date
    echo "Updating $base_branch..."
    if not git checkout $base_branch 2>/dev/null
        echo "Error: Could not switch to base branch '$base_branch'" >&2
        return 1
    end

    if git remote get-url origin >/dev/null 2>&1
        echo "Pulling latest changes from remote..."
        git pull --ff-only
    end

    # Create and switch to new branch
    echo "Creating branch: $branch_name"
    if not git checkout -b $branch_name
        echo "Error: Failed to create branch '$branch_name'" >&2
        return 1
    end

    echo "✓ Successfully created and switched to branch: $branch_name"

    # Push if requested
    if test "$push_branch" = true
        echo "Pushing branch to remote..."
        if git push -u origin $branch_name
            echo "✓ Branch pushed to remote"
        else
            echo "Error: Failed to push branch" >&2
            return 1
        end
    end

    # Create PR if requested
    if test "$create_pr" = true
        if command -v gh >/dev/null 2>&1
            echo "Creating pull request..."
            
            # Generate default PR title from branch name
            set -l default_title (string replace -a '-' ' ' -- $branch_name | string replace -a '_' ' ' | string replace 'feature/' '' | string trim)
            
            # Prompt for PR title
            echo ""
            read -P "PR Title [$default_title]: " pr_title
            if test -z "$pr_title"
                set pr_title $default_title
            end
            
            # Prompt for PR description
            echo ""
            read -P "PR Description (press Enter for empty): " pr_body
            
            # Create the PR
            if test -z "$pr_body"
                gh pr create --base $base_branch --head $branch_name --title "$pr_title"
            else
                gh pr create --base $base_branch --head $branch_name --title "$pr_title" --body "$pr_body"
            end
            
            if test $status -eq 0
                echo "✓ Pull request created successfully"
            else
                echo "Error: Failed to create pull request" >&2
                return 1
            end
        else
            echo "Warning: 'gh' CLI not found. Install it to create PRs automatically." >&2
            echo "Install: https://cli.github.com/" >&2
        end
    end

    return 0
end
