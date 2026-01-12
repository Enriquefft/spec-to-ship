#!/usr/bin/env bash
# src/lib/plan.sh - Implementation plan parsing and manipulation

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Plan file path (cached after first load)
PLAN_FILE=""

# Plan data structure (associative arrays)
# Use -g flag for global scope when sourced from within a function (e.g., BATS tests)
declare -gA PLAN_TASKS 2>/dev/null || declare -A PLAN_TASKS
declare -gA PLAN_TASK_STATUS 2>/dev/null || declare -A PLAN_TASK_STATUS
declare -gA PLAN_TASK_DEPS 2>/dev/null || declare -A PLAN_TASK_DEPS
declare -gA PLAN_TASK_MILESTONE 2>/dev/null || declare -A PLAN_TASK_MILESTONE
PLAN_TASKS=()
PLAN_TASK_STATUS=()
PLAN_TASK_DEPS=()
PLAN_TASK_MILESTONE=()

# _find_plan_file() - Locate implementation plan file
_find_plan_file() {
    local git_root

    if git_root="$(get_git_root 2>/dev/null)"; then
        # Look for plan in docs/
        if [[ -f "${git_root}/docs/IMPLEMENTATION_PLAN.md" ]]; then
            echo "${git_root}/docs/IMPLEMENTATION_PLAN.md"
            return 0
        fi

        # Look for tasks.md in specs directory
        local spec_dir
        spec_dir=$(find "${git_root}/specs" -name "tasks.md" -type f 2>/dev/null | head -1)
        if [[ -n "$spec_dir" ]]; then
            echo "$spec_dir"
            return 0
        fi
    fi

    # Fallback to current directory
    if [[ -f "docs/IMPLEMENTATION_PLAN.md" ]]; then
        echo "docs/IMPLEMENTATION_PLAN.md"
        return 0
    fi

    return 1
}

