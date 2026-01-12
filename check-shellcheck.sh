#!/usr/bin/env bash
# check-shellcheck.sh - Validate all shell scripts with shellcheck

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly RESET='\033[0m'

# Check if shellcheck is installed
if ! command -v shellcheck &> /dev/null; then
    echo -e "${RED}ERROR: shellcheck is not installed${RESET}" >&2
    echo "Install with: apt-get install shellcheck (Debian/Ubuntu)" >&2
    echo "           or: brew install shellcheck (macOS)" >&2
    exit 1
fi

# Find all shell scripts
echo "Finding shell scripts..."
scripts=()

# Add main workflow script
if [[ -f "src/workflow" ]]; then
    scripts+=("src/workflow")
fi

# Add all .sh files in src/
while IFS= read -r -d '' file; do
    scripts+=("$file")
done < <(find src -name "*.sh" -type f -print0 2>/dev/null || true)

# Add all .sh files in tests/ (if they're shell scripts, not just test data)
while IFS= read -r -d '' file; do
    # Skip fixture files
    if [[ ! "$file" =~ tests/fixtures/ ]]; then
        scripts+=("$file")
    fi
done < <(find tests -name "*.sh" -type f -print0 2>/dev/null || true)

if [[ ${#scripts[@]} -eq 0 ]]; then
    echo -e "${YELLOW}No shell scripts found${RESET}"
    exit 0
fi

echo "Found ${#scripts[@]} shell script(s) to check"
echo ""

# Run shellcheck on each script
errors=0
warnings=0
checked=0

for script in "${scripts[@]}"; do
    echo -n "Checking $script... "

    # Run shellcheck with options:
    # -x: Follow source directives
    # -S: Set severity to style (catches more issues)
    # --shell=bash: Assume bash (not sh)
    if output=$(shellcheck -x --shell=bash "$script" 2>&1); then
        echo -e "${GREEN}OK${RESET}"
        ((checked++))
    else
        # Check if there are errors or just warnings
        if echo "$output" | grep -q "^.*: error:"; then
            echo -e "${RED}FAILED${RESET}"
            ((errors++))
        else
            echo -e "${YELLOW}WARNINGS${RESET}"
            ((warnings++))
        fi

        # Show the output
        echo "$output"
        echo ""
        ((checked++))
    fi
done

# Summary
echo "================================"
echo "Shellcheck Summary:"
echo "  Checked: $checked"
echo -e "  Passed:  ${GREEN}$((checked - errors - warnings))${RESET}"
if [[ $warnings -gt 0 ]]; then
    echo -e "  Warnings: ${YELLOW}$warnings${RESET}"
fi
if [[ $errors -gt 0 ]]; then
    echo -e "  Failed:  ${RED}$errors${RESET}"
fi
echo "================================"

# Exit with error if any scripts failed
if [[ $errors -gt 0 ]]; then
    exit 1
fi

# Exit with warning code if there are warnings but no errors
if [[ $warnings -gt 0 ]]; then
    exit 2
fi

exit 0
