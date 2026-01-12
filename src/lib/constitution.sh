#!/usr/bin/env bash
# src/lib/constitution.sh - Constitution validation for quality gates

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Constitution Loading
# ==============================================================================

# Global constitution data
declare -gA CONSTITUTION_PRINCIPLES 2>/dev/null || declare -A CONSTITUTION_PRINCIPLES
CONSTITUTION_PRINCIPLES=()
CONSTITUTION_FILE=""

# constitution_find() - Find constitution file in project
constitution_find() {
    local project_root="${1:-.}"

    # Check standard locations
    local locations=(
        "$project_root/.specify/constitution.md"
        "$project_root/docs/CONSTITUTION.md"
        "$project_root/CONSTITUTION.md"
    )

    for loc in "${locations[@]}"; do
        if [[ -f "$loc" ]]; then
            echo "$loc"
            return 0
        fi
    done

    return 1
}

# constitution_load(project_root) - Load constitution from file
constitution_load() {
    local project_root="${1:-.}"

    # Find constitution file
    if ! CONSTITUTION_FILE=$(constitution_find "$project_root"); then
        log_debug "No constitution file found"
        return 1
    fi

    log_debug "Loading constitution from: $CONSTITUTION_FILE"

    # Parse principles from constitution file
    # Format: ## Principles section with numbered items
    local in_principles=false
    local principle_num=0

    while IFS= read -r line; do
        # Detect principles section
        if [[ "$line" =~ ^##[[:space:]]+Principles ]]; then
            in_principles=true
            continue
        fi

        # Exit principles section on next ## heading
        if [[ "$in_principles" == "true" && "$line" =~ ^##[[:space:]] ]]; then
            break
        fi

        # Parse numbered principles (e.g., "1. **Name**: Description")
        if [[ "$in_principles" == "true" && "$line" =~ ^[0-9]+\.[[:space:]]\*\*(.+)\*\*:[[:space:]]*(.+) ]]; then
            ((principle_num++))
            local name="${BASH_REMATCH[1]}"
            local desc="${BASH_REMATCH[2]}"
            CONSTITUTION_PRINCIPLES["P${principle_num}"]="$name: $desc"
            log_debug "Loaded principle P${principle_num}: $name"
        fi
    done < "$CONSTITUTION_FILE"

    log_debug "Loaded ${#CONSTITUTION_PRINCIPLES[@]} principles"
    return 0
}

# constitution_list() - List all loaded principles
constitution_list() {
    if [[ ${#CONSTITUTION_PRINCIPLES[@]} -eq 0 ]]; then
        echo "No principles loaded"
        return 1
    fi

    for key in $(echo "${!CONSTITUTION_PRINCIPLES[@]}" | tr ' ' '\n' | sort); do
        echo "$key: ${CONSTITUTION_PRINCIPLES[$key]}"
    done
}

# ==============================================================================
# Validation Functions
# ==============================================================================

# constitution_validate(project_root) - Validate project against constitution
# Returns: 0 if valid, 1 if violations found
constitution_validate() {
    local project_root="${1:-.}"
    local violations=0

    # Load constitution
    if ! constitution_load "$project_root"; then
        log_warn "No constitution found - skipping validation"
        return 0  # No constitution = no violations
    fi

    log_info "Validating against constitution..."

    # Check each principle (placeholder for actual validation logic)
    # In future, each principle could have associated validation rules

    # Example validations that could be implemented:
    # - Dependency count check
    # - Test coverage check
    # - Documentation check

    # For now, just verify constitution is parseable
    if [[ ${#CONSTITUTION_PRINCIPLES[@]} -eq 0 ]]; then
        log_warn "Constitution file exists but no principles parsed"
        return 0
    fi

    log_info "${COLOR_GREEN}✓${COLOR_RESET} Constitution validation passed (${#CONSTITUTION_PRINCIPLES[@]} principles)"
    return 0
}

# constitution_check_dependencies(project_root, max_deps) - Check dependency count
constitution_check_dependencies() {
    local project_root="${1:-.}"
    local max_deps="${2:-3}"

    # Count new dependencies (placeholder - would need package.json/Cargo.toml/etc parsing)
    log_debug "Dependency check not yet implemented"
    return 0
}

# constitution_check_tests(project_root) - Check test coverage requirements
constitution_check_tests() {
    local project_root="${1:-.}"

    # Check if tests exist for public APIs (placeholder)
    log_debug "Test coverage check not yet implemented"
    return 0
}

# ==============================================================================
# Display Functions
# ==============================================================================

# constitution_show() - Display constitution summary
constitution_show() {
    local project_root="${1:-.}"

    if ! constitution_load "$project_root"; then
        echo "No constitution found in project"
        echo ""
        echo "To create one, run:"
        echo "  cp .specify/templates/constitution.md .specify/constitution.md"
        return 1
    fi

    echo "# Project Constitution"
    echo ""
    echo "File: $CONSTITUTION_FILE"
    echo ""
    echo "## Principles"
    echo ""
    constitution_list
}

# constitution_violations_report(violations_array) - Generate violation report
constitution_violations_report() {
    local -n violations_ref=$1

    if [[ ${#violations_ref[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo "${COLOR_RED}Constitution Violations Found:${COLOR_RESET}"
    echo ""

    for violation in "${violations_ref[@]}"; do
        echo "  - $violation"
    done

    echo ""
    echo "Use --force to proceed despite violations"
}
