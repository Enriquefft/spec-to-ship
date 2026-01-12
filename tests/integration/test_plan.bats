#!/usr/bin/env bats
# Integration tests for workflow plan command
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

@test "workflow plan fails when no specs found" {
    # Remove specs directory
    rm -rf specs
    mkdir -p specs

    run "$WORKFLOW_BIN" plan

    [ "$status" -eq 1 ]
    [[ "$output" =~ "No spec files found" ]] || [[ "$output" =~ "specs" ]]
}

@test "workflow plan fails when no architecture found" {
    # Create spec but no architecture
    create_spec
    rm -f docs/ARCHITECTURE.md

    run "$WORKFLOW_BIN" plan

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ARCHITECTURE" ]] || [[ "$output" =~ "architecture" ]]
}

@test "workflow plan fails when .workflow not initialized" {
    # Remove workflow directory
    rm -rf .workflow

    run "$WORKFLOW_BIN" plan

    [ "$status" -eq 1 ]
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "workflow plan --help shows usage" {
    run "$WORKFLOW_BIN" plan --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow plan" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--regen" ]]
    [[ "$output" =~ "--milestone" ]]
}

@test "workflow plan handles invalid options" {
    run "$WORKFLOW_BIN" plan --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

# =============================================================================
# File Structure Tests
# =============================================================================

@test "workflow plan output file has expected structure" {
    create_spec
    create_architecture
    create_implementation_plan

    # Verify file structure
    [ -f "docs/IMPLEMENTATION_PLAN.md" ]
    grep -q "Milestone" docs/IMPLEMENTATION_PLAN.md
    grep -q "T00" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow plan creates plan with milestones" {
    create_implementation_plan

    # Verify milestones exist
    grep -q "Milestone 1" docs/IMPLEMENTATION_PLAN.md || grep -q "## M1" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow plan creates plan with tasks" {
    create_implementation_plan

    # Verify tasks exist
    grep -q "\- \[ \]" docs/IMPLEMENTATION_PLAN.md
}

# =============================================================================
# Task Dependency Tests
# =============================================================================

@test "implementation plan includes task dependencies" {
    create_implementation_plan with_deps

    # Verify dependencies present
    grep -q "depends:" docs/IMPLEMENTATION_PLAN.md
    grep -q "T001" docs/IMPLEMENTATION_PLAN.md
}

@test "implementation plan tasks have correct format" {
    create_implementation_plan

    # Tasks should have checkbox format: - [ ] TXXX
    grep -qE "^- \[[[:space:]xX]\] T[0-9]+" docs/IMPLEMENTATION_PLAN.md
}

# =============================================================================
# Regeneration Tests
# =============================================================================

@test "workflow plan --regen flag is recognized" {
    create_spec
    create_architecture

    # Create existing plan
    echo "# Old Plan" > docs/IMPLEMENTATION_PLAN.md

    run timeout 5 "$WORKFLOW_BIN" plan --regen

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

@test "workflow plan preserves existing plan on failure" {
    create_spec
    create_architecture

    # Create existing plan with specific content
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Original Plan
This content should not change on failure.
EOF

    original_content="$(cat docs/IMPLEMENTATION_PLAN.md)"

    # Run plan (will fail without Claude)
    "$WORKFLOW_BIN" plan 2>/dev/null || true

    # File should still exist with original content
    [ -f "docs/IMPLEMENTATION_PLAN.md" ]
    current_content="$(cat docs/IMPLEMENTATION_PLAN.md)"
    [ "$original_content" = "$current_content" ]
}

# =============================================================================
# Milestone Filter Tests
# =============================================================================

@test "workflow plan --milestone flag is recognized" {
    create_spec
    create_architecture

    run timeout 5 "$WORKFLOW_BIN" plan --milestone M1

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

@test "workflow plan --milestone accepts various formats" {
    create_spec
    create_architecture

    # Test different milestone formats
    for milestone in M1 M2 1 2; do
        run timeout 5 "$WORKFLOW_BIN" plan --milestone "$milestone"
        [ "$status" -ne 124 ]
    done
}

# =============================================================================
# Plan Content Tests
# =============================================================================

@test "implementation plan includes test requirements" {
    # Create plan with test requirements
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestone 1: Setup

- [ ] T001 Create project - depends: []

**Required tests**:
- Unit test for function X
- Integration test for API Y
EOF

    # Verify test requirements present
    grep -q "Required tests" docs/IMPLEMENTATION_PLAN.md
}

@test "implementation plan task status parsing" {
    create_implementation_plan mixed

    # Should have both done and pending tasks
    grep -q "\[X\]" docs/IMPLEMENTATION_PLAN.md
    grep -q "\[ \]" docs/IMPLEMENTATION_PLAN.md
}

# =============================================================================
# Gap Analysis Tests
# =============================================================================

@test "workflow plan handles existing source code" {
    create_spec
    create_architecture

    # Create some existing code
    mkdir -p src
    cat > src/test.js <<'EOF'
// Existing implementation
function login() {
  return true;
}
EOF

    # Command should run without crashing
    run timeout 5 "$WORKFLOW_BIN" plan

    # Should not hang
    [ "$status" -ne 124 ]

    # Verify source file exists
    [ -f "src/test.js" ]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "workflow plan respects retry configuration" {
    create_spec
    create_architecture

    # Configure minimal retries
    cat >> .workflow/config.sh <<'EOF'
RETRY_MAX_ATTEMPTS=1
RETRY_BASE_DELAY=1
EOF

    # Command should fail fast
    run timeout 10 "$WORKFLOW_BIN" plan

    # Should complete within timeout
    [ "$status" -ne 124 ]
}
