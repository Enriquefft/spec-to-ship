#!/usr/bin/env bats
# Unit tests for src/lib/plan.sh

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo

    # Load required libraries
    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # Source dependencies
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/plan.sh
    source "${LIB_DIR}/plan.sh"

    # Reset plan state between tests
    PLAN_FILE=""
    PLAN_TASKS=()
    PLAN_TASK_STATUS=()
    PLAN_TASK_DEPS=()
    PLAN_TASK_MILESTONE=()
    PLAN_TASK_COMPLEXITY=()
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

# =============================================================================
# plan_load() tests
# =============================================================================

@test "plan_load parses simple plan file" {
    create_implementation_plan

    plan_load

    # Should have loaded tasks
    [ "${#PLAN_TASKS[@]}" -gt 0 ]
}

@test "plan_load correctly identifies pending tasks" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Create project - depends: []
- [ ] T002 Configure - depends: []
EOF

    plan_load

    [ "${PLAN_TASK_STATUS[T001]}" = "pending" ]
    [ "${PLAN_TASK_STATUS[T002]}" = "pending" ]
}

@test "plan_load correctly identifies done tasks" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 Create project - depends: []
- [x] T002 Configure - depends: []
EOF

    plan_load

    [ "${PLAN_TASK_STATUS[T001]}" = "done" ]
    [ "${PLAN_TASK_STATUS[T002]}" = "done" ]
}

@test "plan_load parses dependencies" {
    create_implementation_plan with_deps

    plan_load

    # T002 depends on T001
    [[ "${PLAN_TASK_DEPS[T002]}" =~ T001 ]]
}

@test "plan_load extracts milestone information" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task one - depends: []

## Milestone 2: Build

- [ ] T002 Task two - depends: []
EOF

    plan_load

    [ "${PLAN_TASK_MILESTONE[T001]}" = "M1" ]
    [ "${PLAN_TASK_MILESTONE[T002]}" = "M2" ]
}

@test "plan_load fails when plan file not found" {
    # Ensure no plan file exists
    rm -rf docs

    run plan_load

    [ "$status" -eq 1 ]
}

@test "plan_load handles empty plan file" {
    mkdir -p docs
    echo "# Empty Plan" > docs/IMPLEMENTATION_PLAN.md

    plan_load

    # Should succeed but have no tasks
    [ "${#PLAN_TASKS[@]}" -eq 0 ]
}

# =============================================================================
# plan_get_next_task() tests
# =============================================================================

@test "plan_get_next_task returns first pending task" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 First task - depends: []
- [ ] T002 Second task - depends: []
EOF

    plan_load

    run plan_get_next_task

    [ "$status" -eq 0 ]
    [ "$output" = "T001" ]
}

@test "plan_get_next_task skips done tasks" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 First task - depends: []
- [ ] T002 Second task - depends: []
EOF

    plan_load

    run plan_get_next_task

    [ "$status" -eq 0 ]
    [ "$output" = "T002" ]
}

@test "plan_get_next_task respects dependencies" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 First task - depends: []
- [ ] T002 Second task - depends: T001
EOF

    plan_load

    run plan_get_next_task

    # Should return T001 because T002 depends on it
    [ "$status" -eq 0 ]
    [ "$output" = "T001" ]
}

@test "plan_get_next_task returns blocked task when dependency is done" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 First task - depends: []
- [ ] T002 Second task - depends: T001
EOF

    plan_load

    run plan_get_next_task

    [ "$status" -eq 0 ]
    [ "$output" = "T002" ]
}

@test "plan_get_next_task filters by milestone" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 M1 task - depends: []

## Milestone 2: Build

- [ ] T002 M2 task - depends: []
EOF

    plan_load

    run plan_get_next_task M2

    [ "$status" -eq 0 ]
    [ "$output" = "T002" ]
}

@test "plan_get_next_task fails when no pending tasks" {
    create_implementation_plan all_done

    plan_load

    run plan_get_next_task

    [ "$status" -eq 1 ]
}

# =============================================================================
# plan_get_task_status() tests
# =============================================================================

@test "plan_get_task_status returns pending for incomplete task" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load

    run plan_get_task_status T001

    [ "$status" -eq 0 ]
    [ "$output" = "pending" ]
}

@test "plan_get_task_status returns done for complete task" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 Task - depends: []
EOF

    plan_load

    run plan_get_task_status T001

    [ "$status" -eq 0 ]
    [ "$output" = "done" ]
}

@test "plan_get_task_status fails for unknown task" {
    mkdir -p docs
    echo "# Empty" > docs/IMPLEMENTATION_PLAN.md

    plan_load

    run plan_get_task_status T999

    [ "$status" -eq 1 ]
}

# =============================================================================
# plan_set_task_status() tests
# =============================================================================

@test "plan_set_task_status updates in-memory status" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load
    plan_set_task_status T001 done

    run plan_get_task_status T001

    [ "$output" = "done" ]
}

@test "plan_set_task_status updates file" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load
    plan_set_task_status T001 done

    # Check file was updated
    grep -q "\[X\] T001" docs/IMPLEMENTATION_PLAN.md
}

