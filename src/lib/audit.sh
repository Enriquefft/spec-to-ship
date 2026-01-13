#!/usr/bin/env bash
# src/lib/audit.sh - Decision audit trail logging

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Audit Log Management
# ==============================================================================

# Audit log location
AUDIT_DIR=""
AUDIT_FILE=""

# audit_init(project_root) - Initialize audit logging
audit_init() {
    local project_root="${1:-.}"

    AUDIT_DIR="$project_root/.workflow/audit"

    # Create audit directory if needed
    mkdir -p "$AUDIT_DIR"

    # Create session-based audit file
    local session_id
    session_id=$(date +%Y%m%d_%H%M%S)_$$
    AUDIT_FILE="$AUDIT_DIR/session_${session_id}.log"

    # Write session header
    cat >> "$AUDIT_FILE" <<EOF
================================================================================
AUDIT LOG - Session $session_id
Started: $(date -Iseconds)
User: ${USER:-unknown}
PWD: $(pwd)
================================================================================

EOF

    log_debug "Audit log initialized: $AUDIT_FILE"
}

# audit_log(category, action, details) - Log an audit entry
audit_log() {
    local category="$1"
    local action="$2"
    local details="${3:-}"

    if [[ -z "$AUDIT_FILE" ]]; then
        log_debug "Audit not initialized, skipping: $category/$action"
        return 0
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    cat >> "$AUDIT_FILE" <<EOF
[$timestamp] [$category] $action
$(if [[ -n "$details" ]]; then echo "  Details: $details"; fi)

EOF
}

# ==============================================================================
# Decision Logging
# ==============================================================================

# audit_decision(decision_type, choice, alternatives, reasoning) - Log a decision
audit_decision() {
    local decision_type="$1"
    local choice="$2"
    local alternatives="${3:-}"
    local reasoning="${4:-}"

    if [[ -z "$AUDIT_FILE" ]]; then
        return 0
    fi

    local timestamp
    timestamp=$(date -Iseconds)

    cat >> "$AUDIT_FILE" <<EOF
[$timestamp] [DECISION] $decision_type
  Choice: $choice
$(if [[ -n "$alternatives" ]]; then echo "  Alternatives: $alternatives"; fi)
$(if [[ -n "$reasoning" ]]; then echo "  Reasoning: $reasoning"; fi)

EOF

    log_debug "Decision logged: $decision_type -> $choice"
}

# audit_hitl_decision(task_id, action, user_input) - Log HITL decision
audit_hitl_decision() {
    local task_id="$1"
    local action="$2"
    local user_input="${3:-}"

    audit_decision "HITL" "$action" "" "Task: $task_id, Input: $user_input"
}

# audit_provider_selection(phase, provider, model, fallback_used) - Log provider selection
audit_provider_selection() {
    local phase="$1"
    local provider="$2"
    local model="$3"
    local fallback_used="${4:-false}"

    local details="Phase: $phase, Provider: $provider, Model: $model"
    if [[ "$fallback_used" == "true" ]]; then
        details+=", Fallback: yes"
    fi

    audit_log "PROVIDER" "Selected provider for $phase" "$details"
}

# audit_alternative_selection(context, selected, options) - Log alternative selection
audit_alternative_selection() {
    local context="$1"
    local selected="$2"
    local options="$3"

    audit_decision "ALTERNATIVE" "$selected" "$options" "Context: $context"
}

# ==============================================================================
# Task Logging
# ==============================================================================

# audit_task_start(task_id, description) - Log task start
audit_task_start() {
    local task_id="$1"
    local description="${2:-}"

    audit_log "TASK" "Started: $task_id" "$description"
}

# audit_task_complete(task_id, duration_seconds) - Log task completion
audit_task_complete() {
    local task_id="$1"
    local duration="${2:-}"

    local details=""
    if [[ -n "$duration" ]]; then
        details="Duration: ${duration}s"
    fi

    audit_log "TASK" "Completed: $task_id" "$details"
}

# audit_task_failed(task_id, reason) - Log task failure
audit_task_failed() {
    local task_id="$1"
    local reason="${2:-unknown}"

    audit_log "TASK" "Failed: $task_id" "Reason: $reason"
}

# audit_task_skipped(task_id, reason) - Log task skip
audit_task_skipped() {
    local task_id="$1"
    local reason="${2:-}"

    audit_log "TASK" "Skipped: $task_id" "Reason: $reason"
}

# ==============================================================================
# Build Logging
# ==============================================================================

# audit_build_start(plan_file, options) - Log build start
audit_build_start() {
    local plan_file="$1"
    local options="${2:-}"

    audit_log "BUILD" "Started" "Plan: $plan_file, Options: $options"
}

# audit_build_complete(tasks_executed, duration) - Log build completion
audit_build_complete() {
    local tasks_executed="$1"
    local duration="${2:-}"

    audit_log "BUILD" "Completed" "Tasks: $tasks_executed, Duration: ${duration}s"
}

