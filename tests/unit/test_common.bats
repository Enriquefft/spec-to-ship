#!/usr/bin/env bats
# Unit tests for src/lib/common.sh

# Load library
load_lib() {
    export LIB_DIR="$(cd "${BATS_TEST_DIRNAME}/../../src/lib" && pwd)"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
}

setup() {
    load_lib
}

teardown() {
    rm -f "$LOG_FILE"
}

@test "log_info writes to stderr" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[INFO]" ]]
    [[ "$output" =~ "test message" ]]
}

@test "log_warn writes to stderr" {
    run log_warn "warning message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[WARN]" ]]
    [[ "$output" =~ "warning message" ]]
}

@test "log_error writes to stderr" {
    run log_error "error message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[ERROR]" ]]
    [[ "$output" =~ "error message" ]]
}

@test "log_debug writes when VERBOSE=true" {
    export VERBOSE=true
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "[DEBUG]" ]]
    [[ "$output" =~ "debug message" ]]
}

@test "log_debug silent when VERBOSE=false" {
    export VERBOSE=false
    run log_debug "debug message"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "require_command succeeds for existing command" {
    run require_command "bash"
    [ "$status" -eq 0 ]
}

@test "require_command fails for missing command" {
    run require_command "nonexistent_command_12345"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required command not found" ]]
}

@test "ensure_dir creates directory" {
    local test_dir="/tmp/workflow_test_dir_$$"
    run ensure_dir "$test_dir"
    [ "$status" -eq 0 ]
    [ -d "$test_dir" ]
    rmdir "$test_dir"
}

@test "ensure_dir succeeds for existing directory" {
    local test_dir="/tmp"
    run ensure_dir "$test_dir"
    [ "$status" -eq 0 ]
}

@test "require_file succeeds for existing file" {
    local test_file="/tmp/workflow_test_file_$$"
    touch "$test_file"
    run require_file "$test_file"
    [ "$status" -eq 0 ]
    rm "$test_file"
}

@test "require_file fails for missing file" {
    run require_file "/nonexistent/file/12345"
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Required file not found" ]]
}
