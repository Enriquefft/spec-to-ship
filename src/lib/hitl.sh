#!/usr/bin/env bash
# src/lib/hitl.sh - Compatibility shim (DEPRECATED)
#
# This file has been merged into interaction.sh for better maintainability.
# All HITL functions are now available through interaction.sh.
#
# This shim exists for backward compatibility. Update your code to source
# interaction.sh directly instead.
#
# Migration:
#   - source "$LIB_DIR/hitl.sh"
#   + source "$LIB_DIR/interaction.sh"
#
# All function names remain the same:
#   - hitl_is_enabled, hitl_mode, hitl_should_pause
#   - hitl_prompt, hitl_prompt_yn, hitl_confirm_action
#   - hitl_log, hitl_show_context, hitl_select_option
#   - hitl_review_changes

: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"

# Source the unified interaction library which contains all HITL functions
# shellcheck source=src/lib/interaction.sh
source "${LIB_DIR}/interaction.sh"

# Log deprecation warning once per session
if [[ -z "${_HITL_DEPRECATION_WARNED:-}" ]]; then
    _HITL_DEPRECATION_WARNED=true
    # Only warn in verbose mode to avoid noise
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        log_debug "hitl.sh is deprecated. Source interaction.sh directly instead."
    fi
fi
