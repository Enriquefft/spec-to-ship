#!/usr/bin/env bats
# Integration tests for workflow status command
# Covers different workflow states per acceptance scenarios

setup() {
  # Create temporary test directory
  export TEST_DIR
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"  # Isolate home directory
  export WORKFLOW_BIN="$(cd "${BATS_TEST_DIRNAME}/../../src" && pwd)/workflow"
  cd "$TEST_DIR" || exit 1

  # Initialize git repo
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Initialize workflow
  "$WORKFLOW_BIN" init
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# Acceptance Scenario 1: Status at Requirements phase
@test "status shows Requirements phase when only PRD exists" {
  # Create PRD file
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase: Requirements"* ]]
  [[ "$output" == *"Status:"* ]]
}

# Acceptance Scenario 2: Status at Architecture phase
@test "status shows Architecture phase when ARCHITECTURE.md exists" {
  # Create PRD and Architecture files
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"
  echo "# Architecture" > "$TEST_DIR/docs/ARCHITECTURE.md"

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase: Architecture"* ]]
  [[ "$output" == *"Status:"* ]]
}

# Acceptance Scenario 3: Status at Planning/Execution phase with milestone progress
@test "status shows Execution phase with milestone progress when plan exists" {
  # Create full workflow state with plan
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"
  echo "# Architecture" > "$TEST_DIR/docs/ARCHITECTURE.md"

  # Create implementation plan with milestone
  cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

### Tasks

- [ ] Task 1: Setup infrastructure
  status: pending
- [x] Task 2: Create database
  status: done
- [ ] Task 3: Build API
  status: pending

## Milestone 2: Features

### Tasks

- [ ] Task 4: User auth
  status: pending
EOF

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"Phase:"* ]]
  [[ "$output" == *"Milestone:"* ]]
  [[ "$output" == *"(1/3) tasks"* ]]  # 1 done out of 3 in M1
}

# Test: HITL enabled status
@test "status shows HITL enabled when configured" {
  # Create PRD
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"

  # Enable HITL in config
  echo 'HITL_ENABLED=true' >> "$TEST_DIR/.workflow/config.sh"
  echo 'HITL_MODE="task"' >> "$TEST_DIR/.workflow/config.sh"

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"HITL: enabled"* ]]
}

# Test: HITL disabled status
@test "status shows HITL disabled when not configured" {
  # Create PRD
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"HITL: disabled"* ]]
}

# Test: No workflow initialized
@test "status handles missing workflow files gracefully" {
  # Remove .workflow directory
  rm -rf "$TEST_DIR/.workflow"

  run "$WORKFLOW_BIN" status

  # Should still succeed but show minimal state
  [ "$status" -eq 0 ]
}

# Test: Task counting accuracy
@test "status accurately counts completed vs total tasks" {
  mkdir -p "$TEST_DIR/docs"
  echo "# PRD" > "$TEST_DIR/docs/PRD.md"

  # Create plan with various task states
  cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Setup

### Tasks

- [x] Task 1: Init
  status: done
- [x] Task 2: Config
  status: done
- [ ] Task 3: Deploy
  status: pending
- [ ] Task 4: Test
  status: blocked

## Milestone 2: Build

### Tasks

- [ ] Task 5: Feature A
  status: pending
EOF

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  # Should show 2/4 complete for Milestone 1
  [[ "$output" == *"(2/4) tasks"* ]]
}

# Test: Multiple milestones - shows current milestone
@test "status shows current (incomplete) milestone" {
  mkdir -p "$TEST_DIR/docs"

  # Create plan with completed M1 and incomplete M2
  cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

### Tasks

- [x] Task 1: Setup
  status: done
- [x] Task 2: Config
  status: done

## Milestone 2: Features

### Tasks

- [x] Task 3: Auth
  status: done
- [ ] Task 4: Dashboard
  status: pending
EOF

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  # Should show Milestone 2 (the incomplete one)
  [[ "$output" == *"Milestone: 2"* ]]
  [[ "$output" == *"(1/2) tasks"* ]]
}

# Test: All milestones complete
@test "status shows completion when all tasks done" {
  mkdir -p "$TEST_DIR/docs"

  cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: MVP

### Tasks

- [x] Task 1: Done
  status: done
- [x] Task 2: Complete
  status: done
EOF

  run "$WORKFLOW_BIN" status

  [ "$status" -eq 0 ]
  [[ "$output" == *"(2/2) tasks"* ]]
}
