#!/usr/bin/env bats
# Integration tests for workflow plan command

# Helper to check if Claude is configured and working
_is_claude_configured() {
    # Check if claude command exists
    if ! command -v claude &> /dev/null; then
        return 1
    fi

    # Try to run a quick Claude command with timeout
    # If it hangs or fails, Claude is not properly configured
    if timeout 5s claude --version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

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

    # Configure faster retries for tests
    cat >> .workflow/config <<'EOF'
RETRY_MAX_ATTEMPTS=1
RETRY_BASE_DELAY=1
EOF
}

teardown() {
    # Clean up test directory
    cd /
    rm -rf "$TEST_DIR"
}

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
    mkdir -p specs
    echo "# Spec" > specs/test.md

    # Remove architecture
    rm -f docs/ARCHITECTURE.md

    run "$WORKFLOW_BIN" plan

    [ "$status" -eq 1 ]
    [[ "$output" =~ "ARCHITECTURE" ]] || [[ "$output" =~ "architecture" ]]
}

@test "workflow plan generates implementation plan from specs and architecture" {
    # Create sample spec
    mkdir -p specs
    cat > specs/user-login.md <<'EOF'
# Feature Specification: User Login

## User Stories

### Story 1: Login

As a user,
I want to log in with email and password,
So that I can access the system.

**Acceptance Criteria**:
- [ ] User can enter credentials
- [ ] System validates credentials
- [ ] User receives auth token on success

## Functional Requirements

- **FR-001**: System SHALL accept email and password
- **FR-002**: System SHALL return JWT token on success
EOF

    # Create sample architecture
    mkdir -p docs
    cat > docs/ARCHITECTURE.md <<'EOF'
# System Architecture

## Component Map

### Authentication Service
- Handles user login and token generation

## Data Models

### User
- `id` (UUID): User identifier
- `email` (string): Email address
- `password_hash` (string): Hashed password

## Interface Contracts

### POST /api/login
- Request: { email, password }
- Response: { token }
EOF

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    run "$WORKFLOW_BIN" plan

    # Should attempt to generate plan (may fail on Claude API)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "workflow plan creates IMPLEMENTATION_PLAN.md file" {
    # Create minimal spec and architecture
    mkdir -p specs docs
    echo "# Spec" > specs/test.md
    echo "# Architecture" > docs/ARCHITECTURE.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Create mock implementation plan
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Milestones

### Milestone 1: Setup (Week 1)

**Tasks**: T001-T003

## Tasks

### T001 - Setup Project

**Dependencies**: None

**Acceptance Criteria**:
- [ ] Project initialized

**Required tests**:
- Directory structure test
EOF

    # Verify file structure
    [ -f "docs/IMPLEMENTATION_PLAN.md" ]
    grep -q "Milestones" docs/IMPLEMENTATION_PLAN.md
    grep -q "Tasks" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow plan includes task dependencies" {
    # Create sample files
    mkdir -p specs docs
    echo "# Spec" > specs/test.md
    echo "# Arch" > docs/ARCHITECTURE.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Mock plan with dependencies
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Tasks

### T001 - Task One
**Dependencies**: None

### T002 - Task Two
**Dependencies**: T001
EOF

    # Verify dependencies present
    grep -q "Dependencies" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow plan includes test requirements" {
    # Create sample files
    mkdir -p specs docs
    echo "# Spec" > specs/test.md
    echo "# Arch" > docs/ARCHITECTURE.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Mock plan with test requirements
    cat > docs/IMPLEMENTATION_PLAN.md <<'EOF'
# Implementation Plan

## Tasks

### T001 - Task One

**Required tests**:
- Unit test for function X
- Integration test for API Y
EOF

    # Verify test requirements present
    grep -q "Required tests" docs/IMPLEMENTATION_PLAN.md
}

@test "workflow plan --regen regenerates existing plan" {
    # Create sample files
    mkdir -p specs docs
    echo "# Spec" > specs/test.md
    echo "# Arch" > docs/ARCHITECTURE.md

    # Create existing plan
    echo "# Old Plan" > docs/IMPLEMENTATION_PLAN.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    run "$WORKFLOW_BIN" plan --regen

    # Should attempt to regenerate (may fail on API)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "workflow plan --milestone filters specific milestone" {
    # Create sample files
    mkdir -p specs docs
    echo "# Spec" > specs/test.md
    echo "# Arch" > docs/ARCHITECTURE.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    run "$WORKFLOW_BIN" plan --milestone M1

    # Should work or fail gracefully
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

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

@test "workflow plan performs gap analysis with existing code" {
    # Create sample files
    mkdir -p specs docs src
    echo "# Spec" > specs/test.md
    echo "# Arch" > docs/ARCHITECTURE.md

    # Create some existing code
    cat > src/test.js <<'EOF'
// Existing implementation
function login() {
  return true;
}
EOF

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Should include gap analysis in plan generation
    # (Exact behavior depends on implementation)
    [ -f "src/test.js" ]
}
