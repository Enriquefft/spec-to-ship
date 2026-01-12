#!/usr/bin/env bats
# Unit tests for src/lib/provider.sh

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
    # shellcheck source=src/lib/provider.sh
    source "${LIB_DIR}/provider.sh"

    # Ensure no config file exists (start with defaults)
    rm -rf .workflow
}

@test "provider resolution: PROVIDER_DEFAULT takes precedence over phase-specific defaults" {
    # Test with only PROVIDER_DEFAULT set
    export WORKFLOW_PROVIDER_DEFAULT="opencode"
    
    # Reload config to pick up environment variables
    config_load
    
    # All phases should return opencode even though phase-specific defaults exist in CONFIG_DEFAULTS
    [ "$(provider_get_for_phase "clarify")" = "opencode" ]
    [ "$(provider_get_for_phase "specs")" = "opencode" ]
    [ "$(provider_get_for_phase "arch")" = "opencode" ]
    [ "$(provider_get_for_phase "plan")" = "opencode" ]
    [ "$(provider_get_for_phase "build")" = "opencode" ]
    [ "$(provider_get_for_phase "gate")" = "opencode" ]
    [ "$(provider_get_for_phase "feedback")" = "opencode" ]
}

@test "provider resolution: phase-specific override still works when different from default" {
    # Set default provider
    export WORKFLOW_PROVIDER_DEFAULT="opencode"
    # Set a different provider for one phase
    export WORKFLOW_PROVIDER_CLARIFY="claude"
    
    # Reload config to pick up environment variables
    config_load
    
    # Clarify phase should use claude (phase-specific)
    [ "$(provider_get_for_phase "clarify")" = "claude" ]
    
    # Other phases should use opencode (default)
    [ "$(provider_get_for_phase "specs")" = "opencode" ]
    [ "$(provider_get_for_phase "arch")" = "opencode" ]
}

@test "provider resolution: fallback to claude when no provider set" {
    # Unset all provider variables
    unset WORKFLOW_PROVIDER_DEFAULT
    unset WORKFLOW_PROVIDER_CLARIFY
    unset WORKFLOW_PROVIDER_SPECS
    unset WORKFLOW_PROVIDER_ARCH
    unset WORKFLOW_PROVIDER_PLAN
    unset WORKFLOW_PROVIDER_BUILD
    unset WORKFLOW_PROVIDER_GATE
    unset WORKFLOW_PROVIDER_FEEDBACK
    
    # Reload config to pick up environment variables
    config_load
    
    # Should fall back to claude
    [ "$(provider_get_for_phase "clarify")" = "claude" ]
}

@test "provider resolution: phase-specific same as default uses default" {
    # Set default provider
    export WORKFLOW_PROVIDER_DEFAULT="opencode"
    # Set phase-specific to the SAME value
    export WORKFLOW_PROVIDER_CLARIFY="opencode"
    
    # Reload config to pick up environment variables
    config_load
    
    # Should still work but use the default path
    [ "$(provider_get_for_phase "clarify")" = "opencode" ]
}