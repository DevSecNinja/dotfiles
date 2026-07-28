function chezmoi_up --description 'Pull, re-init when the config template changed, then apply'
    # chezmoi_up - Pull, re-init if needed, and apply your dotfiles in one go.
    #
    # Replaces the usual `chezmoi update && chezmoi init && chezmoi apply`
    # dance. Each step is a gate: if one fails the run stops there, so a failed
    # pull can never be followed by an apply of half-updated source.
    #
    # The steps are:
    #   0. Branch guard — warn when the source repo is not on its default
    #      branch (usually main), and offer to switch and pull. `chezmoi
    #      update` pulls whichever branch is checked out, so a forgotten
    #      feature branch would otherwise be applied to the machine silently.
    #   1. `chezmoi update --apply=false` — pull the source repo only. Applying
    #      here would use the OLD config, which breaks when the pull introduces
    #      a template variable the current config does not have yet.
    #   2. `chezmoi init` — only when the config template actually changed,
    #      which is the same check chezmoi uses for its "config file template
    #      has changed" warning: the SHA256 stored in its configState bucket
    #      versus the template now on disk. Skipping is logged.
    #   3. `chezmoi apply` — apply with the freshly generated config.
    #
    # Usage: chezmoi_up [-f|--force-init] [-h|--help]   (alias: czu)
    #
    # Environment:
    #   CHEZMOI_UP_BRANCH             Expected branch (default: the source
    #                                 repo's default branch, else main)
    #   CHEZMOI_UP_SKIP_BRANCH_CHECK  Set to 1 to skip the branch guard
    #   CHEZMOI_UP_ASSUME_YES=1       Switch branch without asking
    #   CHEZMOI_UP_ASSUME_NO=1        Never switch, even on a TTY

    argparse --name=chezmoi_up h/help f/force-init -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: chezmoi_up [-f|--force-init] [-h|--help]"
        echo
        echo "Pull, re-init when the config template changed, then apply."
        echo
        echo "Options:"
        echo "  -f, --force-init   Run 'chezmoi init' even if the template is unchanged"
        echo "  -h, --help         Show this help message"
        return 0
    end

    if not command -q chezmoi
        set_color red
        echo "chezmoi_up: chezmoi is not installed or not in PATH" >&2
        set_color normal
        return 1
    end

    _chezmoi_up_check_branch

    set_color --bold blue
    echo "==> Pulling the source repository"
    set_color normal
    if not command chezmoi update --apply=false
        set_color red
        echo "✗ chezmoi update failed; not continuing to init/apply" >&2
        set_color normal
        return 1
    end

    set -l run_init false
    set -l reason ""
    if set -q _flag_force_init
        set run_init true
        set reason "forced"
    else if _chezmoi_up_needs_init
        set run_init true
        set reason "config template changed"
    end

    if test $run_init = true
        set_color --bold blue
        echo "==> Regenerating the config file ($reason)"
        set_color normal
        if not command chezmoi init
            set_color red
            echo "✗ chezmoi init failed; not continuing to apply" >&2
            set_color normal
            return 1
        end
    else
        echo "==> Config template unchanged, skipping chezmoi init"
    end

    set_color --bold blue
    echo "==> Applying"
    set_color normal
    if not command chezmoi apply
        set_color red
        echo "✗ chezmoi apply failed" >&2
        set_color normal
        return 1
    end

    set_color --bold green
    echo "✓ Dotfiles are up to date"
    set_color normal
    return 0
end

# _chezmoi_up_expected_branch -> print the branch the source repo should be on.
# Honours CHEZMOI_UP_BRANCH, else asks git which branch origin's HEAD points at
# (so a repo that renames its default branch keeps working), else falls back to
# main.
function _chezmoi_up_expected_branch --description 'Branch the chezmoi source repo should be on' --argument-names source_dir
    if set -q CHEZMOI_UP_BRANCH; and test -n "$CHEZMOI_UP_BRANCH"
        echo $CHEZMOI_UP_BRANCH
        return 0
    end

    set -l head (git -C $source_dir symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null)
    if test -n "$head"
        string replace -r '^origin/' '' -- $head
        return 0
    end

    echo main
end

# _chezmoi_up_confirm PROMPT -> success when the user answers yes.
# Non-interactive shells always answer no, so an automated run is warned but
# never blocked.
function _chezmoi_up_confirm --description 'Ask a yes/no question; always no when non-interactive' --argument-names prompt
    test "$CHEZMOI_UP_ASSUME_YES" = 1; and return 0
    test "$CHEZMOI_UP_ASSUME_NO" = 1; and return 1
    isatty stdin; or return 1

    read -l -P "$prompt [y/N] " reply
    or return 1
    string match -qir '^(y|yes)$' -- $reply
