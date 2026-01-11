#!/usr/bin/env bash
# src/commands/status.sh - Show current workflow state
# Usage: workflow status

set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=src/lib/hitl.sh
source "${LIB_DIR}/hitl.sh"
# shellcheck source=src/lib/plan.sh
source "${LIB_DIR}/plan.sh"

# cmd_status() - Main status command handler
cmd_status() {
    log_debug "Starting status command"

    # Detect current workflow phase
    local phase
    local status_desc
    phase=$(detect_phase)
    status_desc=$(get_phase_description "$phase")

    # Get milestone information if plan exists
    local milestone_info=""
    if [[ -f "docs/IMPLEMENTATION_PLAN.md" ]]; then
        milestone_info=$(get_milestone_info)
    fi

    # Get HITL status
    local hitl_status
    hitl_status=$(get_hitl_status)

    # Format and display output
    echo "Phase: $phase"
    echo "Status: $status_desc"
    if [[ -n "$milestone_info" ]]; then
        echo "Milestone: $milestone_info"
    fi
    echo "HITL: $hitl_status"

    return 0
}

# detect_phase() - Determine current workflow phase
# Returns: Requirements|Architecture|Planning|Execution|Validation
detect_phase() {
    local git_root
    git_root="$(get_git_root 2>/dev/null)" || git_root="."

    # Check for key milestone files in order
    if [[ ! -f "${git_root}/docs/PRD.md" && ! -f "docs/PRD.md" ]]; then
        echo "Initialization"
        return 0
    fi

    if [[ ! -f "${git_root}/docs/ARCHITECTURE.md" && ! -f "docs/ARCHITECTURE.md" ]]; then
        echo "Requirements"
        return 0
    fi

    if [[ ! -f "${git_root}/docs/IMPLEMENTATION_PLAN.md" && ! -f "docs/IMPLEMENTATION_PLAN.md" ]]; then
        echo "Architecture"
        return 0
    fi

    # Check if plan has tasks
    local plan_file=""
    if [[ -f "${git_root}/docs/IMPLEMENTATION_PLAN.md" ]]; then
        plan_file="${git_root}/docs/IMPLEMENTATION_PLAN.md"
    elif [[ -f "docs/IMPLEMENTATION_PLAN.md" ]]; then
        plan_file="docs/IMPLEMENTATION_PLAN.md"
    fi

    if [[ -n "$plan_file" ]]; then
        # Count total and completed tasks
        local total_tasks completed_tasks
        total_tasks=$(grep -c '^[[:space:]]*-[[:space:]]*\[[xX[:space:]]\]' "$plan_file" 2>/dev/null || echo "0")
        completed_tasks=$(grep -c '^[[:space:]]*-[[:space:]]*\[[xX]\]' "$plan_file" 2>/dev/null || echo "0")

        if [[ "$total_tasks" -eq 0 ]]; then
            echo "Planning"
        elif [[ "$completed_tasks" -eq "$total_tasks" ]]; then
            echo "Validation"
        else
            echo "Execution"
        fi
    else
        echo "Planning"
    fi

    return 0
}

# get_phase_description() - Get human-readable phase description
get_phase_description() {
    local phase="$1"

    case "$phase" in
        Initialization)
            echo "Workflow not initialized (run 'workflow init')"
            ;;
        Requirements)
            echo "Gathering and clarifying requirements"
            ;;
        Architecture)
            echo "Designing system architecture"
            ;;
        Planning)
            echo "Creating implementation plan"
            ;;
        Execution)
            echo "Building features and implementing tasks"
            ;;
        Validation)
            echo "All tasks complete, ready for validation"
            ;;
        *)
            echo "Unknown state"
            ;;
    esac
}

# get_milestone_info() - Get current milestone and progress
# Returns: "N (X/Y tasks complete)" or empty if no plan
get_milestone_info() {
    local git_root
    git_root="$(get_git_root 2>/dev/null)" || git_root="."

    local plan_file=""
    if [[ -f "${git_root}/docs/IMPLEMENTATION_PLAN.md" ]]; then
        plan_file="${git_root}/docs/IMPLEMENTATION_PLAN.md"
    elif [[ -f "docs/IMPLEMENTATION_PLAN.md" ]]; then
        plan_file="docs/IMPLEMENTATION_PLAN.md"
    else
        echo ""
        return 0
    fi

    # Parse milestones and find first incomplete one
    local current_milestone=""
    local milestone_num=0
    local in_milestone=false
    local milestone_complete=true
    local milestone_total=0
    local milestone_done=0

    while IFS= read -r line; do
        # Detect milestone headers
        if [[ "$line" =~ ^##[[:space:]]+(Phase|Milestone)[[:space:]]+([0-9]+):|^##[[:space:]]+(M[0-9]+): ]]; then
            # Process previous milestone if exists
            if [[ "$in_milestone" == true ]]; then
                # Check if this milestone is incomplete
                if [[ "$milestone_complete" == false ]]; then
                    current_milestone="$milestone_num"
                    break
                fi
            fi

            # Start new milestone
            if [[ -n "${BASH_REMATCH[2]}" ]]; then
                milestone_num="${BASH_REMATCH[2]}"
            elif [[ "${BASH_REMATCH[3]}" =~ M([0-9]+) ]]; then
                milestone_num="${BASH_REMATCH[1]}"
            fi
            in_milestone=true
            milestone_complete=true
            milestone_total=0
            milestone_done=0
            continue
        fi

        # Count tasks in current milestone
        if [[ "$in_milestone" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\[([xX[:space:]])\] ]]; then
                milestone_total=$((milestone_total + 1))
                if [[ "${BASH_REMATCH[1]}" =~ [xX] ]]; then
                    milestone_done=$((milestone_done + 1))
                else
                    milestone_complete=false
                fi
            fi

            # End of milestone (next heading or empty section)
            if [[ "$line" =~ ^---$ ]] || [[ "$line" =~ ^##[[:space:]] ]]; then
                if [[ "$milestone_complete" == false ]]; then
                    current_milestone="$milestone_num"
                    break
                fi
            fi
        fi
    done < "$plan_file"

    # Handle last milestone
    if [[ "$in_milestone" == true && "$milestone_complete" == false && -z "$current_milestone" ]]; then
        current_milestone="$milestone_num"
    fi

    # Output format: "N (X/Y tasks complete)"
    if [[ -n "$current_milestone" ]]; then
        echo "$current_milestone (${milestone_done}/${milestone_total}) tasks complete"
    elif [[ "$milestone_total" -gt 0 ]]; then
        # All tasks complete
        echo "$milestone_num (${milestone_done}/${milestone_total}) tasks complete"
    else
        echo "No tasks defined"
    fi
}

# get_hitl_status() - Get HITL status string
# Returns: "enabled ([mode])" or "disabled"
get_hitl_status() {
    # Load configuration
    config_load || true

    local hitl_enabled
    hitl_enabled="$(config_get HITL_ENABLED)" || hitl_enabled="false"

    if [[ "$hitl_enabled" == "true" ]] && hitl_is_enabled; then
        local hitl_mode
        hitl_mode="$(config_get HITL_MODE)" || hitl_mode="milestone"
        echo "enabled (mode: $hitl_mode)"
    else
        echo "disabled"
    fi
}

# Main execution
main() {
    cmd_status "$@"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
