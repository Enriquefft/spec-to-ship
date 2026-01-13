#!/usr/bin/env bash
# src/lib/checklist.sh - Checklist validation library for quality gates

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Checklist Finding and Loading
# ==============================================================================

# Global checklist data
declare -gA CHECKLIST_ITEMS 2>/dev/null || declare -A CHECKLIST_ITEMS
CHECKLIST_ITEMS=()
CHECKLIST_FILE=""

# checklist_find(spec_dir, checklist_name) - Find checklist file
# Searches: spec_dir/checklists/name.md, spec_dir/name-checklist.md
checklist_find() {
    local spec_dir="$1"
    local name="${2:-quality}"

    # Check standard locations
    local locations=(
        "$spec_dir/checklists/${name}.md"
        "$spec_dir/${name}-checklist.md"
        "$spec_dir/checklist.md"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

# checklist_load(checklist_file) - Load checklist items from file
# Format: - [ ] Item description or - [x] Completed item
checklist_load() {
    local checklist_file="$1"

    if [[ ! -f "$checklist_file" ]]; then
        log_error "Checklist file not found: $checklist_file"
        return 1
    fi

    CHECKLIST_FILE="$checklist_file"
    CHECKLIST_ITEMS=()

    log_debug "Loading checklist from: $checklist_file"

    local item_num=0
    while IFS= read -r line; do
        # Parse checklist items: - [ ] Description or - [x] Description
        if [[ "$line" =~ ^[[:space:]]*-[[:space:]]\[([[:space:]]|x|X)\][[:space:]]*(.+) ]]; then
            ((item_num++))
            local status="${BASH_REMATCH[1]}"
            local description="${BASH_REMATCH[2]}"

            # Store as "status|description"
            if [[ "$status" =~ [xX] ]]; then
                CHECKLIST_ITEMS["C${item_num}"]="done|$description"
            else
                CHECKLIST_ITEMS["C${item_num}"]="pending|$description"
            fi

            log_debug "Loaded item C${item_num}: $description"
        fi
    done < "$checklist_file"

    log_debug "Loaded ${#CHECKLIST_ITEMS[@]} checklist items"
    return 0
}

# ==============================================================================
# Checklist Validation
# ==============================================================================

# checklist_validate(spec_dir, project_root) - Validate project against checklist
# Returns: 0 if all items pass, 1 if any failures
checklist_validate() {
    local spec_dir="$1"
    local project_root="${2:-.}"
    local failures=0
    local warnings=0
    local -a failed_items=()
    local -a warning_items=()

    # Find and load checklist
    local checklist_file
    if ! checklist_file=$(checklist_find "$spec_dir"); then
        log_debug "No checklist found in $spec_dir - skipping validation"
        return 0
    fi

    if ! checklist_load "$checklist_file"; then
        log_warn "Failed to load checklist"
        return 0
    fi

    log_info "Validating against checklist: $(basename "$checklist_file")"

    for key in $(echo "${!CHECKLIST_ITEMS[@]}" | tr ' ' '\n' | sort); do
        local item="${CHECKLIST_ITEMS[$key]}"
        local status="${item%%|*}"
        local description="${item#*|}"

        # Run validation check based on item description
        local result
        result=$(checklist_check_item "$description" "$project_root")
        local check_status=$?

        case $check_status in
            0)  # Pass
                echo "  ${COLOR_GREEN}✓${COLOR_RESET} $description"
                ;;
            1)  # Fail
                echo "  ${COLOR_RED}✗${COLOR_RESET} $description"
                echo "    → $result"
                failed_items+=("$description: $result")
                ((failures++))
                ;;
            2)  # Warning
                echo "  ${COLOR_YELLOW}⚠${COLOR_RESET} $description"
                echo "    → $result"
                warning_items+=("$description: $result")
                ((warnings++))
                ;;
        esac
    done

    echo

    if [[ $failures -gt 0 ]]; then
        echo "${COLOR_RED}✗ Checklist validation failed: $failures failures${COLOR_RESET}"
        return 1
    fi

    if [[ $warnings -gt 0 ]]; then
        echo "${COLOR_YELLOW}⚠ Checklist passed with $warnings warnings${COLOR_RESET}"
    else
        echo "${COLOR_GREEN}✓ Checklist validation passed (${#CHECKLIST_ITEMS[@]} items)${COLOR_RESET}"
    fi

    return 0
}