end

# _chezmoi_up_check_branch -> warn when the source repo is off its default
# branch, and offer to switch and pull.
#
# Always succeeds: being on a feature branch is a legitimate way to test
# dotfiles changes, so this warns and offers rather than blocking the run.
function _chezmoi_up_check_branch --description 'Warn when the chezmoi source repo is off its default branch'
    test "$CHEZMOI_UP_SKIP_BRANCH_CHECK" = 1; and return 0

    set -l source_dir (chezmoi source-path 2>/dev/null)
    or return 0
    test -n "$source_dir" -a -d "$source_dir"; or return 0

    # A source directory that is not a git checkout has no branch to be wrong.
    git -C $source_dir rev-parse --is-inside-work-tree >/dev/null 2>&1; or return 0

    set -l expected (_chezmoi_up_expected_branch $source_dir)
    set -l current (git -C $source_dir symbolic-ref --short -q HEAD 2>/dev/null)

    test "$current" = "$expected"; and return 0

    set -l where "detached HEAD"
    test -n "$current"; and set where "'$current'"

    set_color yellow
    if test -z "$current"
        echo "! Source repository is in detached HEAD state, not on '$expected'." >&2
    else
        echo "! Source repository is on '$current', not '$expected'." >&2
    end
    echo "! chezmoi update pulls whichever branch is checked out." >&2
    set_color normal

    if not _chezmoi_up_confirm "Switch to '$expected' and pull?"
        echo "==> Staying on $where."
        return 0
    end

    # Switching with uncommitted changes would either fail or drag the changes
    # onto the default branch; neither is something to do behind the user's back.
    set -l dirty (git -C $source_dir status --porcelain 2>/dev/null)
    if test (count $dirty) -gt 0
        set_color red
        echo "✗ Source repository has uncommitted changes; commit or stash them first." >&2
        set_color normal
        echo "==> Continuing on $where."
        return 0
    end

    set_color --bold blue
    echo "==> Switching to '$expected'"
    set_color normal
    if not git -C $source_dir checkout $expected
        set_color red
        echo "✗ Could not check out '$expected'; continuing on $where." >&2
        set_color normal
        return 0
    end

    # --ff-only: never create a merge commit in the dotfiles source behind the
    # user's back. A diverged branch is reported instead.
    if not git -C $source_dir pull --ff-only
        set_color red
        echo "✗ Could not fast-forward '$expected'; resolve it manually." >&2
        set_color normal
        return 0
    end

    return 0
end

# _chezmoi_up_config_template -> print the chezmoi config template path
# (usually <source>/.chezmoi.yaml.tmpl), or nothing when there is none.
function _chezmoi_up_config_template --description 'Locate the chezmoi config template'
    set -l source_dir (command chezmoi source-path 2>/dev/null)
    or return 0
    test -n "$source_dir"; or return 0

    for ext in yaml toml json jsonc yml
        set -l candidate "$source_dir/.chezmoi.$ext.tmpl"
        if test -f "$candidate"
            echo $candidate
            return 0
        end
    end
    return 0
end

# _chezmoi_up_sha256 FILE -> print the file's SHA256, or nothing.
function _chezmoi_up_sha256 --description 'SHA256 of a file' --argument-names file
    set -l out
    if command -q sha256sum
        set out (command sha256sum "$file" 2>/dev/null)
    else if command -q shasum
        set out (command shasum -a 256 "$file" 2>/dev/null)
    end
    test -n "$out"; or return 0
    string split -f1 ' ' -- $out[1]
end

# _chezmoi_up_needs_init -> success when `chezmoi init` should run.
# Compares the SHA256 chezmoi recorded for the config template with the
# template on disk. When either side cannot be determined we return success and
# let init run: a redundant init is harmless, a skipped one is not.
function _chezmoi_up_needs_init --description 'Has the chezmoi config template changed?'
    set -l template (_chezmoi_up_config_template)
    test -n "$template"; or return 0

    set -l state (command chezmoi state get --bucket=configState --key=configState 2>/dev/null)
    test -n "$state"; or return 0

    set -l stored (string match -r '"configTemplateContentsSHA256"\s*:\s*"([0-9a-f]+)"' -- (string join ' ' $state))[2]
    test -n "$stored"; or return 0

    set -l actual (_chezmoi_up_sha256 $template)
    test -n "$actual"; or return 0

    test "$stored" != "$actual"
end

complete -c chezmoi_up -f
complete -c chezmoi_up -s h -l help -d "Show help message"
complete -c chezmoi_up -s f -l force-init -d "Run chezmoi init even if the template is unchanged"
