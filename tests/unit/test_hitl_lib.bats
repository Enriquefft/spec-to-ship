#!/usr/bin/env bats
# Unit tests for src/lib/hitl.sh

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo

    # Load required libraries
    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # Source dependencies (hitl requires config)
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/config.sh
    source "${LIB_DIR}/config.sh"
    # shellcheck source=src/lib/hitl.sh
    source "${LIB_DIR}/hitl.sh"
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

# =============================================================================
# hitl_is_enabled() tests
# =============================================================================

@test "hitl_is_enabled returns false by default" {
    create_config

    config_load

    run hitl_is_enabled

    [ "$status" -eq 1 ]
}

@test "hitl_is_enabled returns true when enabled in config" {
    create_config HITL_ENABLED=true

    config_load

    run hitl_is_enabled

    [ "$status" -eq 0 ]
}

@test "hitl_is_enabled respects environment variable" {
    create_config

    export WORKFLOW_HITL_ENABLED=true
    config_load

    run hitl_is_enabled

    [ "$status" -eq 0 ]

    unset WORKFLOW_HITL_ENABLED
}

# =============================================================================
# hitl_mode() tests
# =============================================================================

@test "hitl_mode returns default mode" {
    create_config

    config_load

    run hitl_mode

    [ "$status" -eq 0 ]
    [ "$output" = "milestone" ]
}

@test "hitl_mode returns configured mode" {
    create_config HITL_MODE=task

    config_load

    run hitl_mode

    [ "$status" -eq 0 ]
    [ "$output" = "task" ]
}

# =============================================================================
# hitl_should_pause() tests
# =============================================================================

@test "hitl_should_pause returns false when disabled" {
    create_config HITL_ENABLED=false

    config_load

    run hitl_should_pause task

    [ "$status" -eq 1 ]
}

@test "hitl_should_pause with task mode pauses on task trigger" {
    create_config HITL_ENABLED=true HITL_MODE=task

    config_load

    run hitl_should_pause task

    [ "$status" -eq 0 ]
}

@test "hitl_should_pause with task mode does not pause on milestone trigger" {
    create_config HITL_ENABLED=true HITL_MODE=task

    config_load

    run hitl_should_pause milestone

    [ "$status" -eq 1 ]
}

@test "hitl_should_pause with milestone mode pauses on milestone trigger" {
    create_config HITL_ENABLED=true HITL_MODE=milestone

    config_load

    run hitl_should_pause milestone

    [ "$status" -eq 0 ]
}

@test "hitl_should_pause with milestone mode does not pause on task trigger" {
    create_config HITL_ENABLED=true HITL_MODE=milestone

    config_load

    run hitl_should_pause task

    [ "$status" -eq 1 ]
}

@test "hitl_should_pause with uncertain mode pauses on uncertain trigger" {
    create_config HITL_ENABLED=true HITL_MODE=uncertain

    config_load

    run hitl_should_pause uncertain

    [ "$status" -eq 0 ]
}

@test "hitl_should_pause with every:N mode pauses on Nth iteration" {
    create_config HITL_ENABLED=true HITL_MODE=every:3

    config_load

    # Iteration 1 - should not pause
    run hitl_should_pause iteration 1
    [ "$status" -eq 1 ]

    # Iteration 2 - should not pause
    run hitl_should_pause iteration 2
    [ "$status" -eq 1 ]

    # Iteration 3 - should pause (3 % 3 == 0)
    run hitl_should_pause iteration 3
    [ "$status" -eq 0 ]

    # Iteration 6 - should pause (6 % 3 == 0)
    run hitl_should_pause iteration 6
    [ "$status" -eq 0 ]
}

@test "hitl_should_pause with every:1 pauses every iteration" {
    create_config HITL_ENABLED=true HITL_MODE=every:1

    config_load

    for i in 1 2 3 4 5; do
        run hitl_should_pause iteration "$i"
        [ "$status" -eq 0 ]
    done
}

# =============================================================================
# HITL log tests
# =============================================================================

@test "hitl_log creates log file" {
    create_config HITL_ENABLED=true
    config_load

    # Initialize log
    _init_hitl_log

    [ -f "docs/hitl-log.md" ]
}

@test "hitl_log creates docs directory if missing" {
    create_config HITL_ENABLED=true
    config_load

    # Remove docs dir
    rm -rf docs

    # Initialize log
    _init_hitl_log

    [ -d "docs" ]
    [ -f "docs/hitl-log.md" ]
}

@test "hitl_log appends interaction entry" {
    create_config HITL_ENABLED=true
    config_load

    hitl_log "Test question?" "Test response" "Action taken"

    grep -q "Test question?" docs/hitl-log.md
    grep -q "Test response" docs/hitl-log.md
    grep -q "Action taken" docs/hitl-log.md
}

# =============================================================================
# Mode-specific behavior tests
# =============================================================================

@test "all trigger types with disabled HITL return no-pause" {
    create_config HITL_ENABLED=false

    config_load

    for trigger in task milestone uncertain iteration; do
        run hitl_should_pause "$trigger"
        [ "$status" -eq 1 ]
    done
}

@test "HITL enabled with default mode only pauses on milestone" {
    create_config HITL_ENABLED=true
    # Default mode is milestone

    config_load

    run hitl_should_pause task
    [ "$status" -eq 1 ]

    run hitl_should_pause milestone
    [ "$status" -eq 0 ]

    run hitl_should_pause uncertain
    [ "$status" -eq 1 ]
}
