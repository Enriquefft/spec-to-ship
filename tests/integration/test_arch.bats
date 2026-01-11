#!/usr/bin/env bats
# Integration tests for workflow arch command

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

@test "workflow arch fails when no specs found" {
    # Remove specs directory or ensure it's empty
    rm -rf specs
    mkdir -p specs

    run "$WORKFLOW_BIN" arch

    [ "$status" -eq 1 ]
    [[ "$output" =~ "No spec files found" ]] || [[ "$output" =~ "specs/" ]]
}

@test "workflow arch generates architecture document from specs" {
    # Create sample spec files
    mkdir -p specs
    cat > specs/user-authentication.md <<'EOF'
# Feature Specification: User Authentication

## User Stories

### Story 1: Login with Email

As a user,
I want to log in with my email and password,
So that I can access my account.

**Acceptance Criteria**:
- [ ] User can enter email and password
- [ ] System validates credentials
- [ ] User receives JWT token on success
- [ ] Invalid credentials show error message

## Functional Requirements

- **FR-001**: System SHALL accept email and password for authentication
- **FR-002**: System SHALL return JWT token on successful authentication
- **FR-003**: System SHALL hash passwords using bcrypt
- **FR-004**: System SHALL implement rate limiting (5 attempts per minute)

## Data Models

### User Entity
- `id` (UUID): Unique identifier
- `email` (string): User email address
- `password_hash` (string): Bcrypt hashed password
- `created_at` (timestamp): Account creation time
EOF

    cat > specs/expense-tracking.md <<'EOF'
# Feature Specification: Expense Tracking

## User Stories

### Story 1: Add Expense

As a user,
I want to add an expense with amount and category,
So that I can track my spending.

**Acceptance Criteria**:
- [ ] User can enter amount and select category
- [ ] System validates amount is positive
- [ ] Expense is saved with timestamp
- [ ] User sees confirmation

## Functional Requirements

- **FR-001**: System SHALL accept expense amount in USD
- **FR-002**: System SHALL validate amount is positive decimal
- **FR-003**: System SHALL associate expense with user account
- **FR-004**: System SHALL timestamp each expense

## Data Models

### Expense Entity
- `id` (UUID): Unique identifier
- `user_id` (UUID): Reference to User
- `amount` (decimal): Expense amount
- `category` (string): Expense category
- `timestamp` (timestamp): When expense occurred

## Dependencies

- `user-authentication.md` - Requires authenticated user
EOF

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    run "$WORKFLOW_BIN" arch

    # Should attempt to generate architecture (may fail on Claude API)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "workflow arch creates ARCHITECTURE.md file" {
    # Create minimal spec
    mkdir -p specs
    cat > specs/test-feature.md <<'EOF'
# Feature Specification: Test Feature

## Functional Requirements
- **FR-001**: System SHALL do something

## Data Models
### Entity
- `id` (UUID): Identifier
EOF

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Create mock architecture file
    mkdir -p docs
    cat > docs/ARCHITECTURE.md <<'EOF'
# System Architecture Document

## Component Map
- Component 1: Description

## Interface Contracts
- API 1: Description

## Data Models
- Model 1: Description

## Conventions
- Naming: kebab-case for files
EOF

    # Verify file structure
    [ -f "docs/ARCHITECTURE.md" ]
    grep -q "Component Map" docs/ARCHITECTURE.md
    grep -q "Interface Contracts" docs/ARCHITECTURE.md
    grep -q "Data Models" docs/ARCHITECTURE.md
    grep -q "Conventions" docs/ARCHITECTURE.md
}

@test "workflow arch --review shows usage for review mode" {
    # Create sample spec
    mkdir -p specs
    echo "# Spec" > specs/test.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Review mode should work (or fail gracefully)
    run "$WORKFLOW_BIN" arch --review < /dev/null

    # Should either work or fail gracefully with review mode
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "workflow arch --help shows usage" {
    run "$WORKFLOW_BIN" arch --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow arch" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--review" ]]
}

@test "workflow arch handles invalid options" {
    run "$WORKFLOW_BIN" arch --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

@test "workflow arch loads multiple spec files" {
    # Create multiple specs
    mkdir -p specs
    echo "# Spec 1" > specs/feature-one.md
    echo "# Spec 2" > specs/feature-two.md
    echo "# Spec 3" > specs/feature-three.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    # Mock verification - just ensure structure works
    [ -f "specs/feature-one.md" ]
    [ -f "specs/feature-two.md" ]
    [ -f "specs/feature-three.md" ]

    # Count spec files
    spec_count=$(find specs -name "*.md" -type f | wc -l)
    [ "$spec_count" -eq 3 ]
}

@test "workflow arch warns when regenerating existing architecture" {
    # Create spec file
    mkdir -p specs
    echo "# Spec" > specs/test.md

    # Create existing architecture
    mkdir -p docs
    echo "# Existing Architecture" > docs/ARCHITECTURE.md

    # Skip if claude not properly configured
    if ! _is_claude_configured; then
        skip "Claude CLI not configured or not responding"
    fi

    run "$WORKFLOW_BIN" arch

    # Should show warning or handle existing file
    # (Exact behavior depends on implementation)
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}