# checklist_check_item(description, project_root) - Check single item
# Returns: 0=pass, 1=fail, 2=warning
# Outputs: Reason message if not pass
checklist_check_item() {
    local description="$1"
    local project_root="$2"
    local desc_lower
    desc_lower=$(echo "$description" | tr '[:upper:]' '[:lower:]')

    # Pattern matching for common checklist items
    case "$desc_lower" in
        *"test"*"pass"* | *"tests pass"*)
            # Check if tests exist and pass
            # Detect test command: config > run_tests.sh > package.json > Makefile
            local test_cmd=""
            test_cmd=$(config_get "TEST_COMMAND" 2>/dev/null || echo "")

            if [[ -z "$test_cmd" ]]; then
                if [[ -f "$project_root/tests/run_tests.sh" ]]; then
                    test_cmd="bash tests/run_tests.sh"
                elif [[ -f "$project_root/package.json" ]] && grep -q '"test"' "$project_root/package.json"; then
                    test_cmd="npm test"
                elif [[ -f "$project_root/Makefile" ]] && grep -q "^test:" "$project_root/Makefile"; then
                    test_cmd="make test"
                fi
            fi

            if [[ -n "$test_cmd" ]]; then
                if ! (cd "$project_root" && eval "$test_cmd" >/dev/null 2>&1); then
                    echo "Tests failed"
                    return 1
                fi
            else
                echo "No test command configured"
                return 2
            fi
            return 0
            ;;

        *"lint"* | *"shellcheck"*)
            # Check if linting passes
            if command -v shellcheck &>/dev/null; then
                local sh_files
                mapfile -t sh_files < <(find "$project_root/src" -name "*.sh" 2>/dev/null)
                if [[ ${#sh_files[@]} -gt 0 ]]; then
                    if ! shellcheck "${sh_files[@]}" >/dev/null 2>&1; then
                        echo "Shellcheck found issues"
                        return 2
                    fi
                fi
            fi
            return 0
            ;;

        *"documentation"* | *"readme"*)
            # Check if README exists
            if [[ ! -f "$project_root/README.md" && ! -f "$project_root/readme.md" ]]; then
                echo "No README.md found"
                return 2
            fi
            return 0
            ;;

        *"no secrets"* | *"secrets"*)
            # Check for common secret patterns in code
            local secret_patterns=(
                'sk-[a-zA-Z0-9]{32,}'
                'PRIVATE.KEY'
                'password\s*=\s*["\047][^"\047]+'
            )
            for pattern in "${secret_patterns[@]}"; do
                if grep -rE "$pattern" "$project_root/src" 2>/dev/null | grep -v '.git' | head -1; then
                    echo "Potential secret found in code"
                    return 1
                fi
            done
            return 0
            ;;

        *"type"*"check"* | *"typecheck"*)
            # TypeScript type checking
            if [[ -f "$project_root/tsconfig.json" ]]; then
                if ! (cd "$project_root" && npx tsc --noEmit >/dev/null 2>&1); then
                    echo "TypeScript errors found"
                    return 1
                fi
            fi
            return 0
            ;;

        *"build"*"success"* | *"build passes"*)
            # Check if build works
            if [[ -f "$project_root/package.json" ]]; then
                if ! (cd "$project_root" && npm run build >/dev/null 2>&1); then
                    echo "Build failed"
                    return 1
                fi
            fi
            return 0
            ;;

        *"coverage"*)
            # Check test coverage (if configured)
            if [[ -f "$project_root/coverage/lcov.info" ]]; then
                local coverage
                coverage=$(grep -m1 'LF:' "$project_root/coverage/lcov.info" | cut -d: -f2)
                if [[ -n "$coverage" && "$coverage" -lt 80 ]]; then
                    echo "Coverage below 80%"
                    return 2
                fi
            fi
            return 0
            ;;

        *)
            # Unknown item - can't auto-validate, return pass with note
            return 0
            ;;
    esac
}

# ==============================================================================
# Checklist Generation
# ==============================================================================

# checklist_generate_default(output_file, project_type) - Generate default checklist
checklist_generate_default() {
    local output_file="$1"
    local project_type="${2:-bash}"

    cat > "$output_file" <<'EOF'
# Quality Checklist

Pre-merge validation checklist for this feature.

## Code Quality

- [ ] All tests pass
- [ ] Linting passes (shellcheck/eslint)
- [ ] No secrets in code
- [ ] Code follows project conventions

## Documentation

- [ ] README updated if needed
- [ ] Public APIs documented
- [ ] Complex logic has comments

## Security

- [ ] Input validation implemented
- [ ] No hardcoded credentials
- [ ] Proper error handling

## Performance

- [ ] No unnecessary API calls
- [ ] Efficient algorithms used
- [ ] Build time under budget
EOF

    log_info "Generated default checklist: $output_file"
}

# ==============================================================================
# Display Functions
# ==============================================================================

# checklist_show(spec_dir) - Display checklist summary
checklist_show() {
    local spec_dir="$1"

    local checklist_file
    if ! checklist_file=$(checklist_find "$spec_dir"); then
        echo "No checklist found in $spec_dir"
        echo ""
        echo "To create one, run:"
        echo "  mkdir -p $spec_dir/checklists"
        echo "  # Then create quality.md with checklist items"
        return 1
    fi

    if ! checklist_load "$checklist_file"; then
        return 1
    fi

    echo "# Checklist: $(basename "$checklist_file")"
    echo ""
    echo "File: $checklist_file"
    echo ""

    local done_count=0
    local total_count=${#CHECKLIST_ITEMS[@]}

    for key in $(echo "${!CHECKLIST_ITEMS[@]}" | tr ' ' '\n' | sort); do
        local item="${CHECKLIST_ITEMS[$key]}"
        local status="${item%%|*}"
        local description="${item#*|}"

        if [[ "$status" == "done" ]]; then
            echo "- [x] $description"
            ((done_count++))
        else
            echo "- [ ] $description"
        fi
    done

    echo ""
    echo "Progress: $done_count/$total_count items completed"
}

# checklist_list_items() - List all loaded checklist items
checklist_list_items() {
    if [[ ${#CHECKLIST_ITEMS[@]} -eq 0 ]]; then
        echo "No checklist items loaded"
        return 1
    fi

    for key in $(echo "${!CHECKLIST_ITEMS[@]}" | tr ' ' '\n' | sort); do
        local item="${CHECKLIST_ITEMS[$key]}"
        local status="${item%%|*}"
        local description="${item#*|}"
        echo "$key [$status]: $description"
    done
}
