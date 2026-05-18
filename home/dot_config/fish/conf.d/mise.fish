# mise (rtx) initialization
# This file handles mise shell integration (PATH, hooks)
# Completions are loaded from ~/.config/fish/completions/mise.fish (if present)

# Initialize mise if available
if type -q mise
    function __dotfiles_mise_update
        set -l previous_pwd (pwd)

        if test -n "$HOME"; and test -d "$HOME"
            cd "$HOME"; or return 1
        end

        if command mise self-update -y >/dev/null 2>&1
            cd "$previous_pwd"
            return 0
        end

        if type -q brew
            command brew upgrade mise >/dev/null 2>&1
            set -l update_status $status

            cd "$previous_pwd"
            return $update_status
        end

        cd "$previous_pwd"
        return 1
    end

    function __dotfiles_mise_activate
        set -l activation_output (command mise activate fish 2>&1)
        set -l activation_status $status

        if test $activation_status -eq 0
            printf '%s\n' $activation_output | source
            return 0
        end

        if string match -qr 'mise version .* is required' -- $activation_output
            echo "mise is older than this project's required version; updating mise..." >&2

            if __dotfiles_mise_update
                set activation_output (command mise activate fish 2>&1)
                set activation_status $status

                if test $activation_status -eq 0
                    printf '%s\n' $activation_output | source
                    return 0
                end
            else
                echo "mise update failed; continuing without mise activation" >&2
            end
        end

        printf '%s\n' $activation_output >&2
        return $activation_status
    end

    if __dotfiles_mise_activate
        command mise completion fish | source
        echo "✅ mise initialized"
    end

    functions -e __dotfiles_mise_activate __dotfiles_mise_update
end
