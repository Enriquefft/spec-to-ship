#!/usr/bin/env bash
# src/lib/adaptive.sh - Adaptive model selection for agent loop
#
# Provides step classification, capability resolution, and escalation
# state management for token-efficient model selection during build.

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Configuration (read from environment with defaults at call time)
# ==============================================================================

# _adaptive_get_config(name, default) - Get config value from environment
# These are not readonly to allow test overrides
_adaptive_get_config() {
    local name="$1"
    local default="$2"
    echo "${!name:-$default}"
}

# Escalation state (per-task)
declare -gA _ADAPTIVE_FAILURE_COUNT 2>/dev/null || declare -A _ADAPTIVE_FAILURE_COUNT
declare -gA _ADAPTIVE_CURRENT_TIER 2>/dev/null || declare -A _ADAPTIVE_CURRENT_TIER

# ==============================================================================
# Step Classification
# ==============================================================================

# adaptive_classify_step(step_number, response_content) - Classify agent step type
# Args:
#   step_number: Current step number (1-based)
#   response: Model response content (optional, for detecting action type)
# Returns: initial|tool|reasoning|final (stdout)
adaptive_classify_step() {
    local step_number="$1"
    local response="${2:-}"

    # Step 1 is always initial understanding
    if [[ "$step_number" -eq 1 ]]; then
        echo "initial"
        return 0
    fi

    # Check for final answer
    if [[ "$response" =~ \<final_answer\> ]]; then
        echo "final"
        return 0
    fi

    # Check for tool execution
    if [[ "$response" =~ \<tool_code\> ]]; then
        echo "tool"
        return 0
    fi

    # Check for user question (still requires reasoning capability)
    if [[ "$response" =~ \<ask_user\> ]]; then
        echo "reasoning"
        return 0
    fi

    # Default to reasoning for thinking/planning steps
    echo "reasoning"
}

# adaptive_get_step_capability(step_type, task_complexity) - Get capability for step
# Args:
#   step_type: One of initial|tool|reasoning|final
#   task_complexity: Task's base complexity (high|medium|low)
# Returns: high|medium|low (stdout)
adaptive_get_step_capability() {
    local step_type="$1"
    local task_complexity="${2:-high}"

    # Validate task_complexity
    case "$task_complexity" in
        high|medium|low) ;;
        *) task_complexity="high" ;;
    esac

    case "$step_type" in
        initial|reasoning|final)
            # Match task complexity for understanding and synthesis
            echo "$task_complexity"
            ;;
        tool)
            # Tool execution can often use lower tier (if enabled)
            local downgrade
            downgrade="$(_adaptive_get_config ADAPTIVE_TOOL_STEP_DOWNGRADE true)"
            if [[ "$downgrade" == "true" ]]; then
                case "$task_complexity" in
                    high)   echo "medium" ;;
                    medium) echo "low" ;;
                    low)    echo "low" ;;
                esac
            else
                echo "$task_complexity"
            fi
            ;;
        *)
            # Unknown step type, use task complexity
            echo "$task_complexity"
            ;;
    esac
}

# ==============================================================================
# Escalation State Machine
# ==============================================================================

# adaptive_init_task(task_id, initial_complexity) - Initialize escalation state for task
# Args:
#   task_id: Task identifier (e.g., T001)
#   initial_complexity: Starting complexity tier (high|medium|low)
adaptive_init_task() {
    local task_id="$1"
    local default_complexity
    default_complexity="$(_adaptive_get_config ADAPTIVE_DEFAULT_COMPLEXITY high)"
    local initial_complexity="${2:-$default_complexity}"

    # Validate complexity
    case "$initial_complexity" in
        high|medium|low) ;;
        *) initial_complexity="$default_complexity" ;;
    esac

    _ADAPTIVE_FAILURE_COUNT["$task_id"]=0
    _ADAPTIVE_CURRENT_TIER["$task_id"]="$initial_complexity"

    log_debug "Adaptive: initialized task $task_id with complexity $initial_complexity"
}

# adaptive_record_failure(task_id) - Record a step failure for escalation tracking
# Args:
#   task_id: Task identifier
# Returns:
#   0 - Should retry with same tier
#   1 - Escalated to higher tier
#   2 - Already at max tier (high), cannot escalate further
adaptive_record_failure() {
    local task_id="$1"
    local current_count="${_ADAPTIVE_FAILURE_COUNT[$task_id]:-0}"
    local current_tier="${_ADAPTIVE_CURRENT_TIER[$task_id]:-high}"

    current_count=$((current_count + 1))
    _ADAPTIVE_FAILURE_COUNT["$task_id"]=$current_count

    log_debug "Adaptive: task $task_id failure count: $current_count (tier: $current_tier)"

    # Check if should escalate
    local retry_limit
    retry_limit="$(_adaptive_get_config ADAPTIVE_RETRY_BEFORE_ESCALATE 2)"
    if [[ $current_count -ge $retry_limit ]]; then
        local new_tier
        new_tier=$(_adaptive_escalate_tier "$current_tier")

        if [[ "$new_tier" == "$current_tier" ]]; then
            # Already at highest tier
            log_warn "Adaptive: task $task_id at max tier (high), no escalation possible"
            return 2
        fi

        _ADAPTIVE_CURRENT_TIER["$task_id"]="$new_tier"
        _ADAPTIVE_FAILURE_COUNT["$task_id"]=0  # Reset failure count after escalation

        log_info "Adaptive: escalating task $task_id from $current_tier to $new_tier"
        return 1
    fi

    return 0
}

