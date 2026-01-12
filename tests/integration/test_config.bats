#!/usr/bin/env bats
# Integration tests for workflow config command

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

# Test: Show full configuration
@test "config shows full configuration by default" {
  run "$WORKFLOW_BIN" config

  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuration file:"* ]]
  [[ "$output" == *"Model Settings"* ]]
  [[ "$output" == *"HITL Settings"* ]]
  [[ "$output" == *"Build Settings"* ]]
  [[ "$output" == *"MODEL_CLARIFY="* ]]
  [[ "$output" == *"HITL_ENABLED="* ]]
}

# Test: Get specific configuration value
@test "config --get retrieves specific value" {
  run "$WORKFLOW_BIN" config --get MODEL_BUILD_PRIMARY

  [ "$status" -eq 0 ]
  [[ "$output" == "opus" ]] || [[ "$output" == "sonnet" ]] || [[ "$output" == "haiku" ]]
}

# Test: Get non-existent key fails
@test "config --get fails for non-existent key" {
  run "$WORKFLOW_BIN" config --get INVALID_KEY

  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

# Test: Set configuration value
@test "config --set updates configuration value" {
  # Set a new value
  run "$WORKFLOW_BIN" config --set MODEL_BUILD_PRIMARY=sonnet

  [ "$status" -eq 0 ]
  [[ "$output" == *"Updated configuration"* ]] || [[ "$output" == *"Added configuration"* ]]

  # Verify the value was set
  run "$WORKFLOW_BIN" config --get MODEL_BUILD_PRIMARY

  [ "$status" -eq 0 ]
  [[ "$output" == "sonnet" ]]
}

# Test: Set invalid key fails
@test "config --set fails for invalid key" {
  run "$WORKFLOW_BIN" config --set INVALID_KEY=value

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid"* ]]
}

# Test: Set with invalid format fails
@test "config --set fails with invalid format" {
  run "$WORKFLOW_BIN" config --set INVALID_FORMAT

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid format"* ]] || [[ "$output" == *"key=value"* ]]
}

# Test: Set boolean value
@test "config --set works with boolean values" {
  run "$WORKFLOW_BIN" config --set HITL_ENABLED=true

  [ "$status" -eq 0 ]

  # Verify
  run "$WORKFLOW_BIN" config --get HITL_ENABLED

  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

# Test: Set integer value
@test "config --set works with integer values" {
  run "$WORKFLOW_BIN" config --set BUILD_MAX_ITERATIONS=10

  [ "$status" -eq 0 ]

  # Verify
  run "$WORKFLOW_BIN" config --get BUILD_MAX_ITERATIONS

  [ "$status" -eq 0 ]
  [[ "$output" == "10" ]]
}

# Test: Help message
@test "config --help shows help message" {
  run "$WORKFLOW_BIN" config --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"workflow config"* ]]
  [[ "$output" == *"--edit"* ]]
  [[ "$output" == *"--get"* ]]
  [[ "$output" == *"--set"* ]]
}

# Test: Config file is created if missing
@test "config creates default config file if missing" {
  # Remove config file
  rm -f "$TEST_DIR/.workflow/config.sh"

  run "$WORKFLOW_BIN" config

  [ "$status" -eq 0 ]
  [[ "$output" == *"Configuration file"* ]]

  # Verify config file exists
  [ -f "$TEST_DIR/.workflow/config.sh" ]
}

# Test: Config file contains defaults
@test "config creates file with default values" {
  # Remove config file
  rm -f "$TEST_DIR/.workflow/config.sh"

  # Trigger config creation
  "$WORKFLOW_BIN" config > /dev/null

  # Check file contents
  [ -f "$TEST_DIR/.workflow/config.sh" ]
  grep -q "MODEL_CLARIFY=" "$TEST_DIR/.workflow/config.sh"
  grep -q "HITL_ENABLED=" "$TEST_DIR/.workflow/config.sh"
  grep -q "BUILD_MAX_ITERATIONS=" "$TEST_DIR/.workflow/config.sh"
}

# Test: Multiple set operations
@test "config --set can be called multiple times" {
  "$WORKFLOW_BIN" config --set MODEL_BUILD_PRIMARY=sonnet
  "$WORKFLOW_BIN" config --set HITL_ENABLED=true
  "$WORKFLOW_BIN" config --set BUILD_MAX_ITERATIONS=5

  # Verify all values
  run "$WORKFLOW_BIN" config --get MODEL_BUILD_PRIMARY
  [ "$status" -eq 0 ]
  [[ "$output" == "sonnet" ]]

  run "$WORKFLOW_BIN" config --get HITL_ENABLED
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]

  run "$WORKFLOW_BIN" config --get BUILD_MAX_ITERATIONS
  [ "$status" -eq 0 ]
  [[ "$output" == "5" ]]
}

# Test: Error handling for missing --get argument
@test "config --get fails without argument" {
  run "$WORKFLOW_BIN" config --get

  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

# Test: Error handling for missing --set argument
@test "config --set fails without argument" {
  run "$WORKFLOW_BIN" config --set

  [ "$status" -eq 1 ]
  [[ "$output" == *"requires an argument"* ]]
}

# Test: Unknown option fails
@test "config fails with unknown option" {
  run "$WORKFLOW_BIN" config --invalid-option

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

# Test: Set HITL mode
@test "config --set works with HITL mode values" {
  run "$WORKFLOW_BIN" config --set HITL_MODE=task

  [ "$status" -eq 0 ]

  run "$WORKFLOW_BIN" config --get HITL_MODE
  [ "$status" -eq 0 ]
  [[ "$output" == "task" ]]
}
