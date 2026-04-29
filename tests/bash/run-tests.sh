#!/bin/bash
# Bash Test Runner
# Runs all Bats tests for bash functions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
CI_MODE=false
OUTPUT_FILE="test-results.tap"
OUTPUT_FORMAT="tap"
SPECIFIC_TESTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
	--ci)
		CI_MODE=true
		OUTPUT_FORMAT="junit"
		OUTPUT_FILE="test-results.xml"
		shift
		;;
	--output)
		OUTPUT_FILE="$2"
		shift 2
		;;
	--test)
		SPECIFIC_TESTS+=("$2")
		shift 2
		;;
	-h | --help)
		echo "Usage: $0 [OPTIONS]"
		echo "Run Bats tests for bash functions"
		echo ""
		echo "Options:"
		echo "  --ci              Run in CI mode (installs dependencies, exits on failure)"
		echo "                    Automatically uses JUnit XML format for test results"
		echo "  --output FILE     Output file for test results"
		echo "                    (default: test-results.tap, or test-results.xml in CI mode)"
		echo "  --test FILE       Run specific test file (can be used multiple times)"
		echo "  -h, --help        Show this help message"
		echo ""
		echo "Test Output:"
		echo "  Tests now include timing information and output from failing tests"
		exit 0
		;;
	*)
		echo "Unknown option: $1"
		exit 1
		;;
	esac
done

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Bash Test Suite with Bats           ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if bats is installed
if ! command -v bats >/dev/null 2>&1; then
	echo -e "${YELLOW}📦 Bats not found, installing...${NC}"

	if [ "$CI_MODE" = true ]; then
		# Install in CI mode
		echo "Installing Bats from GitHub..."
		BATS_VERSION="1.13.0"
		git clone --depth 1 --branch "v${BATS_VERSION}" https://github.com/bats-core/bats-core.git /tmp/bats-core
		cd /tmp/bats-core
		sudo ./install.sh /usr/local
		cd -
		rm -rf /tmp/bats-core
	else
		# Try to install locally
		if command -v npm >/dev/null 2>&1; then
			echo "Installing Bats via npm..."
			npm install -g bats
		elif command -v brew >/dev/null 2>&1; then
			echo "Installing Bats via Homebrew..."
			brew install bats-core
		else
			echo -e "${RED}❌ Cannot install Bats automatically${NC}"
			echo "Please install Bats manually:"
			echo "  - macOS: brew install bats-core"
			echo "  - Ubuntu/Debian: sudo apt-get install bats"
			echo "  - npm: npm install -g bats"
			echo "  - Manual: https://github.com/bats-core/bats-core#installation"
			exit 1
		fi
	fi

	# Verify installation
	if ! command -v bats >/dev/null 2>&1; then
		echo -e "${RED}❌ Bats installation failed${NC}"
		exit 1
	fi
fi

# Display Bats version
BATS_VERSION=$(bats --version)
echo -e "${GREEN}✅ Bats is available: ${BATS_VERSION}${NC}"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${SCRIPT_DIR}"

