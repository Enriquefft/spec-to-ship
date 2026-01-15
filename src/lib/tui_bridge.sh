#!/usr/bin/env bash
# src/lib/tui_bridge.sh - Bridge between workflow and TUI application

set -euo pipefail

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# TUI state
TUI_ENABLED="${TUI_ENABLED:-false}"
TUI_PID=""
TUI_FIFO=""
TUI_LOG_FILE=""

# tui_is_enabled() - Check if TUI is enabled
tui_is_enabled() {
    [[ "$TUI_ENABLED" == "true" ]] && [[ -n "${WORKFLOW_TUI:-}" ]]
}

# tui_init() - Initialize TUI connection
tui_init() {
    if ! tui_is_enabled; then
        return 0
    fi

    log_debug "Initializing TUI bridge"

    # Create FIFO for communication
    local tmpdir
    tmpdir="$(mktemp -d)"
    TUI_FIFO="${tmpdir}/workflow.tui.fifo"
    mkfifo "$TUI_FIFO"

    # Set up log file for fallback
    local log_dir="${LOG_DIR:-.workflow/logs}"
    mkdir -p "$log_dir"
    TUI_LOG_FILE="${log_dir}/tui_$(date '+%Y%m%d_%H%M%S').log"

    # Export for subprocesses
    export TUI_FIFO
    export TUI_LOG_FILE

    # Launch TUI in background
    local tui_binary=""
    
    # Try to find TUI binary
    if command -v "workflow-tui" &>/dev/null; then
        tui_binary="workflow-tui"
    elif [[ -f "${SCRIPT_DIR}/../bin/workflow-tui-simple" ]]; then
        tui_binary="${SCRIPT_DIR}/../bin/workflow-tui-simple"
    elif [[ -f "${SCRIPT_DIR}/../workflow-tui.sh" ]]; then
        # Use bash TUI as fallback
        WORKFLOW_TUI="bash"
        "${SCRIPT_DIR}/../workflow-tui.sh" <"$TUI_FIFO" &
        TUI_PID=$!
        log_debug "Launched bash TUI with PID: $TUI_PID"
        return 0
    else
        log_warn "No TUI found, falling back to regular output"
        TUI_ENABLED="false"
        return 1
    fi
    
    # Launch the TUI binary
    "$tui_binary" <"$TUI_FIFO" &
    TUI_PID=$!
    log_debug "Launched TUI with PID: $TUI_PID"

    # Cleanup on exit
    trap 'tui_cleanup' EXIT

    return 0
}

# tui_cleanup() - Clean up TUI resources
tui_cleanup() {
    if [[ -n "$TUI_PID" ]]; then
        kill "$TUI_PID" 2>/dev/null || true
        wait "$TUI_PID" 2>/dev/null || true
        log_debug "Cleaned up TUI PID: $TUI_PID"
    fi

    if [[ -n "$TUI_FIFO" && -p "$TUI_FIFO" ]]; then
        rm -f "$TUI_FIFO"
        log_debug "Removed TUI FIFO: $TUI_FIFO"
    fi
}

# tui_emit() - Emit a JSON message to TUI
# Usage: tui_emit <json_message>
tui_emit() {
    local message="$1"
    
    if ! tui_is_enabled; then
        return 0
    fi

    # Write to FIFO (non-blocking)
    if [[ -p "$TUI_FIFO" ]]; then
        echo "$message" > "$TUI_FIFO" 2>/dev/null || true
    fi

    # Also log to file
    if [[ -n "$TUI_LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$TUI_LOG_FILE"
    fi
}

# tui_llm_start() - Emit LLM start message
# Usage: tui_llm_start <phase> <provider> <model> [task_id]
tui_llm_start() {
    local phase="$1"
    local provider="$2"
    local model="$3"
    local task_id="${4:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "llm_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "provider": "$provider",
  "model": "$model",
  "task_id": "$task_id"
}
EOF
)"
    tui_emit "$json"
}

# tui_llm_prompt() - Emit LLM prompt message
# Usage: tui_llm_prompt <task_id> <content> [tokens]
tui_llm_prompt() {
    local task_id="$1"
    local content="$2"
    local tokens="${3:-0}"
    
    # Sanitize content for JSON
    content="$(echo "$content" | sed 's/"/\\"/g' | tr '\n' '\\n')"
    
    local json
    json="$(cat <<EOF
{
  "type": "llm_prompt",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "content": "$content",
  "tokens": $tokens
}
EOF
)"
    tui_emit "$json"
}