# audit_build_failed(reason, last_task) - Log build failure
audit_build_failed() {
    local reason="$1"
    local last_task="${2:-}"

    audit_log "BUILD" "Failed" "Reason: $reason, Last task: $last_task"
}

# audit_build_interrupted(task_id, iteration) - Log build interruption
audit_build_interrupted() {
    local task_id="$1"
    local iteration="${2:-}"

    audit_log "BUILD" "Interrupted" "Task: $task_id, Iteration: $iteration"
}

# audit_build_resumed(from_task, from_iteration) - Log build resume
audit_build_resumed() {
    local from_task="$1"
    local from_iteration="${2:-}"

    audit_log "BUILD" "Resumed" "From task: $from_task, Iteration: $from_iteration"
}

# ==============================================================================
# Quality Gate Logging
# ==============================================================================

# audit_gate_check(gate_name, result, details) - Log quality gate check
audit_gate_check() {
    local gate_name="$1"
    local result="$2"
    local details="${3:-}"

    audit_log "GATE" "$gate_name: $result" "$details"
}

# audit_gate_override(gate_name, reason) - Log quality gate override
audit_gate_override() {
    local gate_name="$1"
    local reason="${2:-force flag}"

    audit_log "GATE" "Override: $gate_name" "Reason: $reason"
}

# ==============================================================================
# Report Generation
# ==============================================================================

# audit_get_session_log() - Get current session log file path
audit_get_session_log() {
    echo "$AUDIT_FILE"
}

# audit_list_sessions(limit) - List recent audit sessions
audit_list_sessions() {
    local limit="${1:-10}"

    if [[ -z "$AUDIT_DIR" ]] || [[ ! -d "$AUDIT_DIR" ]]; then
        echo "No audit logs found"
        return 1
    fi

    echo "Recent audit sessions:"
    echo ""
    printf "%-30s %-20s %s\n" "SESSION" "STARTED" "ENTRIES"
    printf "%-30s %-20s %s\n" "-------" "-------" "-------"

    local count=0
    for log_file in $(ls -t "$AUDIT_DIR"/session_*.log 2>/dev/null); do
        if [[ $count -ge $limit ]]; then
            break
        fi

        local session_name
        session_name=$(basename "$log_file" .log)

        local started
        started=$(grep "^Started:" "$log_file" | head -1 | cut -d: -f2- | xargs)

        local entries
        entries=$(grep -c '^\[' "$log_file" 2>/dev/null || echo "0")

        printf "%-30s %-20s %s\n" "$session_name" "${started:0:19}" "$entries"

        ((count++))
    done
}

# audit_generate_report(session_file) - Generate human-readable report
audit_generate_report() {
    local session_file="${1:-$AUDIT_FILE}"

    if [[ ! -f "$session_file" ]]; then
        echo "Audit file not found: $session_file"
        return 1
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "AUDIT REPORT"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Summary counts
    local decisions tasks builds gates
    decisions=$(grep -c '\[DECISION\]' "$session_file" 2>/dev/null || echo "0")
    tasks=$(grep -c '\[TASK\]' "$session_file" 2>/dev/null || echo "0")
    builds=$(grep -c '\[BUILD\]' "$session_file" 2>/dev/null || echo "0")
    gates=$(grep -c '\[GATE\]' "$session_file" 2>/dev/null || echo "0")

    echo "Summary:"
    echo "  Decisions logged: $decisions"
    echo "  Task events:      $tasks"
    echo "  Build events:     $builds"
    echo "  Gate checks:      $gates"
    echo ""

    # Decisions section
    if [[ $decisions -gt 0 ]]; then
        echo "Decisions:"
        grep -A3 '\[DECISION\]' "$session_file" | head -30
        echo ""
    fi

    # Failed tasks
    local failures
    failures=$(grep '\[TASK\] Failed' "$session_file" 2>/dev/null || true)
    if [[ -n "$failures" ]]; then
        echo "Failed Tasks:"
        echo "$failures"
        echo ""
    fi

    # Gate overrides
    local overrides
    overrides=$(grep '\[GATE\] Override' "$session_file" 2>/dev/null || true)
    if [[ -n "$overrides" ]]; then
        echo "Gate Overrides:"
        echo "$overrides"
        echo ""
    fi
}

# audit_cleanup(max_sessions) - Keep only N most recent sessions
audit_cleanup() {
    local max_sessions="${1:-20}"

    if [[ -z "$AUDIT_DIR" ]] || [[ ! -d "$AUDIT_DIR" ]]; then
        return 0
    fi

    # Get list of sessions sorted by date (newest first)
    local sessions
    mapfile -t sessions < <(ls -t "$AUDIT_DIR"/session_*.log 2>/dev/null)

    local count=${#sessions[@]}

    if [[ $count -le $max_sessions ]]; then
        return 0
    fi

    # Remove old sessions
    local removed=0
    for ((i=max_sessions; i<count; i++)); do
        rm -f "${sessions[$i]}"
        ((removed++))
    done

    log_info "Cleaned up $removed old audit session(s)"
}
