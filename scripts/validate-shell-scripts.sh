#!/bin/bash
# Validate shell script syntax
# Checks all .sh files for syntax errors

set -e

echo "🔍 Checking shell script syntax..."

# Get the source directory (current directory if not specified)
SOURCE_DIR="${1:-.}"

# Find and check all shell scripts
TEMP_FILE="$(mktemp)"
trap 'rm -f "${TEMP_FILE}"' EXIT

find "${SOURCE_DIR}" \( -name "*.sh" -o -name "*.sh.tmpl" \) | grep -v node_modules | sort >"${TEMP_FILE}"

if [ ! -s "${TEMP_FILE}" ]; then
	echo "No shell scripts found"
	exit 0
fi

SCRIPT_COUNT=0
ERROR_COUNT=0
SKIPPED_COUNT=0

while IFS= read -r script; do
	echo "  Checking: ${script}"

	# Skip template files with Chezmoi template syntax ({{- }})
	if [[ "${script}" == *.tmpl ]] && grep -q '{{' "${script}"; then
		echo "    ⏭️  Skipped (contains Chezmoi template syntax)"
		SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
		continue
	fi

	SCRIPT_COUNT=$((SCRIPT_COUNT + 1))

	# Determine which shell to use based on shebang
	SHELL_INTERPRETER="sh"
	if head -n 1 "${script}" | grep -q "#!/bin/bash\|#!/usr/bin/env bash"; then
		SHELL_INTERPRETER="bash"
	fi

	if ${SHELL_INTERPRETER} -n "${script}" 2>&1; then
		echo "    ✅ OK"
	else
		echo "    ❌ Syntax error"
		ERROR_COUNT=$((ERROR_COUNT + 1))
	fi
done <"${TEMP_FILE}"

echo ""
echo "📊 Checked ${SCRIPT_COUNT} script(s)"
if [ "${SKIPPED_COUNT}" -gt 0 ]; then
	echo "⏭️  Skipped ${SKIPPED_COUNT} template file(s)"
fi

if [ "${ERROR_COUNT}" -gt 0 ]; then
	echo "❌ Found ${ERROR_COUNT} script(s) with syntax errors"
	exit 1
fi

echo "✅ All shell scripts are syntactically correct!"