# plan_load() - Load implementation plan into memory
plan_load() {
    # Find plan file if not cached
    if [[ -z "$PLAN_FILE" ]]; then
        if ! PLAN_FILE=$(_find_plan_file); then
            log_error "Implementation plan not found"
            return 1
        fi
        log_debug "Found plan file: $PLAN_FILE"
    fi

    if [[ ! -f "$PLAN_FILE" ]]; then
        log_error "Plan file not found: $PLAN_FILE"
        return 1
    fi

    log_debug "Loading plan from: $PLAN_FILE"

    # Parse plan file for task definitions
    # Expected format: - [ ] T001 [Milestone] Description
    #                  - [X] T002 [Milestone] Description (done)
    local current_milestone=""

    while IFS= read -r line; do
        # Detect milestone headers (## Phase N:, ## Milestone N:, or ## M1:)
        if [[ "$line" =~ ^##[[:space:]]+(Phase|Milestone)[[:space:]]+([0-9]+): ]]; then
            current_milestone="M${BASH_REMATCH[2]}"
            log_debug "Found milestone: $current_milestone"
            continue
        elif [[ "$line" =~ ^##[[:space:]]+(M[0-9]+): ]]; then
            current_milestone="${BASH_REMATCH[1]}"
            log_debug "Found milestone: $current_milestone"
            continue
        fi

        # Parse task line: - [ ] T001 or - [X] T001
        if [[ "$line" =~ ^-[[:space:]]\[([[:space:]xX])\][[:space:]]+(T[0-9]+) ]]; then
            local status_char="${BASH_REMATCH[1]}"
            local task_id="${BASH_REMATCH[2]}"

            # Determine status
            local status="pending"
            if [[ "$status_char" =~ [xX] ]]; then
                status="done"
            fi

            # Extract description (everything after task ID)
            local description="${line#*${task_id}}"
            description="${description#"${description%%[![:space:]]*}"}"  # trim leading space

            # Store task data
            PLAN_TASKS["$task_id"]="$description"
            PLAN_TASK_STATUS["$task_id"]="$status"
            PLAN_TASK_MILESTONE["$task_id"]="$current_milestone"

            # Parse dependencies (looks for "depends: T001, T002" in description)
            if [[ "$description" =~ depends:[[:space:]]*([T0-9,[:space:]]+) ]]; then
                local deps="${BASH_REMATCH[1]}"
                deps="${deps//,/ }"  # replace commas with spaces
                PLAN_TASK_DEPS["$task_id"]="$deps"
            else
                PLAN_TASK_DEPS["$task_id"]=""
            fi

            log_debug "Loaded task: $task_id [$status] $current_milestone"
        fi
    done < "$PLAN_FILE"

    local task_count=${#PLAN_TASKS[@]}
    log_info "Loaded $task_count tasks from plan"
    return 0
}

# plan_get_next_task(milestone) - Get next pending task for milestone
plan_get_next_task() {
    local milestone="${1:-}"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    # Iterate through tasks in order (T001, T002, ...)
    for task_id in $(echo "${!PLAN_TASKS[@]}" | tr ' ' '\n' | sort); do
        local status="${PLAN_TASK_STATUS[$task_id]}"
        local task_milestone="${PLAN_TASK_MILESTONE[$task_id]}"

        # Skip if not in requested milestone (if specified)
        if [[ -n "$milestone" && "$task_milestone" != "$milestone" ]]; then
            continue
        fi

        # Skip if not pending
        if [[ "$status" != "pending" ]]; then
            continue
        fi

        # Check if dependencies are satisfied
        if plan_deps_satisfied "$task_id"; then
            echo "$task_id"
            return 0
        fi
    done

    # No pending tasks found
    return 1
}

# plan_get_task_status(task_id) - Get status of specific task
plan_get_task_status() {
    local task_id="$1"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    if [[ -z "${PLAN_TASK_STATUS[$task_id]:-}" ]]; then
        log_error "Task not found: $task_id"
        return 1
    fi

    echo "${PLAN_TASK_STATUS[$task_id]}"
    return 0
}

# plan_set_task_status(task_id, status) - Update task status
plan_set_task_status() {
    local task_id="$1"
    local status="$2"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    if [[ -z "${PLAN_TASKS[$task_id]:-}" ]]; then
        log_error "Task not found: $task_id"
        return 1
    fi

    # Validate status
    case "$status" in
        pending|in_progress|done|failed|blocked)
            ;;
        *)
            log_error "Invalid status: $status"
            return 1
            ;;
    esac

    # Update in memory
    PLAN_TASK_STATUS["$task_id"]="$status"
    log_debug "Updated task $task_id status: $status"

    # Update in file
    local status_char=" "
    if [[ "$status" == "done" ]]; then
        status_char="X"
    fi

    # Use sed to update the checkbox
    if [[ -f "$PLAN_FILE" ]]; then
        # Create backup
        cp "$PLAN_FILE" "${PLAN_FILE}.bak"

        # Replace checkbox for this task
        sed -i "s/^- \[[[:space:]xX]\] ${task_id}/- [${status_char}] ${task_id}/" "$PLAN_FILE"

        log_debug "Updated task status in file: $PLAN_FILE"
    fi

    return 0
}

# plan_get_task_deps(task_id) - Get dependencies for task
plan_get_task_deps() {
    local task_id="$1"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    if [[ -z "${PLAN_TASKS[$task_id]:-}" ]]; then
        return 1
    fi

    echo "${PLAN_TASK_DEPS[$task_id]:-}"
    return 0
}

# plan_deps_satisfied(task_id) - Check if all dependencies are satisfied
plan_deps_satisfied() {
    local task_id="$1"

    # Get dependencies
    local deps
    deps="$(plan_get_task_deps "$task_id")"

    # No dependencies = satisfied
    if [[ -z "$deps" ]]; then
        return 0
    fi

    # Check each dependency
    for dep_id in $deps; do
        local dep_status
        dep_status="$(plan_get_task_status "$dep_id")"

        if [[ "$dep_status" != "done" ]]; then
            log_debug "Task $task_id blocked by $dep_id (status: $dep_status)"
            return 1
        fi
    done

    return 0
}

# plan_milestone_complete(milestone) - Check if all tasks in milestone are done
plan_milestone_complete() {
    local milestone="$1"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    local incomplete=0

    for task_id in "${!PLAN_TASKS[@]}"; do
        local task_milestone="${PLAN_TASK_MILESTONE[$task_id]}"

        # Skip if not in this milestone
        if [[ "$task_milestone" != "$milestone" ]]; then
            continue
        fi

        local status="${PLAN_TASK_STATUS[$task_id]}"
        if [[ "$status" != "done" ]]; then
            log_debug "Milestone $milestone incomplete: $task_id is $status"
            ((incomplete++))
        fi
    done

    if [[ $incomplete -gt 0 ]]; then
        return 1
    fi

    log_info "Milestone $milestone complete"
    return 0
}

# plan_get_task_description(task_id) - Get task description
plan_get_task_description() {
    local task_id="$1"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    if [[ -z "${PLAN_TASKS[$task_id]:-}" ]]; then
        return 1
    fi

    echo "${PLAN_TASKS[$task_id]}"
    return 0
}

# plan_list_tasks(milestone, status) - List tasks matching criteria
plan_list_tasks() {
    local milestone="${1:-}"
    local status="${2:-}"

    # Ensure plan is loaded
    if [[ ${#PLAN_TASKS[@]} -eq 0 ]]; then
        plan_load || return 1
    fi

    for task_id in $(echo "${!PLAN_TASKS[@]}" | tr ' ' '\n' | sort); do
        local task_milestone="${PLAN_TASK_MILESTONE[$task_id]}"
        local task_status="${PLAN_TASK_STATUS[$task_id]}"

        # Filter by milestone
        if [[ -n "$milestone" && "$task_milestone" != "$milestone" ]]; then
            continue
        fi

        # Filter by status
        if [[ -n "$status" && "$task_status" != "$status" ]]; then
            continue
        fi

        echo "$task_id"
    done

    return 0
}