# Make OUTPUT_FILE path absolute if it's relative
if [[ ! "$OUTPUT_FILE" = /* ]]; then
	OUTPUT_FILE="${SCRIPT_DIR}/${OUTPUT_FILE}"
fi

# Find all .bats test files
echo -e "${BLUE}🔍 Discovering test files...${NC}"
TEST_FILES=()

if [ ${#SPECIFIC_TESTS[@]} -gt 0 ]; then
	# Run specific tests
	for test in "${SPECIFIC_TESTS[@]}"; do
		if [ -f "${TESTS_DIR}/${test}" ]; then
			TEST_FILES+=("${TESTS_DIR}/${test}")
			echo "  📝 Found: $(basename "$test")"
		elif [ -f "$test" ]; then
			TEST_FILES+=("$test")
			echo "  📝 Found: $(basename "$test")"
		else
			echo "  ❌ Test not found: $test"
			exit 1
		fi
	done
else
	# Run all tests
	while IFS= read -r -d '' file; do
		TEST_FILES+=("$file")
		echo "  📝 Found: $(basename "$file")"
	done < <(find "$TESTS_DIR" -path "$TESTS_DIR/libs" -prune -o -name "*.bats" -print0)
fi

if [ ${#TEST_FILES[@]} -eq 0 ]; then
	echo -e "${YELLOW}⚠️  No test files found in $TESTS_DIR${NC}"
	exit 0
fi

echo ""
echo -e "${BLUE}🧪 Running ${#TEST_FILES[@]} test file(s)...${NC}"
echo ""

# Run tests
# Build the common Bats flags for timing and output reporting
BATS_FLAGS=(--timing --print-output-on-failure)

if [ "$CI_MODE" = true ]; then
	# In CI mode, show real-time progress on stdout and save reports
	# This allows visibility of test progress to identify hanging tests
	if [ "$OUTPUT_FORMAT" = "junit" ]; then
		# Show TAP output on console for real-time progress
		# Save JUnit XML report to file for CI artifact upload
		# Create output directory for report if it doesn't exist
		OUTPUT_DIR="$(dirname "$OUTPUT_FILE")"
		mkdir -p "$OUTPUT_DIR"

		bats --formatter tap --report-formatter junit --output "$OUTPUT_DIR" "${BATS_FLAGS[@]}" "${TEST_FILES[@]}"
		EXIT_CODE=$?

		# Bats creates report.xml in the output directory, rename it to match OUTPUT_FILE
		if [ -f "$OUTPUT_DIR/report.xml" ]; then
			mv "$OUTPUT_DIR/report.xml" "$OUTPUT_FILE"
		fi
	else
		# Use TAP format with timing and output on failure
		bats --tap "${BATS_FLAGS[@]}" "${TEST_FILES[@]}" | tee "$OUTPUT_FILE"
		EXIT_CODE=${PIPESTATUS[0]}
	fi
else
	# In interactive mode, show output directly with timing and output on failure
	bats "${BATS_FLAGS[@]}" "${TEST_FILES[@]}"
	EXIT_CODE=$?
fi

# Display results based on exit code
echo ""
if [ "$EXIT_CODE" -eq 0 ]; then
	echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
	echo -e "${GREEN}║   ✅ All Tests Passed!                ║${NC}"
	echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
else
	echo -e "${RED}╔════════════════════════════════════════╗${NC}"
	echo -e "${RED}║   ❌ Some Tests Failed                ║${NC}"
	echo -e "${RED}╚════════════════════════════════════════╝${NC}"
fi

# In CI mode, display full output and summary
if [ "$CI_MODE" = true ]; then
	echo ""
	echo -e "${BLUE}📊 Test Results Summary:${NC}"
	if [ -f "$OUTPUT_FILE" ]; then
		if [ "$OUTPUT_FORMAT" = "junit" ]; then
			echo "  JUnit XML report generated: $OUTPUT_FILE"

			# Install xmllint in CI mode if not available
			if ! command -v xmllint >/dev/null 2>&1; then
				echo "  📦 Installing xmllint for XML parsing..."
				if command -v apt-get >/dev/null 2>&1; then
					sudo apt-get update -qq >/dev/null 2>&1
					sudo apt-get install -y -qq libxml2-utils >/dev/null 2>&1
				fi
			fi

			# Display a simple summary from JUnit XML
			if command -v xmllint >/dev/null 2>&1; then
				# Validate XML first
				if xmllint --noout "$OUTPUT_FILE" 2>/dev/null; then
					TOTAL=$(xmllint --xpath "count(//testcase)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					FAILURES=$(xmllint --xpath "count(//testcase/failure)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					ERRORS=$(xmllint --xpath "count(//testcase/error)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					SKIPPED=$(xmllint --xpath "count(//testcase/skipped)" "$OUTPUT_FILE" 2>/dev/null || echo "0")
					echo "  Total: $TOTAL, Failures: $FAILURES, Errors: $ERRORS, Skipped: $SKIPPED"
				else
					echo "  ⚠️  Warning: XML report is malformed or empty. Check test execution for errors."
				fi
			else
				# Fallback: parse XML with grep/sed if xmllint is still not available
				echo "  Parsing XML report..."
				TOTAL=$(grep -c "<testcase " "$OUTPUT_FILE" 2>/dev/null || echo "0")
				FAILURES=$(grep -c "<failure" "$OUTPUT_FILE" 2>/dev/null || echo "0")
				ERRORS=$(grep -c "<error" "$OUTPUT_FILE" 2>/dev/null || echo "0")
				SKIPPED=$(grep -c "<skipped" "$OUTPUT_FILE" 2>/dev/null || echo "0")
				echo "  Total: $TOTAL, Failures: $FAILURES, Errors: $ERRORS, Skipped: $SKIPPED"
			fi
		else
			# TAP format summary
			grep -E "^(ok|not ok)" "$OUTPUT_FILE" | sort | uniq -c || echo "  No test results found"
		fi
	fi

	if [ "$OUTPUT_FORMAT" = "tap" ]; then
		echo ""
		echo -e "${BLUE}📋 Full Test Output:${NC}"
		cat "$OUTPUT_FILE"
	fi
fi

exit "$EXIT_CODE"
