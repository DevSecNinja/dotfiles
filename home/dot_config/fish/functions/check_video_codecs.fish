function check_video_codecs --description "Check video files for codecs unsupported by Intel i3-9100 (UHD 630) and optionally convert them"
    # check_video_codecs - Scans video files in a directory and flags any using
    # codecs not supported by Intel i3-9100 hardware decoding (UHD 630 / Coffee Lake).
    #
    # Supported codecs: H.264, H.265/HEVC, VP8, VP9, MPEG-2, VC-1, MJPEG
    # Unsupported codecs: AV1 (requires 11th gen+), and others
    #
    # Usage: check_video_codecs [OPTIONS] [DIRECTORY]
    #
    # Options:
    #   -c, --convert         Convert unsupported files to H.265 (default target)
    #   -t, --target CODEC    Target codec: 264 or 265 (default)
    #   -r, --recursive       Scan directories recursively
    #   -n, --dry-run         Show what would be converted without converting
    #   -v, --verbose         Enable verbose output
    #   -h, --help            Show help message and exit
    #
    # Examples:
    #   check_video_codecs                          # Scan current directory
    #   check_video_codecs ~/media/movies           # Scan specific directory
    #   check_video_codecs -r ~/media               # Scan recursively
    #   check_video_codecs --convert                # Scan and convert to H.264
    #   check_video_codecs --convert --target 265   # Scan and convert to H.265
    #   check_video_codecs --convert --dry-run      # Preview conversions
    #
    # Notes:
    #   - Requires ffprobe and ffmpeg (from ffmpeg package)
    #   - Converted files are saved alongside originals with a codec suffix
    #   - Original files are NOT deleted (rename/remove manually after verifying)
    #   - Audio streams are copied without re-encoding
    #   - Subtitle streams are copied when the output container supports them

    argparse --name=check_video_codecs h/help v/verbose n/dry-run c/convert r/recursive 't/target=' -- $argv
    or return 1

    if set -q _flag_help
        echo "Usage: check_video_codecs [OPTIONS] [DIRECTORY]"
        echo ""
        echo "Check video files for codecs unsupported by Intel i3-9100 (UHD 630)"
        echo "and optionally convert them to a compatible format."
        echo ""
        echo "Options:"
        echo "  -c, --convert         Convert unsupported files to a compatible codec"
        echo "  -t, --target CODEC    Target codec: 264 or 265 (default)"
        echo "  -r, --recursive       Scan directories recursively"
        echo "  -n, --dry-run         Show what would be converted without converting"
        echo "  -v, --verbose         Enable verbose output"
        echo "  -h, --help            Show this help message"
        echo ""
        echo "Supported HW decode codecs (i3-9100 / UHD 630):"
        echo "  H.264 (AVC), H.265 (HEVC), VP8, VP9, MPEG-2, VC-1, MJPEG"
        echo ""
        echo "Unsupported codecs (will be flagged):"
        echo "  AV1, and any other codec not in the supported list"
        echo ""
        echo "Target codecs:"
        echo "  264   H.264/AVC  (libx264, CRF 18, preset slow) — best compatibility"
        echo "  265   H.265/HEVC (libx265, CRF 20, preset slow) — ~30-40% smaller files (default)"
        echo ""
        echo "Examples:"
        echo "  check_video_codecs                          # Scan current directory"
        echo "  check_video_codecs ~/media/movies           # Scan specific directory"
        echo "  check_video_codecs -r ~/media               # Scan recursively"
        echo "  check_video_codecs --convert                # Scan and convert to H.264"
        echo "  check_video_codecs --convert --target 265   # Convert to H.265"
        echo "  check_video_codecs --convert --dry-run      # Preview without converting"
        return 0
    end

    # Validate dependencies
    if not command -q ffprobe
        echo "❌ ffprobe is not installed or not in PATH (install ffmpeg)" >&2
        return 1
    end

    if set -q _flag_convert
        if not command -q ffmpeg
            echo "❌ ffmpeg is not installed or not in PATH" >&2
            return 1
        end
    end

    # Determine target directory
    set -l scan_dir "."
    if test (count $argv) -ge 1
        set scan_dir $argv[1]
    end

    if not test -d "$scan_dir"
        echo "❌ Directory not found: $scan_dir" >&2
        return 1
    end

    # Determine target codec
    set -l target_codec "265"
    if set -q _flag_target
        switch $_flag_target
            case 264 x264 h264
                set target_codec "264"
            case 265 x265 h265 hevc
                set target_codec "265"
            case '*'
                echo "❌ Unknown target codec: $_flag_target (use 264 or 265)" >&2
                return 1
        end
    end

    # Codecs supported by Intel UHD 630 (Coffee Lake / i3-9100) hardware decoding
    set -l supported_codecs \
        h264 \
        hevc \
        vp8 \
        vp9 \
        mpeg2video \
        vc1 \
        mjpeg \
        wmv3

    # Video file extensions to scan
    set -l video_extensions "mkv" "mp4" "avi" "mov" "wmv" "flv" "webm" "m4v" "ts" "mpg" "mpeg" "m2ts" "vob" "ogv"

    # Build find command for video files
    set -l find_args
    if set -q _flag_recursive
        set find_args $scan_dir -type f
    else
        set find_args $scan_dir -maxdepth 1 -type f
    end

    # Build the name filter
    set -l name_filter
    for ext in $video_extensions
        if test (count $name_filter) -gt 0
            set -a name_filter -o
        end
        set -a name_filter -iname "*.$ext"
    end

    # Find all video files
    set -l video_files
    set -l found_files (find $find_args \( $name_filter \) 2>/dev/null | sort)

    if test (count $found_files) -eq 0
        echo "📁 No video files found in: $scan_dir"
        return 0
    end

    if set -q _flag_verbose
        echo "🔍 Scanning" (count $found_files) "video file(s) in: $scan_dir"
        echo ""
    end

    # Track results
    set -l flagged_count 0
    set -l ok_count 0
    set -l error_count 0
    set -l flagged_files
    set -l flagged_codecs

    # Check each file
    for file in $found_files
        # Get the video codec using ffprobe
        set -l codec (ffprobe -v error -select_streams v:0 \
            -show_entries stream=codec_name \
            -of default=noprint_wrappers=1:nokey=1 \
            "$file" 2>/dev/null)

        if test -z "$codec"
            if set -q _flag_verbose
                echo "⚠️  Skipping (no video stream): $file"
            end
            set error_count (math $error_count + 1)
            continue
        end

        # Check if codec is supported
        set -l is_supported false
        for supported in $supported_codecs
            if test "$codec" = "$supported"
                set is_supported true
                break
            end
        end

        if test "$is_supported" = true
            set ok_count (math $ok_count + 1)
            if set -q _flag_verbose
                echo "✅ $codec — $file"
            end
        else
            set flagged_count (math $flagged_count + 1)
            set -a flagged_files "$file"
            set -a flagged_codecs "$codec"
            echo "⛔ $codec — $file"
        end
    end

    # Summary
    echo ""
    echo "──────────────────────────────────────────"
    echo "📊 Scan complete: "(count $found_files)" file(s) scanned"
    echo "   ✅ Supported:   $ok_count"
    echo "   ⛔ Unsupported: $flagged_count"
    if test $error_count -gt 0
        echo "   ⚠️  Skipped:     $error_count"
    end
    echo "──────────────────────────────────────────"

    # Convert if requested
    if set -q _flag_convert; and test $flagged_count -gt 0
        echo ""

        # Set encoding parameters based on target codec
        set -l encoder
        set -l crf_value
        set -l codec_suffix
        switch $target_codec
            case 264
                set encoder libx264
                set crf_value 18
                set codec_suffix "x264"
            case 265
                set encoder libx265
                set crf_value 20
                set codec_suffix "x265"
        end

        if set -q _flag_dry_run
            echo "🔍 [DRY RUN] Would convert $flagged_count file(s) to $encoder:"
            echo ""
        else
            echo "🔄 Converting $flagged_count file(s) to $encoder..."
            echo ""
        end

        set -l convert_ok 0
        set -l convert_fail 0

        for i in (seq (count $flagged_files))
            set -l src $flagged_files[$i]
            set -l src_codec $flagged_codecs[$i]

            # Build output filename: input.mkv → input.x264.mkv
            set -l dir (path dirname "$src")
            set -l base (path basename "$src")
            set -l ext (path extension "$base")
            set -l name (string replace -r '\.[^.]*$' '' "$base")
            set -l dest "$dir/$name.$codec_suffix$ext"

            # Skip if destination already exists
            if test -f "$dest"
                echo "⏭️  Output already exists, skipping: $dest"
                continue
            end

            if set -q _flag_dry_run
                echo "   $src_codec → $encoder: $src"
                echo "   → $dest"
                echo ""
                continue
            end

            echo "🔄 [$i/"(count $flagged_files)"] Converting: $base"
            echo "   Codec: $src_codec → $encoder (CRF $crf_value, preset slow)"
            echo "   Output: $dest"

            ffmpeg -i "$src" \
                -c:v $encoder -preset slow -crf $crf_value \
                -c:a copy \
                -c:s copy \
                -map 0 \
                -hide_banner -loglevel warning -stats \
                "$dest"

            if test $status -eq 0
                set convert_ok (math $convert_ok + 1)
                # Show size comparison
                set -l src_size (du -h "$src" | cut -f1)
                set -l dest_size (du -h "$dest" | cut -f1)
                echo "   ✅ Done — $src_size → $dest_size"
            else
                set convert_fail (math $convert_fail + 1)
                echo "   ❌ Conversion failed: $base"
                # Clean up partial output
                test -f "$dest"; and rm -f "$dest"
            end
            echo ""
        end

        if not set -q _flag_dry_run
            echo "──────────────────────────────────────────"
            echo "📊 Conversion complete:"
            echo "   ✅ Succeeded: $convert_ok"
            if test $convert_fail -gt 0
                echo "   ❌ Failed:    $convert_fail"
            end
            echo "──────────────────────────────────────────"
            echo ""
            echo "💡 Original files were kept. Remove them manually after verifying."
        end
    else if not set -q _flag_convert; and test $flagged_count -gt 0
        echo ""
        echo "💡 To convert these files, run:"
        echo "   check_video_codecs --convert $scan_dir"
        echo "   check_video_codecs --convert --target 264 $scan_dir   # for max compatibility"
    end

    return 0
end

# Completions for check_video_codecs
complete -c check_video_codecs -f -a '(__fish_complete_directories)'

# Options
complete -c check_video_codecs -s h -l help -d "Show help message"
complete -c check_video_codecs -s v -l verbose -d "Enable verbose output"
complete -c check_video_codecs -s n -l dry-run -d "Show what would be converted"
complete -c check_video_codecs -s c -l convert -d "Convert unsupported files"
complete -c check_video_codecs -s r -l recursive -d "Scan directories recursively"
complete -c check_video_codecs -s t -l target -d "Target codec" -r -a "264 265"