@test "plan_set_task_status rejects invalid status" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load

    run plan_set_task_status T001 invalid_status

    [ "$status" -eq 1 ]
}

@test "plan_set_task_status accepts valid statuses" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load

    for valid_status in pending in_progress done failed blocked; do
        run plan_set_task_status T001 "$valid_status"
        [ "$status" -eq 0 ]
    done
}

# =============================================================================
# plan_deps_satisfied() tests
# =============================================================================

@test "plan_deps_satisfied returns true when no dependencies" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load

    run plan_deps_satisfied T001

    [ "$status" -eq 0 ]
}

@test "plan_deps_satisfied returns true when all deps done" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 First - depends: []
- [ ] T002 Second - depends: T001
EOF

    plan_load

    run plan_deps_satisfied T002

    [ "$status" -eq 0 ]
}

@test "plan_deps_satisfied returns false when dep pending" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 First - depends: []
- [ ] T002 Second - depends: T001
EOF

    plan_load

    run plan_deps_satisfied T002

    [ "$status" -eq 1 ]
}

# =============================================================================
# plan_milestone_complete() tests
# =============================================================================

@test "plan_milestone_complete returns true when all tasks done" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 Task one - depends: []
- [X] T002 Task two - depends: []
EOF

    plan_load

    run plan_milestone_complete M1

    [ "$status" -eq 0 ]
}

@test "plan_milestone_complete returns false when tasks pending" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 Task one - depends: []
- [ ] T002 Task two - depends: []
EOF

    plan_load

    run plan_milestone_complete M1

    [ "$status" -eq 1 ]
}

# =============================================================================
# plan_get_task_description() tests
# =============================================================================

@test "plan_get_task_description returns description" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Create project structure - depends: []
EOF

    plan_load

    run plan_get_task_description T001

    [ "$status" -eq 0 ]
    [[ "$output" =~ "Create project structure" ]]
}

# =============================================================================
# plan_list_tasks() tests
# =============================================================================

@test "plan_list_tasks returns all tasks" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task one - depends: []
- [ ] T002 Task two - depends: []
- [ ] T003 Task three - depends: []
EOF

    plan_load

    run plan_list_tasks

    [ "$status" -eq 0 ]
    [[ "$output" =~ T001 ]]
    [[ "$output" =~ T002 ]]
    [[ "$output" =~ T003 ]]
}

@test "plan_list_tasks filters by milestone" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 M1 task - depends: []

## Milestone 2: Build

- [ ] T002 M2 task - depends: []
EOF

    plan_load

    run plan_list_tasks M1

    [ "$status" -eq 0 ]
    [[ "$output" =~ T001 ]]
    [[ ! "$output" =~ T002 ]]
}

@test "plan_list_tasks filters by status" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [X] T001 Done task - depends: []
- [ ] T002 Pending task - depends: []
EOF

    plan_load

    run plan_list_tasks "" pending

    [ "$status" -eq 0 ]
    [[ ! "$output" =~ T001 ]]
    [[ "$output" =~ T002 ]]
}

# =============================================================================
# plan_get_task_complexity() tests
# =============================================================================

@test "plan_load parses complexity field" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Simple task - depends: [] - complexity: low
- [ ] T002 Complex task - depends: T001 - complexity: high
- [ ] T003 Medium task - depends: [] - complexity: medium
EOF

    plan_load

    [ "${PLAN_TASK_COMPLEXITY[T001]}" = "low" ]
    [ "${PLAN_TASK_COMPLEXITY[T002]}" = "high" ]
    [ "${PLAN_TASK_COMPLEXITY[T003]}" = "medium" ]
}

@test "plan_load defaults complexity to high if not specified" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task without complexity - depends: []
EOF

    plan_load

    [ "${PLAN_TASK_COMPLEXITY[T001]}" = "high" ]
}

@test "plan_get_task_complexity returns correct complexity" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: [] - complexity: medium
EOF

    plan_load

    run plan_get_task_complexity T001
    [ "$status" -eq 0 ]
    [ "$output" = "medium" ]
}

@test "plan_get_task_complexity returns high for missing complexity" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: []
EOF

    plan_load

    run plan_get_task_complexity T001
    [ "$status" -eq 0 ]
    [ "$output" = "high" ]
}

@test "plan_get_task_complexity returns high for unknown task" {
    mkdir -p docs
    echo "# Empty" > docs/IMPLEMENTATION_PLAN.md

    plan_load

    run plan_get_task_complexity T999
    [ "$status" -eq 1 ]
    # Extract last line (actual output) - log messages may appear before it
    local actual_output
    actual_output=$(echo "$output" | tail -1)
    [ "$actual_output" = "high" ]  # Default fallback
}

@test "plan_load parses complexity with various formats" {
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Task - depends: [] - complexity: low
- [ ] T002 Task - complexity: medium - depends: T001
- [ ] T003 Task - depends: []- complexity:high
EOF

    plan_load

    [ "${PLAN_TASK_COMPLEXITY[T001]}" = "low" ]
    [ "${PLAN_TASK_COMPLEXITY[T002]}" = "medium" ]
    [ "${PLAN_TASK_COMPLEXITY[T003]}" = "high" ]
}
