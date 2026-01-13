#!/usr/bin/env bats
# Unit tests for src/lib/adaptive.sh

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo

    # Load required libraries
    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # Source dependencies (adaptive.sh sources common.sh)
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/adaptive.sh
    source "${LIB_DIR}/adaptive.sh"

    # Reset adaptive state between tests
    _ADAPTIVE_FAILURE_COUNT=()
    _ADAPTIVE_CURRENT_TIER=()
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

# =============================================================================
# adaptive_classify_step() tests
# =============================================================================

@test "adaptive_classify_step returns initial for step 1" {
    run adaptive_classify_step 1 ""
    [ "$status" -eq 0 ]
    [ "$output" = "initial" ]
}

@test "adaptive_classify_step returns initial for step 1 regardless of response" {
    run adaptive_classify_step 1 "<tool_code>something</tool_code>"
    [ "$status" -eq 0 ]
    [ "$output" = "initial" ]
}

@test "adaptive_classify_step returns tool for tool_code response" {
    run adaptive_classify_step 5 "<tool_code>agent_tool_read_file foo</tool_code>"
    [ "$status" -eq 0 ]
    [ "$output" = "tool" ]
}

@test "adaptive_classify_step returns final for final_answer response" {
    run adaptive_classify_step 10 "<final_answer>Task complete</final_answer>"
    [ "$status" -eq 0 ]
    [ "$output" = "final" ]
}

@test "adaptive_classify_step returns reasoning for ask_user response" {
    run adaptive_classify_step 5 "<ask_user>What should I do?</ask_user>"
    [ "$status" -eq 0 ]
    [ "$output" = "reasoning" ]
}

@test "adaptive_classify_step returns reasoning for plain text" {
    run adaptive_classify_step 3 "I need to think about this..."
    [ "$status" -eq 0 ]
    [ "$output" = "reasoning" ]
}

# =============================================================================
# adaptive_get_step_capability() tests
# =============================================================================

@test "adaptive_get_step_capability matches task complexity for initial step" {
    run adaptive_get_step_capability "initial" "high"
    [ "$output" = "high" ]

    run adaptive_get_step_capability "initial" "medium"
    [ "$output" = "medium" ]

    run adaptive_get_step_capability "initial" "low"
    [ "$output" = "low" ]
}

@test "adaptive_get_step_capability matches task complexity for reasoning step" {
    run adaptive_get_step_capability "reasoning" "high"
    [ "$output" = "high" ]

    run adaptive_get_step_capability "reasoning" "medium"
    [ "$output" = "medium" ]
}

@test "adaptive_get_step_capability matches task complexity for final step" {
    run adaptive_get_step_capability "final" "high"
    [ "$output" = "high" ]
}

@test "adaptive_get_step_capability downgrades tool steps when enabled" {
    export ADAPTIVE_TOOL_STEP_DOWNGRADE="true"

    run adaptive_get_step_capability "tool" "high"
    [ "$output" = "medium" ]

    run adaptive_get_step_capability "tool" "medium"
    [ "$output" = "low" ]

    run adaptive_get_step_capability "tool" "low"
    [ "$output" = "low" ]
}

@test "adaptive_get_step_capability does not downgrade tool steps when disabled" {
    export ADAPTIVE_TOOL_STEP_DOWNGRADE="false"

    run adaptive_get_step_capability "tool" "high"
    [ "$output" = "high" ]

    run adaptive_get_step_capability "tool" "medium"
    [ "$output" = "medium" ]
}

@test "adaptive_get_step_capability defaults invalid complexity to high" {
    run adaptive_get_step_capability "reasoning" "invalid"
    [ "$output" = "high" ]
}

# =============================================================================
# Escalation state machine tests
# =============================================================================

@test "adaptive_init_task initializes state correctly" {
    adaptive_init_task "T001" "low"

    [ "${_ADAPTIVE_FAILURE_COUNT[T001]}" -eq 0 ]
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "low" ]
}

@test "adaptive_init_task defaults to high complexity" {
    adaptive_init_task "T001"

    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "high" ]
}

@test "adaptive_init_task handles invalid complexity" {
    adaptive_init_task "T001" "invalid"

    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "high" ]
}

@test "adaptive_record_failure returns 0 on first failure (retry)" {
    adaptive_init_task "T001" "low"

    # Call directly (not via run) to check side effects
    adaptive_record_failure "T001"
    local status=$?

    [ "$status" -eq 0 ]
    [ "${_ADAPTIVE_FAILURE_COUNT[T001]}" -eq 1 ]
}

@test "adaptive_record_failure escalates after 2 failures" {
    export ADAPTIVE_RETRY_BEFORE_ESCALATE=2
    adaptive_init_task "T001" "low"

    adaptive_record_failure "T001" || true  # First failure, returns 0
    # Second failure triggers escalation, returns 1
    adaptive_record_failure "T001" && local status=0 || local status=$?

    [ "$status" -eq 1 ]  # Escalated
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "medium" ]
    [ "${_ADAPTIVE_FAILURE_COUNT[T001]}" -eq 0 ]  # Reset after escalation
}

