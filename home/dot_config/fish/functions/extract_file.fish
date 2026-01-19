function extract_file --description "Extract archived files and mount disk images"
    # Parse options
    set -l verbose false
    set -l show_help false
    set -l file ""

    for arg in $argv
        switch $arg
            case -h --help
                set show_help true
            case -v --verbose
                set verbose true
            case '-*'
                echo "Unknown option: $arg" >&2
                echo "Use 'extract_file --help' for usage information" >&2
                return 1
            case '*'
                if test -z "$file"
                    set file $arg
                else
                    echo "Error: Multiple files specified. Only one file can be extracted at a time." >&2
                    return 1
                end
        end
    end

    if test "$show_help" = true
        echo "Usage: extract_file [OPTIONS] FILE"
        echo ""
        echo "Extract archived files and mount disk images"
        echo ""
        echo "Options:"
        echo "  -v, --verbose    Enable verbose output"
        echo "  -h, --help       Show this help message"
        echo ""
        echo "Supported formats:"
        echo "  .tar.bz2, .tar.gz, .bz2, .gz, .tar, .tbz2, .tgz"
        echo "  .zip, .ZIP, .rar, .Z, .pax, .pax.Z, .dmg (macOS only)"
        echo ""
        echo "Examples:"
        echo "  extract_file archive.tar.gz      # Extract a gzipped tarball"
        echo "  extract_file package.zip         # Extract a zip file"
        echo "  extract_file image.dmg           # Mount a macOS disk image"
        echo ""
        echo "Notes:"
        echo "  - .dmg/hdiutil is macOS-specific"
        echo "  - Some formats require specific tools (e.g., unrar, pax)"
        echo ""
        echo "Credit: Based on http://nparikh.org/notes/zshrc.txt"
        return 0
    end

    # Check if file argument was provided
    if test -z "$file"
        echo "Error: No file specified" >&2
        echo "Use 'extract_file --help' for usage information" >&2
        return 1
    end

    # Check if file exists
    if not test -f "$file"
        echo "Error: '$file' is not a valid file" >&2
        return 1
    end

    # Extract based on file extension
    if test "$verbose" = true
        echo "Extracting '$file'..."
    end

    switch $file
        case '*.tar.bz2'
            tar -jxvf "$file"
        case '*.tar.gz'
            tar -zxvf "$file"
        case '*.bz2'
            bunzip2 "$file"
        case '*.dmg'
            hdiutil mount "$file"
        case '*.gz'
            gunzip "$file"
        case '*.tar'
            tar -xvf "$file"
        case '*.tbz2'
            tar -jxvf "$file"
        case '*.tgz'
            tar -zxvf "$file"
        case '*.zip' '*.ZIP'
            unzip "$file"
        case '*.pax'
            cat "$file" | pax -r
        case '*.pax.Z'
            uncompress "$file" --stdout | pax -r
        case '*.rar'
            unrar x "$file"
        case '*.Z'
            uncompress "$file"
        case '*'
            echo "Error: '$file' cannot be extracted/mounted via extract_file" >&2
            echo "Unsupported file format" >&2
            return 1
    end

    set -l exit_code $status

    if test $exit_code -eq 0 -a "$verbose" = true
        echo "✓ Successfully extracted '$file'"
    end

    return $exit_code
end
