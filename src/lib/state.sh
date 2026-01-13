#!/usr/bin/env bash
# src/lib/state.sh - Build state management for resume capability

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# State File Management
# ==============================================================================

# State file location
STATE_DIR=""
STATE_FILE=""

# state_init(project_root) - Initialize state directory
state_init() {
    local project_root="${1:-.}"

    STATE_DIR="$project_root/.workflow/state"
    STATE_FILE="$STATE_DIR/build.state"

    # Create state directory if needed
    mkdir -p "$STATE_DIR"

    log_debug "State directory initialized: $STATE_DIR"
}

# state_save(key, value) - Save a state value
state_save() {
    local key="$1"
    local value="$2"

    if [[ -z "$STATE_FILE" ]]; then
        log_error "State not initialized. Call state_init first."
        return 1
    fi

    # Create or update state file
    if [[ -f "$STATE_FILE" ]]; then
        # Remove existing key if present
        grep -v "^${key}=" "$STATE_FILE" > "${STATE_FILE}.tmp" 2>/dev/null || true
        mv "${STATE_FILE}.tmp" "$STATE_FILE"
    fi

    # Append new value
    echo "${key}=${value}" >> "$STATE_FILE"
    log_debug "State saved: $key=$value"
}

# state_get(key) - Get a state value
state_get() {
    local key="$1"

    if [[ -z "$STATE_FILE" ]] || [[ ! -f "$STATE_FILE" ]]; then
        return 1
    fi

    local value
    value=$(grep "^${key}=" "$STATE_FILE" 2>/dev/null | cut -d= -f2-)

    if [[ -n "$value" ]]; then
        echo "$value"
        return 0
    fi

    return 1
}

# state_clear() - Clear all state
state_clear() {
    if [[ -n "$STATE_FILE" ]] && [[ -f "$STATE_FILE" ]]; then
        rm -f "$STATE_FILE"
        log_debug "State cleared"
    fi
}

# state_exists() - Check if state file exists
state_exists() {
    [[ -n "$STATE_FILE" ]] && [[ -f "$STATE_FILE" ]]
}

# ==============================================================================
# Build State Operations
# ==============================================================================

# build_state_save(task_id, iteration, milestone, status) - Save build state
build_state_save() {
    local task_id="$1"
    local iteration="$2"
    local milestone="${3:-}"
    local status="${4:-running}"

    state_save "LAST_TASK_ID" "$task_id"
    state_save "LAST_ITERATION" "$iteration"
    state_save "LAST_MILESTONE" "$milestone"
    state_save "BUILD_STATUS" "$status"
    state_save "TIMESTAMP" "$(date -Iseconds)"
    state_save "PID" "$$"
}

# build_state_load() - Load build state into variables
# Sets: BUILD_STATE_TASK, BUILD_STATE_ITERATION, BUILD_STATE_MILESTONE, BUILD_STATE_STATUS, BUILD_STATE_TIMESTAMP
build_state_load() {
    BUILD_STATE_TASK=$(state_get "LAST_TASK_ID" 2>/dev/null || echo "")
    BUILD_STATE_ITERATION=$(state_get "LAST_ITERATION" 2>/dev/null || echo "0")
    BUILD_STATE_MILESTONE=$(state_get "LAST_MILESTONE" 2>/dev/null || echo "")
    BUILD_STATE_STATUS=$(state_get "BUILD_STATUS" 2>/dev/null || echo "")
    BUILD_STATE_TIMESTAMP=$(state_get "TIMESTAMP" 2>/dev/null || echo "")
    BUILD_STATE_PID=$(state_get "PID" 2>/dev/null || echo "")
}

# build_state_is_interrupted() - Check if there's an interrupted build
build_state_is_interrupted() {
    if ! state_exists; then
        return 1
    fi

    build_state_load

    # Check if status indicates interruption
    if [[ "$BUILD_STATE_STATUS" == "running" ]]; then
        # Check if the process is still running
        if [[ -n "$BUILD_STATE_PID" ]] && kill -0 "$BUILD_STATE_PID" 2>/dev/null; then
            # Process still running - not interrupted
            return 1
        fi
        # Process not running but status is running = interrupted
        return 0
    fi

    return 1
}

# build_state_mark_complete() - Mark build as complete
build_state_mark_complete() {
    state_save "BUILD_STATUS" "complete"
    state_save "COMPLETED_AT" "$(date -Iseconds)"
}

# build_state_mark_failed(reason) - Mark build as failed
build_state_mark_failed() {
    local reason="${1:-unknown}"
    state_save "BUILD_STATUS" "failed"
    state_save "FAILURE_REASON" "$reason"
    state_save "FAILED_AT" "$(date -Iseconds)"
}

# build_state_show() - Display current build state
build_state_show() {
    if ! state_exists; then
        echo "No build state found"
        return 1
    fi

    build_state_load

    echo "Build State:"
    echo "  Status:     $BUILD_STATE_STATUS"
    echo "  Last Task:  $BUILD_STATE_TASK"
    echo "  Iteration:  $BUILD_STATE_ITERATION"
    echo "  Milestone:  ${BUILD_STATE_MILESTONE:-<none>}"
    echo "  Timestamp:  $BUILD_STATE_TIMESTAMP"
    echo "  PID:        $BUILD_STATE_PID"
}

# ==============================================================================
# Resume Helpers
# ==============================================================================

# build_state_prompt_resume() - Prompt user to resume interrupted build
# Returns: 0 if user wants to resume, 1 otherwise
build_state_prompt_resume() {
    if ! build_state_is_interrupted; then
        return 1
    fi

    build_state_load

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Interrupted build detected"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Last Task:    $BUILD_STATE_TASK"
    echo "  Iteration:    $BUILD_STATE_ITERATION"
    echo "  Milestone:    ${BUILD_STATE_MILESTONE:-<none>}"
    echo "  Interrupted:  $BUILD_STATE_TIMESTAMP"
    echo ""

    # Use interaction library if available, otherwise simple prompt
    if declare -f interaction_prompt_yn &>/dev/null; then
        if interaction_prompt_yn "Resume from last task?" "y"; then
            return 0
        fi
    else
        read -r -p "Resume from last task? [Y/n] " response
        case "$response" in
            [nN]|[nN][oO])
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    fi

    return 1
}

# build_state_get_resume_task() - Get task ID to resume from
build_state_get_resume_task() {
    if state_exists; then
        state_get "LAST_TASK_ID"
    fi
}

# build_state_get_resume_iteration() - Get iteration to resume from
build_state_get_resume_iteration() {
    if state_exists; then
        state_get "LAST_ITERATION"
    else
        echo "0"
    fi
}
