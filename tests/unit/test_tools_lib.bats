#!/usr/bin/env bats
# Unit tests for src/lib/tools.sh permission handling (no LLM calls)

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir
    setup_git_repo

    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/config.sh
    source "${LIB_DIR}/config.sh"
    # shellcheck source=src/lib/interaction.sh
    source "${LIB_DIR}/interaction.sh"
    # shellcheck source=src/lib/tools.sh
    source "${LIB_DIR}/tools.sh"
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

@test "agent_tool_write_file fails gracefully on permission denied without HITL" {
    create_config HITL_ENABLED=false
    config_load

    mkdir locked
    chmod 555 locked  # remove write permission

    run agent_tool_write_file "locked/file.txt" "data"

    assert_status_failure
    assert_output_contains "Permission denied"
}

@test "agent_tool_write_file respects HITL and allows skip without hanging" {
    create_config HITL_ENABLED=true HITL_MODE=task
    config_load

    mkdir locked
    chmod 555 locked

    run agent_tool_write_file "locked/file.txt" "data" <<<"3"

    assert_status_failure
    assert_output_contains "Permission denied"
}

@test "agent_tool_run_command surfaces permission errors without retries when HITL disabled" {
    create_config HITL_ENABLED=false
    config_load

    mkdir locked
    chmod 555 locked

    run agent_tool_run_command "touch locked/out.txt"

    assert_status_failure
    assert_output_contains "Permission denied"
}
