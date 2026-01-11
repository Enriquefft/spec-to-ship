#!/usr/bin/env bats
# Integration tests for workflow init command

setup() {
    # Create temporary test directory
    export TEST_DIR="$(mktemp -d)"
    export WORKFLOW_BIN="$(cd "${BATS_TEST_DIRNAME}/../../src" && pwd)/workflow"

    cd "$TEST_DIR"

    # Initialize git repo
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
}

teardown() {
    # Clean up test directory
    cd /
    rm -rf "$TEST_DIR"
}

@test "workflow init creates directory structure" {
    run "$WORKFLOW_BIN" init

    [ "$status" -eq 0 ]
    [ -d ".workflow" ]
    [ -d ".workflow/logs" ]
    [ -d "docs" ]
    [ -d "docs/gates" ]
    [ -d "specs" ]
    [ -d "src" ]
    [ -d "src/lib" ]
    [ -d "src/commands" ]
}

@test "workflow init creates configuration file" {
    run "$WORKFLOW_BIN" init

    [ "$status" -eq 0 ]
    [ -f ".workflow/config.sh" ]

    # Check config contains expected values
    grep -q "MODEL_CLARIFY" ".workflow/config.sh"
    grep -q "HITL_ENABLED" ".workflow/config.sh"
}

@test "workflow init creates PRD template" {
    run "$WORKFLOW_BIN" init

    [ "$status" -eq 0 ]
    [ -f "docs/PRD.md" ]

    # Check PRD contains template sections
    grep -q "Product Requirements Document" "docs/PRD.md"
    grep -q "## Overview" "docs/PRD.md"
}

@test "workflow init --from copies existing PRD" {
    # Create source PRD
    local source_prd="${TEST_DIR}/source.md"
    echo "# My Custom PRD" > "$source_prd"

    run "$WORKFLOW_BIN" init --from "$source_prd"

    [ "$status" -eq 0 ]
    [ -f "docs/PRD.md" ]
    grep -q "My Custom PRD" "docs/PRD.md"
}

@test "workflow init --force overwrites existing files" {
    # Initialize once
    "$WORKFLOW_BIN" init
    echo "custom content" > ".workflow/config.sh"

    # Initialize again with force
    run "$WORKFLOW_BIN" init --force

    [ "$status" -eq 0 ]
    [ -f ".workflow/config.sh" ]
    grep -q "MODEL_CLARIFY" ".workflow/config.sh"
    ! grep -q "custom content" ".workflow/config.sh"
}

@test "workflow init updates .gitignore" {
    run "$WORKFLOW_BIN" init

    [ "$status" -eq 0 ]
    [ -f ".gitignore" ]
    grep -q ".workflow/logs" ".gitignore"
}

@test "workflow init --help shows usage" {
    run "$WORKFLOW_BIN" init --help

    [ "$status" -eq 0 ]
    [[ "$output" =~ "workflow init" ]]
    [[ "$output" =~ "USAGE" ]]
    [[ "$output" =~ "--from" ]]
}
