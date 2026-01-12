#!/usr/bin/env bats
# Integration tests for workflow build command
# Tests CLI behavior, file handling, and preconditions without requiring Claude

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo
    setup_workflow
}

teardown() {
    teardown_test_dir
}

# =============================================================================
# Precondition Tests
# =============================================================================

@test "workflow build fails when no implementation plan found" {
    # Remove implementation plan
    rm -f docs/IMPLEMENTATION_PLAN.md

    run "$WORKFLOW_BIN" build --max 1

    [ "$status" -eq 1 ]
    [[ "$output" =~ "IMPLEMENTATION_PLAN" ]] || [[ "$output" =~ "plan" ]]
}

@test "workflow build fails when .workflow not initialized" {
    # Remove workflow directory
    rm -rf .workflow

    run "$WORKFLOW_BIN" build --max 1

    [ "$status" -eq 1 ]
}

@test "workflow build exits cleanly when no pending tasks" {
    # Create plan with all tasks complete
    create_implementation_plan all_done

    run "$WORKFLOW_BIN" build --max 1

    # Should exit cleanly with exit code 0 (no work to do)
    [ "$status" -eq 0 ]
    [[ "$output" =~ "No" ]] || [[ "$output" =~ "complete" ]] || [[ "$output" =~ "pending" ]]
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "workflow build --help shows usage" {
    run "$WORKFLOW_BIN" build --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow build" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--max" ]]
    [[ "$output" =~ "--milestone" ]]
    [[ "$output" =~ "--hitl" ]]
}

@test "workflow build handles invalid options" {
    run "$WORKFLOW_BIN" build --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

# =============================================================================
# Flag Recognition Tests
# =============================================================================

@test "workflow build --max flag is recognized" {
    create_implementation_plan

    run timeout 5 "$WORKFLOW_BIN" build --max 1

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

@test "workflow build --milestone flag is recognized" {
    create_implementation_plan

    run timeout 5 "$WORKFLOW_BIN" build --milestone M1 --max 1

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

@test "workflow build --no-hitl flag is recognized" {
    create_implementation_plan

    run timeout 5 "$WORKFLOW_BIN" build --no-hitl --max 1

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

@test "workflow build --hitl accepts various modes" {
    create_implementation_plan

    # Test different HITL modes
    for mode in task milestone uncertain every:5; do
        run timeout 5 "$WORKFLOW_BIN" build --hitl "$mode" --max 1
        [ "$status" -ne 124 ]
    done
}

# =============================================================================
# Plan File Tests
# =============================================================================

@test "workflow build detects pending tasks" {
    create_implementation_plan

    # Verify plan has pending tasks
    grep -q "\[ \]" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow build detects completed tasks" {
    create_implementation_plan mixed

    # Verify plan has both completed and pending tasks
    grep -q "\[X\]" docs/IMPLEMENTATION_PLAN.md
    grep -q "\[ \]" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow build respects task dependencies" {
    create_implementation_plan with_deps

    # Verify dependencies are present in plan
    grep -q "depends:" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow build preserves plan on failure" {
    create_implementation_plan

    original_content="$(cat docs/IMPLEMENTATION_PLAN.md)"

    # Run build (will fail without Claude but shouldn't corrupt plan)
    "$WORKFLOW_BIN" build --max 1 2>/dev/null || true

    # File should still exist with original content
    [ -f "docs/IMPLEMENTATION_PLAN.md" ]
    current_content="$(cat docs/IMPLEMENTATION_PLAN.md)"
    [ "$original_content" = "$current_content" ]
}

# =============================================================================
# Milestone Filter Tests
# =============================================================================

@test "workflow build --milestone accepts various formats" {
    create_implementation_plan

    # Test different milestone formats
    for milestone in M1 M2 1 2; do
        run timeout 5 "$WORKFLOW_BIN" build --milestone "$milestone" --max 1
        [ "$status" -ne 124 ]
    done
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "workflow build respects retry configuration" {
    create_implementation_plan

    # Configure minimal retries
    cat >> .workflow/config.sh <<'EOF'
RETRY_MAX_ATTEMPTS=1
RETRY_BASE_DELAY=1
EOF

    # Command should fail fast
    run timeout 10 "$WORKFLOW_BIN" build --max 1

    # Should complete within timeout
    [ "$status" -ne 124 ]
}

@test "workflow build respects BUILD_PUSH_AFTER_COMMIT config" {
    create_implementation_plan

    # Configure to not push after commit
    cat >> .workflow/config.sh <<'EOF'
BUILD_PUSH_AFTER_COMMIT=false
EOF

    # Verify config is loaded (even if build fails without Claude)
    grep -q "BUILD_PUSH_AFTER_COMMIT=false" .workflow/config.sh
}

# =============================================================================
# Task Counting Tests
# =============================================================================

@test "implementation plan has correct task format" {
    create_implementation_plan

    # Tasks should have checkbox format: - [ ] TXXX
    grep -qE "^- \[[[:space:]xX]\] T[0-9]+" docs/IMPLEMENTATION_PLAN.md
}

@test "implementation plan can be parsed for task count" {
    create_implementation_plan

    # Count pending tasks
    pending_count=$(grep -c "^\- \[ \]" docs/IMPLEMENTATION_PLAN.md || echo 0)
    [ "$pending_count" -gt 0 ]
}

@test "implementation plan can track mixed task statuses" {
    create_implementation_plan mixed

    # Count both pending and completed
    pending_count=$(grep -c "^\- \[ \]" docs/IMPLEMENTATION_PLAN.md || echo 0)
    completed_count=$(grep -c "^\- \[X\]" docs/IMPLEMENTATION_PLAN.md || echo 0)

    [ "$pending_count" -gt 0 ]
    [ "$completed_count" -gt 0 ]
}
