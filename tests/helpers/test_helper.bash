#!/usr/bin/env bash
# tests/helpers/test_helper.bash - Common test utilities and fixtures
#
# Inspired by ralph-claude-code's test helper approach.
# Provides isolated test environments and fixture creation without requiring LLM.

# =============================================================================
# Environment Setup
# =============================================================================

# Get the absolute path to the project root
export PROJECT_ROOT
PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

# Path to the workflow binary
export WORKFLOW_BIN="${PROJECT_ROOT}/src/workflow"

# Path to lib directory for unit tests
export LIB_DIR="${PROJECT_ROOT}/src/lib"

# Suppress verbose output during tests
export VERBOSE=false

# =============================================================================
# Test Directory Management
# =============================================================================

# setup_test_dir() - Create isolated temporary test directory
# Sets up TEST_DIR and changes to it
setup_test_dir() {
    export TEST_DIR
    TEST_DIR="$(mktemp -d)"
    export HOME="$TEST_DIR"  # Isolate home directory
    cd "$TEST_DIR" || exit 1
}

# setup_git_repo() - Initialize a git repo in TEST_DIR
setup_git_repo() {
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
}

# setup_workflow() - Initialize workflow structure in TEST_DIR
setup_workflow() {
    "$WORKFLOW_BIN" init > /dev/null 2>&1
}

# teardown_test_dir() - Clean up test directory
teardown_test_dir() {
    cd /
    rm -rf "$TEST_DIR"
}

# =============================================================================
# Fixture Creators
# =============================================================================

# create_prd() - Create a sample PRD.md file
# Usage: create_prd [content]
create_prd() {
    local content="${1:-}"
    mkdir -p "$TEST_DIR/docs"

    if [[ -n "$content" ]]; then
        echo "$content" > "$TEST_DIR/docs/PRD.md"
    else
        cat > "$TEST_DIR/docs/PRD.md" <<'EOF'
# Product Requirements Document

## Overview
A test project for workflow testing.

## Goals
- Test the workflow functionality
- Validate CLI behavior

## Requirements
- Feature A: Description
- Feature B: Description
EOF
    fi
}

# create_prd_structured() - Create a sample PRD_STRUCTURED.md file
create_prd_structured() {
    mkdir -p "$TEST_DIR/docs"
    cat > "$TEST_DIR/docs/PRD_STRUCTURED.md" <<'EOF'
# Structured Product Requirements Document

## Audiences
- End users
- Administrators

## Jobs To Be Done
- Complete workflow tasks efficiently

## Activities

### Activity 1: User Login
**Priority**: High

**Acceptance Criteria**:
- [ ] User can enter credentials
- [ ] System validates input
- [ ] User receives confirmation

### Activity 2: Data Export
**Priority**: Medium

**Acceptance Criteria**:
- [ ] User can select export format
- [ ] System generates file
- [ ] User can download result
EOF
}

# create_spec() - Create a sample spec file
# Usage: create_spec [filename] [content]
create_spec() {
    local filename="${1:-test-feature.md}"
    local content="${2:-}"
    mkdir -p "$TEST_DIR/specs"

    if [[ -n "$content" ]]; then
        echo "$content" > "$TEST_DIR/specs/$filename"
    else
        cat > "$TEST_DIR/specs/$filename" <<'EOF'
# Feature Specification: Test Feature

## User Stories

### Story 1: Basic Operation

As a user,
I want to perform an action,
So that I achieve a result.

**Acceptance Criteria**:
- [ ] Action can be initiated
- [ ] System responds appropriately
- [ ] Result is displayed

## Functional Requirements

- **FR-001**: System SHALL accept user input
- **FR-002**: System SHALL validate input
- **FR-003**: System SHALL produce output

## Data Models

### Entity
- `id` (UUID): Unique identifier
- `name` (string): Entity name
- `created_at` (timestamp): Creation time
EOF
    fi
}

# create_architecture() - Create a sample ARCHITECTURE.md file
create_architecture() {
    mkdir -p "$TEST_DIR/docs"
    cat > "$TEST_DIR/docs/ARCHITECTURE.md" <<'EOF'
# System Architecture Document

## Component Map

### Core Service
- Handles main business logic
- Manages state

### API Layer
- REST endpoints
- Authentication

## Interface Contracts

### POST /api/action
- Request: { data: string }
- Response: { result: string, status: number }

## Data Models

### User
- `id` (UUID): User identifier
- `email` (string): Email address

## Conventions

- File naming: kebab-case
- Function naming: camelCase
- Constants: UPPER_SNAKE_CASE
EOF
}

# create_implementation_plan() - Create a sample IMPLEMENTATION_PLAN.md file
# Usage: create_implementation_plan [variant]
# Variants: default, with_deps, all_done, mixed
create_implementation_plan() {
    local variant="${1:-default}"
    mkdir -p "$TEST_DIR/docs"

    case "$variant" in
        with_deps)
            cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