@test "adaptive_record_failure returns 2 at max tier" {
    adaptive_init_task "T001" "high"

    adaptive_record_failure "T001"
    run adaptive_record_failure "T001"

    [ "$status" -eq 2 ]  # At max
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "high" ]  # Unchanged
}

@test "adaptive_record_success resets failure count" {
    adaptive_init_task "T001" "medium"
    adaptive_record_failure "T001"

    [ "${_ADAPTIVE_FAILURE_COUNT[T001]}" -eq 1 ]

    adaptive_record_success "T001"

    [ "${_ADAPTIVE_FAILURE_COUNT[T001]}" -eq 0 ]
}

@test "adaptive_get_current_tier returns correct tier" {
    adaptive_init_task "T001" "medium"

    run adaptive_get_current_tier "T001"
    [ "$output" = "medium" ]
}

@test "adaptive_get_current_tier returns high for unknown task" {
    run adaptive_get_current_tier "UNKNOWN"
    [ "$output" = "high" ]
}

@test "adaptive_cleanup_task removes state" {
    adaptive_init_task "T001" "low"
    adaptive_cleanup_task "T001"

    # State should be cleared
    [ -z "${_ADAPTIVE_FAILURE_COUNT[T001]:-}" ]
    [ -z "${_ADAPTIVE_CURRENT_TIER[T001]:-}" ]
}

# =============================================================================
# Escalation progression tests
# =============================================================================

@test "escalation progresses low -> medium -> high" {
    export ADAPTIVE_RETRY_BEFORE_ESCALATE=2
    adaptive_init_task "T001" "low"

    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "low" ]

    # Two failures -> escalate to medium
    # First failure returns 0 (retry), second returns 1 (escalated)
    adaptive_record_failure "T001" || true
    adaptive_record_failure "T001" || true
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "medium" ]

    # Two more failures -> escalate to high
    adaptive_record_failure "T001" || true
    adaptive_record_failure "T001" || true
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "high" ]

    # Two more failures -> stays at high (max)
    adaptive_record_failure "T001" || true
    adaptive_record_failure "T001" && local status=0 || local status=$?
    [ "$status" -eq 2 ]
    [ "${_ADAPTIVE_CURRENT_TIER[T001]}" = "high" ]
}

# =============================================================================
# History compression tests
# =============================================================================

@test "adaptive_should_compress_history returns false below threshold" {
    export ADAPTIVE_HISTORY_COMPRESS_THRESHOLD=10

    run adaptive_should_compress_history 5
    [ "$status" -ne 0 ]
}

@test "adaptive_should_compress_history returns true at threshold" {
    export ADAPTIVE_HISTORY_COMPRESS_THRESHOLD=10

    run adaptive_should_compress_history 10
    [ "$status" -eq 0 ]
}

@test "adaptive_should_compress_history returns true above threshold" {
    export ADAPTIVE_HISTORY_COMPRESS_THRESHOLD=10

    run adaptive_should_compress_history 15
    [ "$status" -eq 0 ]
}

@test "adaptive_compress_history handles missing file" {
    run adaptive_compress_history "/nonexistent/file"
    [ "$status" -eq 1 ]
}

@test "adaptive_compress_history skips if not enough steps" {
    export ADAPTIVE_HISTORY_KEEP_RECENT=3

    # Create a history file with only 2 steps
    local history_file
    history_file="$(mktemp)"
    cat > "$history_file" <<'EOF'
# System Prompt
Test prompt

# CURRENT TASK
Do something

# INTERACTION HISTORY

## Assistant (Step 1)
Response 1

## Assistant (Step 2)
Response 2
EOF

    run adaptive_compress_history "$history_file"
    [ "$status" -eq 0 ]

    # File should be unchanged (not enough steps to compress)
    grep -q "## Assistant (Step 1)" "$history_file"
    grep -q "## Assistant (Step 2)" "$history_file"

    rm -f "$history_file"
}

# =============================================================================
# Utility function tests
# =============================================================================

@test "adaptive_is_enabled returns true by default" {
    export ADAPTIVE_ENABLED="true"
    run adaptive_is_enabled
    [ "$status" -eq 0 ]
}

@test "adaptive_is_enabled returns false when disabled" {
    export ADAPTIVE_ENABLED="false"
    run adaptive_is_enabled
    [ "$status" -ne 0 ]
}

@test "adaptive_get_stats returns formatted output" {
    adaptive_init_task "T001" "medium"
    adaptive_record_failure "T001"

    run adaptive_get_stats "T001"
    [[ "$output" =~ "task=T001" ]]
    [[ "$output" =~ "tier=medium" ]]
    [[ "$output" =~ "failures=1" ]]
}