# tui_llm_response() - Emit LLM response message
# Usage: tui_llm_response <task_id> <content> [tokens] [duration_ms]
tui_llm_response() {
    local task_id="$1"
    local content="$2"
    local tokens="${3:-0}"
    local duration_ms="${4:-0}"
    
    # Sanitize content for JSON
    content="$(echo "$content" | sed 's/"/\\"/g' | tr '\n' '\\n')"
    
    local json
    json="$(cat <<EOF
{
  "type": "llm_response",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "content": "$content",
  "tokens": $tokens,
  "duration_ms": $duration_ms
}
EOF
)"
    tui_emit "$json"
}

# tui_llm_complete() - Emit LLM complete message
# Usage: tui_llm_complete <task_id> <duration_ms> <success> [error]
tui_llm_complete() {
    local task_id="$1"
    local duration_ms="$2"
    local success="$3"
    local error="${4:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "llm_complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "duration_ms": $duration_ms,
  "success": $success,
  "error": "$error"
}
EOF
)"
    tui_emit "$json"
}

# tui_phase_start() - Emit phase start message
# Usage: tui_phase_start <phase> [tasks...]
tui_phase_start() {
    local phase="$1"
    shift
    local tasks=("$@")
    
    # Convert tasks array to JSON array
    local tasks_json=""
    if [[ ${#tasks[@]} -gt 0 ]];
    then
        tasks_json=$(printf '"%s",' "${tasks[@]}")
        tasks_json="[${tasks_json%,}]"  # Remove trailing comma
    else
        tasks_json="[]"
    fi
    
    local json
    json="$(cat <<EOF
{
  "type": "phase_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "tasks": $tasks_json
}
EOF
)"
    tui_emit "$json"
}

# tui_phase_complete() - Emit phase complete message
# Usage: tui_phase_complete <phase> <success> <duration_ms> [error]
tui_phase_complete() {
    local phase="$1"
    local success="$2"
    local duration_ms="$3"
    local error="${4:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "phase_complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "phase": "$phase",
  "success": $success,
  "duration_ms": $duration_ms,
  "error": "$error"
}
EOF
)"
    tui_emit "$json"
}

# tui_task_start() - Emit task start message
# Usage: tui_task_start <task_id> <task_name> [milestone]
tui_task_start() {
    local task_id="$1"
    local task_name="$2"
    local milestone="${3:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "task_start",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "task": "$task_name",
  "milestone": "$milestone"
}
EOF
)"
    tui_emit "$json"
}

# tui_task_update() - Emit task update message
# Usage: tui_task_update <task_id> <status> <progress> [message]
tui_task_update() {
    local task_id="$1"
    local status="$2"
    local progress="$3"
    local message="${4:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "task_update",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "status": "$status",
  "progress": $progress,
  "message": "$message"
}
EOF
)"
    tui_emit "$json"
}

# tui_task_complete() - Emit task complete message
# Usage: tui_task_complete <task_id> <success> <duration_ms> [error]
tui_task_complete() {
    local task_id="$1"
    local success="$2"
    local duration_ms="$3"
    local error="${4:-}"
    
    local json
    json="$(cat <<EOF
{
  "type": "task_complete",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "success": $success,
  "duration_ms": $duration_ms,
  "error": "$error"
}
EOF
)"
    tui_emit "$json"
}

# tui_error() - Emit error message
# Usage: tui_error <error> [source] [task_id] [trace]
tui_error() {
    local error="$1"
    local source="${2:-}"
    local task_id="${3:-}"
    local trace="${4:-}"
    
    # Sanitize
    error="$(echo "$error" | sed 's/"/\\"/g')"
    
    local json
    json="$(cat <<EOF
{
  "type": "error",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "error": "$error",
  "source": "$source",
  "task_id": "$task_id",
  "trace": "$trace"
}
EOF
)"
    tui_emit "$json"
}

# tui_log() - Emit log message
# Usage: tui_log <level> <message> [source]
tui_log() {
    local level="$1"
    local message="$2"
    local source="${3:-}"
    
    # Sanitize
    message="$(echo "$message" | sed 's/"/\\"/g')"
    
    local json
    json="$(cat <<EOF
{
  "type": "log",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "level": "$level",
  "message": "$message",
  "source": "$source"
}
EOF
)"
    tui_emit "$json"
}

# Initialize TUI if WORKFLOW_TUI is set
if [[ -n "${WORKFLOW_TUI:-}" && "${WORKFLOW_TUI}" != "false" ]]; then
    TUI_ENABLED="true"
    tui_init
fi

# tui_inject_message() - Emit LLM injection message
# Usage: tui_inject_message <task_id> <content>
tui_inject_message() {
    local task_id="$1"
    local content="$2"
    
    # Sanitize content for JSON
    content="$(echo "$content" | sed 's/"/\\"/g' | tr '\n' ' ')"
    
    local json
    json="$(cat <<INNEREOF
{
  "type": "llm_inject",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "content": "$content"
}
INNEREOF
)"
    tui_emit "$json"
}