- [ ] T001 Setup project structure - depends: []
- [ ] T002 Configure database - depends: T001
- [ ] T003 Create models - depends: T002

## Milestone 2: Features

- [ ] T004 Implement API - depends: T003
- [ ] T005 Add authentication - depends: T004
EOF
            ;;
        all_done)
            cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

- [X] T001 Setup project structure - depends: []
- [X] T002 Configure database - depends: T001

## Milestone 2: Features

- [X] T003 Implement API - depends: T002
EOF
            ;;
        mixed)
            cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

- [X] T001 Setup project structure - depends: []
- [X] T002 Configure database - depends: T001
- [ ] T003 Create models - depends: T002

## Milestone 2: Features

- [ ] T004 Implement API - depends: T003
- [ ] T005 Add authentication - depends: T004
EOF
            ;;
        *)
            cat > "$TEST_DIR/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

## Milestone 1: Foundation

- [ ] T001 Setup project structure - depends: []
- [ ] T002 Configure database - depends: []

## Milestone 2: Features

- [ ] T003 Implement API - depends: []
EOF
            ;;
    esac
}

# create_config() - Create a workflow config file
# Usage: create_config [key=value ...]
create_config() {
    mkdir -p "$TEST_DIR/.workflow"

    # Start with defaults
    cat > "$TEST_DIR/.workflow/config.sh" <<'EOF'
# Workflow Configuration

# Model Settings
MODEL_CLARIFY=opus
MODEL_SPECS=sonnet
MODEL_ARCH=opus
MODEL_PLAN=opus
MODEL_BUILD_PRIMARY=opus
MODEL_BUILD_SECONDARY=sonnet
MODEL_GATE=sonnet
MODEL_FEEDBACK=haiku

# HITL Settings
HITL_ENABLED=false
HITL_MODE=milestone

# Build Settings
BUILD_MAX_ITERATIONS=0
BUILD_BACKPRESSURE_TESTS=true
BUILD_BACKPRESSURE_TYPECHECK=false
BUILD_BACKPRESSURE_LINT=true

# Retry Settings
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_DELAY=2
EOF

    # Override with any provided key=value pairs
    for arg in "$@"; do
        local key="${arg%%=*}"
        local value="${arg#*=}"
        echo "${key}=${value}" >> "$TEST_DIR/.workflow/config.sh"
    done
}

# =============================================================================
# Assertion Helpers
# =============================================================================

# assert_file_exists() - Assert that a file exists
assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Expected file to exist: $file" >&2
        return 1
    fi
}

# assert_dir_exists() - Assert that a directory exists
assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Expected directory to exist: $dir" >&2
        return 1
    fi
}

# assert_file_contains() - Assert that a file contains a string
assert_file_contains() {
    local file="$1"
    local pattern="$2"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "Expected file '$file' to contain: $pattern" >&2
        return 1
    fi
}

# assert_file_not_contains() - Assert that a file does not contain a string
assert_file_not_contains() {
    local file="$1"
    local pattern="$2"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "Expected file '$file' to NOT contain: $pattern" >&2
        return 1
    fi
}

# assert_output_contains() - Assert that output contains a string
# Use with: run command; assert_output_contains "expected"
assert_output_contains() {
    local pattern="$1"
    if [[ ! "$output" =~ $pattern ]]; then
        echo "Expected output to contain: $pattern" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# assert_status_success() - Assert command succeeded (exit code 0)
assert_status_success() {
    if [[ "$status" -ne 0 ]]; then
        echo "Expected success (exit 0), got exit $status" >&2
        echo "Output: $output" >&2
        return 1
    fi
}

# assert_status_failure() - Assert command failed (exit code != 0)
assert_status_failure() {
    if [[ "$status" -eq 0 ]]; then
        echo "Expected failure (exit != 0), got success" >&2
        echo "Output: $output" >&2
        return 1
    fi
}

# =============================================================================
# Library Loading Helpers (for unit tests)
# =============================================================================

# load_lib() - Load a library file for unit testing
# Usage: load_lib common
load_lib() {
    local lib_name="$1"
    local lib_file="${LIB_DIR}/${lib_name}.sh"

    if [[ ! -f "$lib_file" ]]; then
        echo "Library not found: $lib_file" >&2
        return 1
    fi

    # Set up minimal environment for library
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # shellcheck source=/dev/null
    source "$lib_file"
}

# =============================================================================
# Utility Functions
# =============================================================================

# count_files() - Count files matching pattern in directory
count_files() {
    local dir="$1"
    local pattern="${2:-*}"
    find "$dir" -name "$pattern" -type f 2>/dev/null | wc -l
}

# get_file_content() - Get file content (for assertions)
get_file_content() {
    local file="$1"
    cat "$file" 2>/dev/null
}
