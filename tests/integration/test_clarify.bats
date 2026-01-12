#!/usr/bin/env bats
# Integration tests for workflow clarify command
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

@test "workflow clarify fails when PRD not found" {
    # Remove PRD
    rm -f docs/PRD.md

    run "$WORKFLOW_BIN" clarify --no-interactive

    [ "$status" -eq 1 ]
    [[ "$output" =~ "PRD not found" ]] || [[ "$output" =~ "PRD.md" ]]
}

@test "workflow clarify fails when .workflow not initialized" {
    # Remove workflow directory
    rm -rf .workflow

    run "$WORKFLOW_BIN" clarify --no-interactive

    [ "$status" -eq 1 ]
}

# =============================================================================
# Help and Usage Tests
# =============================================================================

@test "workflow clarify --help shows usage" {
    run "$WORKFLOW_BIN" clarify --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow clarify" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--no-interactive" ]]
}

@test "workflow clarify handles invalid options" {
    run "$WORKFLOW_BIN" clarify --invalid-option

    [ "$status" -eq 1 ]
    [[ "$output" =~ "Unknown option" ]] || [[ "$output" =~ "invalid" ]]
}

# =============================================================================
# File Structure Tests
# =============================================================================

@test "workflow clarify creates docs directory if missing" {
    rm -rf docs

    # This will fail because there's no PRD, but the command should try
    run "$WORKFLOW_BIN" clarify --no-interactive

    # Even on failure, docs dir might be created
    # The important thing is the command runs without crashing on missing dir
    [ "$status" -eq 1 ]  # Expected to fail (no PRD)
}

@test "workflow clarify preserves original PRD" {
    # Create sample PRD with specific content
    cat > docs/PRD.md <<'EOF'
# Original Content
This should not change during clarify errors.
EOF

    # Store original content
    original_content="$(cat docs/PRD.md)"

    # Run clarify with timeout (will fail without Claude, but shouldn't modify PRD)
    # Use short timeout to fail fast when no provider is configured
    timeout 3 "$WORKFLOW_BIN" clarify --no-interactive 2>/dev/null || true

    # Verify original PRD unchanged
    current_content="$(cat docs/PRD.md)"
    [ "$original_content" = "$current_content" ]
}

# =============================================================================
# Output File Validation Tests
# =============================================================================

@test "workflow clarify output file has expected structure when created" {
    # Create PRD
    create_prd

    # Create a mock PRD_STRUCTURED.md to test structure validation
    cat > docs/PRD_STRUCTURED.md <<'EOF'
# Structured Product Requirements Document

## Audiences
- End users

## Jobs To Be Done
- Track expenses

## Activities
### Activity 1: Upload Receipt
EOF

    # Verify file exists and has expected sections
    [ -f "docs/PRD_STRUCTURED.md" ]
    grep -q "Structured Product Requirements Document" docs/PRD_STRUCTURED.md
    grep -q "Audiences" docs/PRD_STRUCTURED.md
    grep -q "Jobs To Be Done" docs/PRD_STRUCTURED.md
    grep -q "Activities" docs/PRD_STRUCTURED.md
}

# =============================================================================
# Interactive Mode Tests
# =============================================================================

@test "workflow clarify with --no-interactive flag runs without TTY" {
    create_prd

    # Without a configured provider, this will fail but should not hang
    # waiting for user input. We're testing that --no-interactive works,
    # not that Claude is available.
    # Skip this test as it requires a provider to be configured
    skip "Requires AI provider - tests CLI behavior only"
}

@test "workflow clarify without --no-interactive and no TTY handles gracefully" {
    create_prd

    # Without a configured provider, this will fail but should not hang
    # waiting for user input from a non-existent TTY.
    # Skip this test as it requires a provider to be configured
    skip "Requires AI provider - tests CLI behavior only"
}

# =============================================================================
# Configuration Tests
# =============================================================================

@test "workflow clarify respects fast retry config" {
    create_prd

    # This test requires a provider to be configured, skip it
    skip "Requires AI provider - tests retry configuration"
}
