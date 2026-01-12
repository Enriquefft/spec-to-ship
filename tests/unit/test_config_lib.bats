#!/usr/bin/env bats
# Unit tests for src/lib/config.sh

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo

    # Load required libraries
    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # Source common first (config depends on it)
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/config.sh
    source "${LIB_DIR}/config.sh"
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

# =============================================================================
# config_load() tests
# =============================================================================

@test "config_load loads default values when no config file exists" {
    # Ensure no config file
    rm -rf .workflow

    # Call directly (not with run) to keep CONFIG in current shell
    config_load

    # Check defaults are set
    [ "${CONFIG[MODEL_CLARIFY]}" = "opus" ]
    [ "${CONFIG[HITL_ENABLED]}" = "false" ]
    [ "${CONFIG[BUILD_MAX_ITERATIONS]}" = "0" ]
}

@test "config_load reads values from config file" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
MODEL_CLARIFY=sonnet
HITL_ENABLED=true
BUILD_MAX_ITERATIONS=10
EOF

    config_load

    [ "${CONFIG[MODEL_CLARIFY]}" = "sonnet" ]
    [ "${CONFIG[HITL_ENABLED]}" = "true" ]
    [ "${CONFIG[BUILD_MAX_ITERATIONS]}" = "10" ]
}

@test "config_load handles quoted values" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
MODEL_CLARIFY="opus"
HITL_MODE="milestone"
EOF

    config_load

    [ "${CONFIG[MODEL_CLARIFY]}" = "opus" ]
    [ "${CONFIG[HITL_MODE]}" = "milestone" ]
}

@test "config_load ignores comments" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
# This is a comment
MODEL_CLARIFY=sonnet  # inline comment
# Another comment
HITL_ENABLED=true
EOF

    config_load

    [ "${CONFIG[MODEL_CLARIFY]}" = "sonnet" ]
    [ "${CONFIG[HITL_ENABLED]}" = "true" ]
}

@test "config_load overrides with environment variables" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
MODEL_CLARIFY=opus
EOF

    export WORKFLOW_MODEL_CLARIFY=haiku

    config_load

    [ "${CONFIG[MODEL_CLARIFY]}" = "haiku" ]

    unset WORKFLOW_MODEL_CLARIFY
}

# =============================================================================
# config_get() tests
# =============================================================================

@test "config_get returns value for existing key" {
    mkdir -p .workflow
    echo "MODEL_CLARIFY=sonnet" > .workflow/config.sh
    config_load

    run config_get MODEL_CLARIFY

    [ "$status" -eq 0 ]
    [ "$output" = "sonnet" ]
}

@test "config_get fails for non-existent key" {
    config_load

    run config_get NONEXISTENT_KEY

    [ "$status" -eq 1 ]
}

# =============================================================================
# config_set() tests
# =============================================================================

@test "config_set updates existing key" {
    config_load

    # config_set runs in subshell with run, so check return status separately
    run config_set MODEL_CLARIFY haiku
    [ "$status" -eq 0 ]

    # For value check, call set directly in current shell
    config_set MODEL_CLARIFY haiku
    [ "${CONFIG[MODEL_CLARIFY]}" = "haiku" ]
}

@test "config_set fails for invalid key" {
    config_load

    run config_set INVALID_KEY value

    [ "$status" -eq 1 ]
}

# =============================================================================
# config_validate() tests
# =============================================================================

@test "config_validate succeeds with valid configuration" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
MODEL_CLARIFY=opus
MODEL_SPECS=sonnet
MODEL_ARCH=opus
MODEL_PLAN=opus
MODEL_BUILD_PRIMARY=opus
MODEL_BUILD_SECONDARY=sonnet
MODEL_GATE=sonnet
MODEL_FEEDBACK=haiku
HITL_ENABLED=false
HITL_MODE=milestone
BUILD_MAX_ITERATIONS=5
BUILD_BACKPRESSURE_TESTS=true
BUILD_BACKPRESSURE_TYPECHECK=false
BUILD_BACKPRESSURE_LINT=true
RETRY_MAX_ATTEMPTS=3
RETRY_BASE_DELAY=2
EOF

    config_load

    run config_validate

    [ "$status" -eq 0 ]
}

@test "config_validate fails with invalid model name" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
MODEL_CLARIFY=invalid_model
EOF

    config_load

    run config_validate

    [ "$status" -eq 1 ]
}

@test "config_validate fails with invalid boolean" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
HITL_ENABLED=yes
EOF

    config_load

    run config_validate

    [ "$status" -eq 1 ]
}

@test "config_validate fails with invalid integer" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
BUILD_MAX_ITERATIONS=abc
EOF

    config_load

    run config_validate

    [ "$status" -eq 1 ]
}

@test "config_validate accepts valid HITL modes" {
    mkdir -p .workflow

    for mode in task milestone uncertain; do
        cat > .workflow/config.sh <<EOF
HITL_MODE=$mode
EOF
        config_load
        run config_validate
        [ "$status" -eq 0 ]
    done
}

@test "config_validate accepts every:N HITL mode" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
HITL_MODE=every:5
EOF

    config_load

    run config_validate

    [ "$status" -eq 0 ]
}

@test "config_validate fails with invalid HITL mode" {
    mkdir -p .workflow
    cat > .workflow/config.sh <<'EOF'
HITL_MODE=invalid
EOF

    config_load

    run config_validate

    [ "$status" -eq 1 ]
}

# =============================================================================
# config_validate_no_secrets() tests
# =============================================================================

@test "config_validate_no_secrets passes with normal values" {
    config_load

    run config_validate_no_secrets

    [ "$status" -eq 0 ]
}

@test "config_validate_no_secrets detects API key patterns" {
    config_load
    # Force the value into config in current shell
    CONFIG[SOME_KEY]="sk-abc123def456ghi789jkl012mno345pqr"

    run config_validate_no_secrets

    [ "$status" -eq 1 ]
}

# =============================================================================
# config_model_for_phase() tests
# =============================================================================

@test "config_model_for_phase returns correct model for clarify" {
    mkdir -p .workflow
    echo "MODEL_CLARIFY=haiku" > .workflow/config.sh
    config_load

    run config_model_for_phase clarify

    [ "$status" -eq 0 ]
    [ "$output" = "haiku" ]
}

@test "config_model_for_phase returns correct model for build" {
    mkdir -p .workflow
    echo "MODEL_BUILD_PRIMARY=sonnet" > .workflow/config.sh
    config_load

    run config_model_for_phase build

    [ "$status" -eq 0 ]
    [ "$output" = "sonnet" ]
}

@test "config_model_for_phase fails for unknown phase" {
    config_load

    run config_model_for_phase unknown_phase

    [ "$status" -eq 1 ]
}

@test "config_model_for_phase covers all phases" {
    config_load

    for phase in clarify specs arch plan build gate feedback; do
        run config_model_for_phase "$phase"
        [ "$status" -eq 0 ]
        [ -n "$output" ]
    done
}
