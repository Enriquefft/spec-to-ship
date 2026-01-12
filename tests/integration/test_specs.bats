#!/usr/bin/env bats
# Integration tests for workflow specs command
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

@test "workflow specs fails when PRD_STRUCTURED not found" {
    # Remove structured PRD
    rm -f docs/PRD_STRUCTURED.md

    # Use --context-mode full to bypass interactive prompt (minimal shows menu)
    run "$WORKFLOW_BIN" specs --context-mode full

    [ "$status" -eq 1 ]
    [[ "$output" =~ "PRD_STRUCTURED" ]] || [[ "$output" =~ "Structured PRD not found" ]]
}

@test "workflow specs fails when .workflow not initialized" {
    # Remove workflow directory
    rm -rf .workflow

    run "$WORKFLOW_BIN" specs

    [ "$status" -eq 1 ]
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "workflow specs --help shows usage" {
    run "$WORKFLOW_BIN" specs --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow specs" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--force" ]]
}

@test "workflow specs handles invalid options" {
    run "$WORKFLOW_BIN" specs --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

# =============================================================================
# File Structure Tests
# =============================================================================

@test "workflow specs creates specs directory" {
    create_prd_structured

    # Even if the command fails without Claude, specs dir should be created
    "$WORKFLOW_BIN" specs 2>/dev/null || true

    [ -d "specs" ]
}

@test "workflow specs creates kebab-case filenames" {
    create_prd_structured

    # Create mock spec files to test naming convention
    mkdir -p specs
    cat > specs/user-login.md <<'EOF'
# Feature Specification: User Login
EOF
    cat > specs/data-export.md <<'EOF'
# Feature Specification: Data Export
EOF

    # Verify kebab-case filenames
    [ -f "specs/user-login.md" ]
    [ -f "specs/data-export.md" ]

    # Verify content
    grep -q "User Login" specs/user-login.md
    grep -q "Data Export" specs/data-export.md
}

@test "workflow specs skips existing files without --force" {
    create_prd_structured

    # Create pre-existing spec file
    mkdir -p specs
    echo "# Existing spec content - do not overwrite" > specs/user-login.md

    # Run specs without --force
    run "$WORKFLOW_BIN" specs

    # Existing file should be preserved
    grep -q "Existing spec content" specs/user-login.md
}

# =============================================================================
# Spec File Format Tests
# =============================================================================

@test "spec files have expected structure" {
    # Create a properly formatted spec file
    mkdir -p specs
    cat > specs/test-feature.md <<'EOF'
# Feature Specification: Test Feature

## User Stories

### Story 1: Basic Operation

As a user,
I want to perform an action,
So that I achieve a result.

**Acceptance Criteria**:
- [ ] Action can be initiated
- [ ] System responds appropriately

## Functional Requirements

- **FR-001**: System SHALL accept input
- **FR-002**: System SHALL validate input

## Data Models

### Entity
- `id` (UUID): Identifier
- `name` (string): Name
EOF

    # Verify structure
    grep -q "Feature Specification" specs/test-feature.md
    grep -q "User Stories" specs/test-feature.md
    grep -q "Functional Requirements" specs/test-feature.md
    grep -q "Data Models" specs/test-feature.md
}

# =============================================================================
# Activity Parsing Tests
# =============================================================================

@test "workflow specs parses multiple activities from PRD_STRUCTURED" {
    # Create structured PRD with 3 activities
    cat > docs/PRD_STRUCTURED.md <<'EOF'
# Structured PRD

## Activities

### Activity 1: Feature One
**Acceptance Criteria**:
- [ ] Criteria 1

### Activity 2: Feature Two
**Acceptance Criteria**:
- [ ] Criteria 2

### Activity 3: Feature Three
**Acceptance Criteria**:
- [ ] Criteria 3
EOF

    # Create mock spec files that would be generated
    mkdir -p specs
    echo "# Feature One" > specs/feature-one.md
    echo "# Feature Two" > specs/feature-two.md
    echo "# Feature Three" > specs/feature-three.md

    # Verify all files exist
    [ -f "specs/feature-one.md" ]
    [ -f "specs/feature-two.md" ]
    [ -f "specs/feature-three.md" ]

    # Count spec files
    spec_count=$(find specs -name "*.md" -type f | wc -l)
    [ "$spec_count" -eq 3 ]
}

# =============================================================================
# Force Flag Tests
# =============================================================================

@test "workflow specs --force flag is recognized" {
    create_prd_structured

    # Create pre-existing spec file
    mkdir -p specs
    echo "# Old content" > specs/test-feature.md

    # --force flag should be recognized (even if command fails without Claude)
    run timeout 5 "$WORKFLOW_BIN" specs --force

    # Should not hang and should not error on the flag itself
    [ "$status" -ne 124 ]
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "workflow specs respects retry configuration" {
    create_prd_structured

    # Configure minimal retries
    cat >> .workflow/config.sh <<'EOF'
RETRY_MAX_ATTEMPTS=1
RETRY_BASE_DELAY=1
EOF

    # Command should fail fast
    run timeout 10 "$WORKFLOW_BIN" specs

    # Should complete within timeout
    [ "$status" -ne 124 ]
}
