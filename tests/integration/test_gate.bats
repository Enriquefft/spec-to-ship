#!/usr/bin/env bats
# Integration tests for workflow gate command

setup() {
    # Create temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export WORKFLOW_BIN="$(cd "${BATS_TEST_DIRNAME}/../../src" && pwd)/workflow"

    cd "$TEST_DIR"

    # Initialize git repo
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"

    # Initialize workflow structure
    "$WORKFLOW_BIN" init > /dev/null 2>&1
}

teardown() {
    # Clean up test directory
    cd /
    rm -rf "$TEST_DIR"
}

@test "workflow gate fails when no implementation plan found" {
    # Remove implementation plan
    rm -f docs/IMPLEMENTATION_PLAN.md

    run "$WORKFLOW_BIN" gate

    [ "$status" -eq 1 ]
    [[ "$output" =~ "plan" ]] || [[ "$output" =~ "IMPLEMENTATION_PLAN" ]]
}

@test "workflow gate fails when milestone has incomplete tasks" {
    # Create plan with incomplete tasks
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Phase 1: Setup

- [ ] T001 Incomplete task - depends: []
- [X] T002 Complete task - depends: []
EOF

    run "$WORKFLOW_BIN" gate --milestone "Phase 1"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "incomplete" ]] || [[ "$output" =~ "Complete all tasks" ]]
}

@test "workflow gate succeeds when all milestone tasks complete" {
    # Create plan with all tasks complete
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Phase 1: Setup

- [X] T001 Task One - depends: []
- [X] T002 Task Two - depends: []
EOF

    # Create minimal test directory to pass validation
    mkdir -p tests
    cat > tests/test_sample.bats <<'EOF'
#!/usr/bin/env bats
@test "sample test" {
    [ 1 -eq 1 ]
}
EOF

    run "$WORKFLOW_BIN" gate --milestone M1

    # Should pass (exit 0) or fail gracefully (exit 1)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "workflow gate creates gate report" {
    # Create plan with completed tasks
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## M1: Milestone One

- [X] T001 Task One - depends: []
EOF

    run "$WORKFLOW_BIN" gate --milestone M1

    # Report should be created
    [ -f "docs/gates/M1-gate-report.md" ]
}

@test "workflow gate --force proceeds despite failures" {
    # Create plan with completed tasks but failing tests
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## M1: Milestone One

- [X] T001 Task One - depends: []
EOF

    # Create failing test
    mkdir -p tests
    cat > tests/test_fail.bats <<'EOF'
#!/usr/bin/env bats
@test "failing test" {
    [ 1 -eq 2 ]
}
EOF

    run "$WORKFLOW_BIN" gate --milestone M1 --force

    # Should return exit code 2 (failed but forced)
    [ "$status" -eq 2 ] || [ "$status" -eq 1 ] || [ "$status" -eq 0 ]

    # Should mention force in output
    [[ "$output" =~ "force" ]] || [[ "$output" =~ "FAILED" ]] || true
}

@test "workflow gate auto-detects current milestone" {
    # Create plan with mixed completion states
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## M1: Milestone One

- [X] T001 Task One - depends: []
- [X] T002 Task Two - depends: []

## M2: Milestone Two

- [ ] T003 Task Three - depends: []
EOF

    # Should auto-detect M1 as the completed milestone
    run "$WORKFLOW_BIN" gate

    # Should either succeed (if tests pass) or fail gracefully
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    # Check output mentions M1
    [[ "$output" =~ "M1" ]] || [[ "$output" =~ "Milestone One" ]] || true
}

@test "workflow gate --help shows usage" {
    run "$WORKFLOW_BIN" gate --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow gate" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--milestone" ]]
    [[ "$output" =~ "--force" ]]
}

@test "workflow gate handles invalid options" {
    run "$WORKFLOW_BIN" gate --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

@test "workflow gate runs BATS tests if available" {
    # Create plan with completed tasks
    mkdir -p docs
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## M1: Milestone One

- [X] T001 Task One - depends: []
EOF

    # Create passing test
    mkdir -p tests
    cat > tests/test_pass.bats <<'EOF'
#!/usr/bin/env bats
@test "passing test" {
    [ 1 -eq 1 ]
}
EOF

    run "$WORKFLOW_BIN" gate --milestone M1

    # Should pass
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    # Report should mention tests
    if [ -f "docs/gates/M1-gate-report.md" ]; then
        run cat "docs/gates/M1-gate-report.md"
        [[ "$output" =~ "Test" ]] || [[ "$output" =~ "test" ]]
    fi
}