# _adaptive_escalate_tier(current_tier) - Get next higher tier
# Returns: high|medium (capped at high)
_adaptive_escalate_tier() {
    local current="$1"

    case "$current" in
        low)    echo "medium" ;;
        medium) echo "high" ;;
        high)   echo "high" ;;  # Already at max
        *)      echo "high" ;;
    esac
}

# adaptive_record_success(task_id) - Record successful step (resets failure count)
# Args:
#   task_id: Task identifier
adaptive_record_success() {
    local task_id="$1"
    _ADAPTIVE_FAILURE_COUNT["$task_id"]=0
    log_debug "Adaptive: task $task_id step succeeded, reset failure count"
}

# adaptive_get_current_tier(task_id) - Get current effective tier for task
# Args:
#   task_id: Task identifier
# Returns: high|medium|low (stdout)
adaptive_get_current_tier() {
    local task_id="$1"
    echo "${_ADAPTIVE_CURRENT_TIER[$task_id]:-high}"
}

# adaptive_cleanup_task(task_id) - Clean up escalation state after task completes
# Args:
#   task_id: Task identifier
adaptive_cleanup_task() {
    local task_id="$1"
    unset "_ADAPTIVE_FAILURE_COUNT[$task_id]"
    unset "_ADAPTIVE_CURRENT_TIER[$task_id]"
    log_debug "Adaptive: cleaned up state for task $task_id"
}

# ==============================================================================
# History Compression
# ==============================================================================

# adaptive_should_compress_history(step_count) - Check if history needs compression
# Args:
#   step_count: Current step number
# Returns: 0 if should compress, 1 otherwise
adaptive_should_compress_history() {
    local step_count="$1"
    local threshold
    threshold="$(_adaptive_get_config ADAPTIVE_HISTORY_COMPRESS_THRESHOLD 10)"
    [[ $step_count -ge $threshold ]]
}

# adaptive_compress_history(history_file) - Compress older history entries
# Keeps: System prompt, task, last N steps verbatim; summarizes middle steps
# Args:
#   history_file: Path to agent history file
adaptive_compress_history() {
    local history_file="$1"

    if [[ ! -f "$history_file" ]]; then
        log_warn "Adaptive: history file not found: $history_file"
        return 1
    fi

    # Count assistant steps
    local step_count
    step_count=$(grep -c "^## Assistant" "$history_file" 2>/dev/null || echo 0)

    local keep_recent
    keep_recent="$(_adaptive_get_config ADAPTIVE_HISTORY_KEEP_RECENT 3)"
    if [[ $step_count -le $keep_recent ]]; then
        # Not enough steps to compress
        log_debug "Adaptive: only $step_count steps, skipping compression"
        return 0
    fi

    local temp_file
    temp_file="$(mktemp)"

    # Extract header sections (system prompt, task, context)
    # Stop at first "## Assistant" line
    awk '/^## Assistant/ { exit } { print }' "$history_file" > "$temp_file"

    # Add compression marker
    {
        echo ""
        echo "# INTERACTION HISTORY (Compressed)"
        echo ""
        echo "## Summary of Steps 1-$((step_count - keep_recent))"
        echo ""
        echo "Previous steps compressed for token efficiency. Key actions:"
        echo ""
    } >> "$temp_file"

    # Extract tool actions from older steps (compressed summary)
    local keep_from=$((step_count - keep_recent + 1))
    awk -v keep="$keep_from" '
        BEGIN { step=0; in_assistant=0; in_tool=0 }
        /^## Assistant \(Step/ {
            step++
            in_assistant=1
            step_captured[step] = 0
            if (step < keep) {
                # Summarize this step
                print "- Step " step ":"
            }
            next
        }
        /^## User\/System/ {
            in_assistant=0
            next
        }
        step < keep && in_assistant {
            # Extract tool calls from older steps
            if (/<tool_code>/) { in_tool=1; next }
            if (/<\/tool_code>/) { in_tool=0; next }
            if (in_tool && /agent_tool_/) {
                gsub(/^[[:space:]]+/, "")
                print "  - " $0
                step_captured[step] = 1
            }
            if (/<final_answer>/) { print "  - Provided final answer"; step_captured[step] = 1 }
            if (/<ask_user>/) { print "  - Asked user question"; step_captured[step] = 1 }
            # Capture first non-empty reasoning line as fallback context
            if (!step_captured[step] && !in_tool && /[A-Za-z]/) {
                gsub(/^[[:space:]]+/, "")
                # Truncate to 100 chars for brevity
                if (length($0) > 100) {
                    print "  - " substr($0, 1, 100) "..."
                } else {
                    print "  - " $0
                }
                step_captured[step] = 1
            }
        }
        step >= keep {
            # Keep recent steps verbatim
            print
        }
    ' "$history_file" >> "$temp_file"

    # Replace original
    mv "$temp_file" "$history_file"
    log_info "Adaptive: compressed history, kept last $keep_recent steps verbatim"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# adaptive_is_enabled() - Check if adaptive model selection is enabled
# Returns: 0 if enabled, 1 if disabled
adaptive_is_enabled() {
    local enabled="${ADAPTIVE_ENABLED:-true}"
    [[ "$enabled" == "true" ]]
}

# adaptive_get_stats(task_id) - Get stats for debugging
# Returns: JSON-like string with current state
adaptive_get_stats() {
    local task_id="$1"
    local tier="${_ADAPTIVE_CURRENT_TIER[$task_id]:-unset}"
    local failures="${_ADAPTIVE_FAILURE_COUNT[$task_id]:-0}"
    echo "task=$task_id tier=$tier failures=$failures"
}
