function git --description "Run Git and switch gh accounts after HTTPS authentication failures"
    if test "$GIT_CREDENTIAL_SWITCHER_DISABLE" = 1
        command git $argv
        return $status
    end

    set -l operation
    for argument in $argv
        if contains -- $argument push pull
            set operation $argument
            break
        end
    end

    if test -z "$operation"
        command git $argv
        return $status
    end

    set -l error_file (mktemp "$TMPDIR/git-auth-error.XXXXXX" 2>/dev/null)
    if test $status -ne 0 -o -z "$error_file"
        set error_file (mktemp -t git-auth-error.XXXXXX 2>/dev/null)
    end
    if test $status -ne 0 -o -z "$error_file"
        command git $argv
        return $status
    end

    command git $argv 2>$error_file
    set -l first_status $status
    set -l error_text (string collect <$error_file)
    command cat $error_file >&2
    command rm -f $error_file

    if test $first_status -eq 0; or not string match -rq 'fatal: Authentication failed for' -- "$error_text"
        return $first_status
    end

    set -l hosts (string match -r -g 'https://(?:[^/@]+@)?([^/ ]+)' -- "$error_text")
    set -l host $hosts[1]
    if test -z "$host"
        return $first_status
    end

    if test "$GIT_CREDENTIAL_SWITCHER_FORCE" != 1
        if not test -t 0; or not test -t 2
            return $first_status
        end
    end

    if not command -q gh
        $HOME/.config/shell/functions/log.sh WARN "GitHub CLI is unavailable; credentials for $host were not switched"
        return $first_status
    end

    set -l account_lines (command gh auth status --hostname $host --json hosts \
        --jq '.hosts | .[] | .[] | [.login, .active] | @tsv' 2>/dev/null)
    if test $status -ne 0
        $HOME/.config/shell/functions/log.sh WARN "Could not read GitHub accounts for $host"
        return $first_status
    end

    set -l current_account
    set -l next_account
    for account_line in $account_lines
        set -l fields (string split \t -- $account_line)
        set -l account $fields[1]
        set -l active $fields[2]
        if test "$active" = true -a -z "$current_account"
            set current_account $account
        end
    end

    for account_line in $account_lines
        set -l fields (string split \t -- $account_line)
        set -l account $fields[1]
        if test "$account" != "$current_account" -a -z "$next_account"
            set next_account $account
        end
    end

    if test -z "$next_account"
        $HOME/.config/shell/functions/log.sh WARN "No alternate GitHub account is configured for $host"
        return $first_status
    end

    if test -z "$current_account"
        set current_account "the current account"
    end

    read -l -P "Failed to authenticate with GitHub credential $current_account. Switch context to $next_account and retry git $operation? [y/N] " reply
    if not contains -- $reply y Y yes YES Yes
        $HOME/.config/shell/functions/log.sh NOTICE "GitHub credential switch declined"
        return $first_status
    end

    if not env -u GH_TOKEN -u GITHUB_TOKEN gh auth switch --hostname $host --user $next_account
        $HOME/.config/shell/functions/log.sh WARN "GitHub account switch failed"
        return $first_status
    end

    $HOME/.config/shell/functions/log.sh RESULT "Active GitHub account switched from $current_account to $next_account"
    $HOME/.config/shell/functions/log.sh STATE "Retrying git $operation"
    env -u GH_TOKEN -u GITHUB_TOKEN git $argv
end
