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
        "$project_root/.workflow/constitution.md"
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
    # Supports multiple formats:
    # 1. Numbered list: "1. **Name**: Description"
    # 2. Heading format: "### 1. Name" with description below
    local in_principles=false
    local principle_num=0
    local pending_heading=""
    local pending_desc=""

    while IFS= read -r line; do
        # Detect principles section (flexible matching: "Principles", "Core Principles", etc.)
        if [[ "$line" =~ ^##[[:space:]]+.*Principles ]]; then
            in_principles=true
            continue
        fi

        # Exit principles section on next ## heading (but not ### subheadings)
        if [[ "$in_principles" == "true" && "$line" =~ ^##[[:space:]][^#] ]]; then
            break
        fi

        if [[ "$in_principles" == "true" ]]; then
            # Format 1: Numbered list (1. **Name**: Description)
            if [[ "$line" =~ ^[0-9]+\.[[:space:]]\*\*(.+)\*\*:[[:space:]]*(.+) ]]; then
                principle_num=$((principle_num + 1))
                local name="${BASH_REMATCH[1]}"
                local desc="${BASH_REMATCH[2]}"
                CONSTITUTION_PRINCIPLES["P${principle_num}"]="$name: $desc"
                log_debug "Loaded principle P${principle_num}: $name (list format)"
                continue
            fi

            # Format 2: Heading format (### 1. Name or ### Name)
            if [[ "$line" =~ ^###[[:space:]]+([0-9]+\.[[:space:]])?(.+) ]]; then
                # Save previous principle if exists
                if [[ -n "$pending_heading" && -n "$pending_desc" ]]; then
                    principle_num=$((principle_num + 1))
                    CONSTITUTION_PRINCIPLES["P${principle_num}"]="$pending_heading: $pending_desc"
                    log_debug "Loaded principle P${principle_num}: $pending_heading (heading format)"
                fi
                # Start new principle
                pending_heading="${BASH_REMATCH[2]}"
                pending_desc=""
                continue
            fi

            # Accumulate description for heading format
            if [[ -n "$pending_heading" && -n "$line" && ! "$line" =~ ^[[:space:]]*$ ]]; then
                # Extract Rule section specifically for structured principles
                if [[ "$line" =~ ^\*\*Rule\*\*:[[:space:]]*(.+) ]]; then
                    pending_desc="${BASH_REMATCH[1]}"
                # Fallback: capture first non-empty, non-section-marker line
                elif [[ -z "$pending_desc" && ! "$line" =~ ^\*\*[A-Z][a-z]+\*\*: && ! "$line" =~ ^- ]]; then
                    pending_desc="$line"
                fi
            fi
        fi
    done < "$CONSTITUTION_FILE"

    # Save last pending principle
    if [[ -n "$pending_heading" && -n "$pending_desc" ]]; then
        principle_num=$((principle_num + 1))
        CONSTITUTION_PRINCIPLES["P${principle_num}"]="$pending_heading: $pending_desc"
        log_debug "Loaded principle P${principle_num}: $pending_heading (heading format)"
    fi

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
    local -a violation_list=()

    # Load constitution
    if ! constitution_load "$project_root"; then
        log_warn "No constitution found - skipping validation"
        return 0  # No constitution = no violations
    fi

    log_info "Validating against constitution..."

    # Validation 1: Minimum principle count (3)
    local min_principles=3
    if [[ ${#CONSTITUTION_PRINCIPLES[@]} -lt $min_principles ]]; then
        violation_list+=("Insufficient principles: found ${#CONSTITUTION_PRINCIPLES[@]}, minimum $min_principles required")
        ((violations++))
    fi

    # Validation 2: Each principle must have description text
    for key in "${!CONSTITUTION_PRINCIPLES[@]}"; do
        local principle="${CONSTITUTION_PRINCIPLES[$key]}"
        # Check if principle has meaningful description (more than just the name)
        local desc_part="${principle#*: }"
        if [[ -z "$desc_part" ]] || [[ ${#desc_part} -lt 10 ]]; then
            violation_list+=("Principle $key has insufficient description")
            ((violations++))
        fi
    done

    # Validation 3: Governance section exists
    if [[ -n "$CONSTITUTION_FILE" ]] && [[ -f "$CONSTITUTION_FILE" ]]; then
        if ! grep -q "^## Governance" "$CONSTITUTION_FILE"; then
            violation_list+=("Missing Governance section in constitution")
            ((violations++))
        fi
    fi

    # Report violations if any
    if [[ $violations -gt 0 ]]; then
        log_warn "Constitution validation found $violations issue(s):"
        for violation in "${violation_list[@]}"; do
            log_warn "  - $violation"
        done
        return 1
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
        echo "  workflow constitution"
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
