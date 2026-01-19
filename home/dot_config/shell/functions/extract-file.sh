#!/bin/bash
# extract-file - Extract archived files and mount disk images
#
# Automatically detects the archive type and uses the appropriate
# extraction tool. Supports various archive formats including tar,
# zip, rar, and macOS disk images (.dmg).
#
# Usage: extract-file [OPTIONS] FILE
#   --verbose, -v    Enable verbose output
#   --help, -h       Show help message and exit
#
# Examples:
#   extract-file archive.tar.gz      # Extract a gzipped tarball
#   extract-file package.zip         # Extract a zip file
#   extract-file image.dmg           # Mount a macOS disk image
#   extract-file --verbose file.rar  # Extract with verbose output
#
# Supported formats:
#   .tar.bz2, .tar.gz, .bz2, .gz, .tar, .tbz2, .tgz
#   .zip, .ZIP, .rar, .Z, .pax, .pax.Z, .dmg (macOS only)
#
# Notes:
#   - .dmg/hdiutil is macOS-specific
#   - Some formats require specific tools to be installed (e.g., unrar, pax)
#
# Credit: Based on http://nparikh.org/notes/zshrc.txt

extract-file() {
	# Initialize variables
	local verbose=false
	local file=""

	# Parse arguments
	while [[ $# -gt 0 ]]; do
		case $1 in
		--verbose | -v)
			verbose=true
			shift
			;;
		-h | --help)
			echo "Usage: extract-file [OPTIONS] FILE"
			echo "Extract archived files and mount disk images"
			echo ""
			echo "Options:"
			echo "  --verbose, -v    Enable verbose output"
			echo "  -h, --help       Show this help message"
			echo ""
			echo "Supported formats:"
			echo "  .tar.bz2, .tar.gz, .bz2, .gz, .tar, .tbz2, .tgz"
			echo "  .zip, .ZIP, .rar, .Z, .pax, .pax.Z, .dmg (macOS only)"
			echo ""
			echo "Examples:"
			echo "  extract-file archive.tar.gz      # Extract a gzipped tarball"
			echo "  extract-file package.zip         # Extract a zip file"
			echo "  extract-file image.dmg           # Mount a macOS disk image"
			return 0
			;;
		-*)
			echo "Unknown option: $1" >&2
			echo "Use 'extract-file --help' for usage information" >&2
			return 1
			;;
		*)
			if [[ -z "$file" ]]; then
				file="$1"
			else
				echo "Error: Multiple files specified. Only one file can be extracted at a time." >&2
				return 1
			fi
			shift
			;;
		esac
	done

	# Check if file argument was provided
	if [[ -z "$file" ]]; then
		echo "Error: No file specified" >&2
		echo "Use 'extract-file --help' for usage information" >&2
		return 1
	fi

	# Check if file exists
	if [[ ! -f "$file" ]]; then
		echo "Error: '$file' is not a valid file" >&2
		return 1
	fi

	# Extract based on file extension
	if [[ "$verbose" = true ]]; then
		echo "Extracting '$file'..."
	fi

	case "$file" in
	*.tar.bz2)
		tar -jxvf "$file"
		;;
	*.tar.gz)
		tar -zxvf "$file"
		;;
	*.bz2)
		bunzip2 "$file"
		;;
	*.dmg)
		hdiutil mount "$file"
		;;
	*.gz)
		gunzip "$file"
		;;
	*.tar)
		tar -xvf "$file"
		;;
	*.tbz2)
		tar -jxvf "$file"
		;;
	*.tgz)
		tar -zxvf "$file"
		;;
	*.zip | *.ZIP)
		unzip "$file"
		;;
	*.pax)
		pax -r <"$file"
		;;
	*.pax.Z)
		uncompress "$file" --stdout | pax -r
		;;
	*.rar)
		unrar x "$file"
		;;
	*.Z)
		uncompress "$file"
		;;
	*)
		echo "Error: '$file' cannot be extracted/mounted via extract-file" >&2
		echo "Unsupported file format" >&2
		return 1
		;;
	esac

	local exit_code=$?

	if [[ $exit_code -eq 0 ]] && [[ "$verbose" = true ]]; then
		echo "✓ Successfully extracted '$file'"
	fi

	return $exit_code
}
