function clipboard_copy --description "Copy stdin to the system clipboard, cross-platform"
    argparse --name=clipboard_copy h/help check tool -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: clipboard_copy [--check|--tool]"
        echo "Copy stdin to the system clipboard."
        return 0
    end

    set -l tool ""
    if test (uname) = Darwin; and command -q pbcopy
        set tool pbcopy
    else if set -q WAYLAND_DISPLAY; and command -q wl-copy
        set tool wl-copy
    else if command -q wl-copy; and not set -q DISPLAY
        set tool wl-copy
    else if command -q xclip
        set tool xclip
    else if command -q xsel
        set tool xsel
    else if command -q clip.exe
        set tool clip.exe
    end

    if set -q _flag_check
        test -n "$tool"
        return $status
    end

    if set -q _flag_tool
        if test -z "$tool"
            return 1
        end
        echo $tool
        return 0
    end

    if test -z "$tool"
        echo "Error: no clipboard backend found (tried pbcopy, wl-copy, xclip, xsel, clip.exe)" >&2
        return 1
    end

    switch $tool
        case pbcopy
            pbcopy
        case wl-copy
            wl-copy
        case xclip
            xclip -selection clipboard -in
        case xsel
            xsel --clipboard --input
        case clip.exe
            clip.exe
    end
end
