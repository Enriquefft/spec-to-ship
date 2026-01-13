#!/usr/bin/env bash
# src/lib/agent.sh - The "Polyfill" Agent Loop
# Turns any text-in/text-out model into an agent with tools and smart interaction.

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/provider.sh
source "${LIB_DIR}/provider.sh"
# shellcheck source=src/lib/tools.sh
source "${LIB_DIR}/tools.sh"
# shellcheck source=src/lib/interaction.sh
source "${LIB_DIR}/interaction.sh"
# shellcheck source=src/lib/adaptive.sh
source "${LIB_DIR}/adaptive.sh"
# shellcheck source=src/lib/plan.sh
source "${LIB_DIR}/plan.sh"

# ==============================================================================
# Constants
# ==============================================================================
AGENT_MAX_STEPS=15
AGENT_HISTORY_FILE=""

# ==============================================================================
# Main Loop
# ==============================================================================

# agent_run_task(task_id, task_description, context_files...)
# Main entry point to start an agentic task.
# Args:
#   task_id: Task identifier (e.g., T001) for adaptive model selection
#   task: Task description
#   context_files: Optional context files to include
agent_run_task() {
    local task_id="$1"
    local task="$2"
    shift 2
    local context_files=("$@")

    # 1. Setup Workspace
    AGENT_HISTORY_FILE="$(mktemp)"
    # Store task_id in global for cleanup trap (local vars not accessible in trap context)
    _AGENT_CURRENT_TASK_ID="$task_id"

    # Cleanup function for trap
    _agent_cleanup() {
        adaptive_cleanup_task "${_AGENT_CURRENT_TASK_ID:-}" 2>/dev/null || true
        rm -f "$AGENT_HISTORY_FILE" 2>/dev/null || true
        unset _AGENT_CURRENT_TASK_ID
    }
    trap '_agent_cleanup' EXIT

    # 2. Get task complexity and initialize adaptive state
    local task_complexity
    if adaptive_is_enabled; then
        task_complexity="$(plan_get_task_complexity "$task_id" 2>/dev/null)" || task_complexity="high"
        adaptive_init_task "$task_id" "$task_complexity"
        log_info "Agent started on task: ${task:0:50}... (complexity: $task_complexity)"
    else
        task_complexity="high"
        log_info "Agent started on task: ${task:0:50}... (adaptive disabled)"
    fi

    # 3. Construct Initial System Prompt
    local system_prompt_file="${LIB_DIR}/../prompts/system_agent.md"
    if [[ ! -f "$system_prompt_file" ]]; then
        log_error "System prompt not found: $system_prompt_file"
        return 1
    fi

    # Initialize History with System Prompt + Task
    {
        cat "$system_prompt_file"
        echo ""
        echo "# CURRENT TASK"
        echo "$task"
        echo ""
        echo "# CONTEXT"
        for f in "${context_files[@]}"; do
            if [[ -f "$f" ]]; then
                echo "## File: $f"
                cat "$f"
                echo ""
            fi
        done
        echo ""
        echo "# INTERACTION HISTORY"
    } > "$AGENT_HISTORY_FILE"

    # 4. The ReAct Loop with Adaptive Model Selection
    local step=0
    local done=false
    local prev_response=""

    while [[ $step -lt $AGENT_MAX_STEPS && "$done" == "false" ]]; do
        # Check for build interruption (Ctrl+C)
        if [[ "${BUILD_INTERRUPTED:-false}" == "true" ]]; then
            log_warn "Agent loop interrupted by user"
            return 130
        fi

        ((step++))

        # A. History Compression (for token efficiency)
        if adaptive_is_enabled && adaptive_should_compress_history "$step"; then
            adaptive_compress_history "$AGENT_HISTORY_FILE"
        fi

        # B. Determine step capability (adaptive model selection)
        local step_type step_capability effective_tier
        if adaptive_is_enabled; then
            step_type=$(adaptive_classify_step "$step" "$prev_response")
            effective_tier=$(adaptive_get_current_tier "$task_id")
            step_capability=$(adaptive_get_step_capability "$step_type" "$effective_tier")
            log_debug "Agent Step $step/$AGENT_MAX_STEPS: type=$step_type, capability=$step_capability"
        else
            step_capability="high"
            log_debug "Agent Step $step/$AGENT_MAX_STEPS"
        fi

        # C. Invoke Provider with appropriate capability
        local response
        local invoke_status=0

        if adaptive_is_enabled; then
            response=$(provider_invoke_with_capability "$step_capability" "$AGENT_HISTORY_FILE") || invoke_status=$?
        else
            response=$(provider_invoke_for_phase "build" "$AGENT_HISTORY_FILE") || invoke_status=$?
        fi

        # D. Handle interrupt signal (Ctrl+C)
        if [[ $invoke_status -eq 130 ]]; then
            log_warn "Provider interrupted by signal (exit code 130)"
            return 130
        fi

        # E. Handle invocation failures with escalation
        if [[ $invoke_status -ne 0 ]] || [[ -z "$response" ]]; then
            log_warn "Agent step $step failed (capability: $step_capability)"

            if adaptive_is_enabled; then
                local escalation_result
                adaptive_record_failure "$task_id"
                escalation_result=$?

                case $escalation_result in
                    0)  # Retry same tier
                        log_info "Retrying step with same capability ($step_capability)..."
                        ((step--))  # Don't count this as a step
                        continue
                        ;;
                    1)  # Escalated - retry with new tier
                        local new_tier
                        new_tier=$(adaptive_get_current_tier "$task_id")
                        log_info "Escalated to $new_tier capability, retrying..."
                        ((step--))  # Don't count this as a step
                        continue
                        ;;
                    2)  # At max tier, still failing
                        log_error "Step failed at maximum capability (high)"
                        # Continue anyway - maybe model can recover
                        ;;
                esac
            fi
        fi

        # F. Record success for adaptive tracking
        if adaptive_is_enabled && [[ -n "$response" ]]; then
            adaptive_record_success "$task_id"
        fi

        # Store response for next iteration's step classification
        prev_response="$response"

        # Log the raw response for debugging
        log_debug "Raw Agent Response: ${response:0:100}..."

        # Append Agent Response to History
        echo "" >> "$AGENT_HISTORY_FILE"
        echo "## Assistant (Step $step)" >> "$AGENT_HISTORY_FILE"
        echo "$response" >> "$AGENT_HISTORY_FILE"

        # G. Parse and Execute
        # We look for ONE action per turn (Tool or Ask or Finish)

        # Check for <final_answer>
        if echo "$response" | grep -q "<final_answer>"; then
            log_info "Agent completed task."
            done=true
            break
        fi

        # Check for <ask_user>
        if echo "$response" | grep -q "<ask_user>"; then
            _agent_handle_question "$response"
            continue
        fi

        # Check for <tool_code>
        if echo "$response" | grep -q "<tool_code>"; then
            _agent_handle_tool "$response"
            continue
        fi

        # Fallback: If no tags found, treat as thought/comment
        log_warn "Agent produced no executable tags. Continuing..."
    done

    if [[ "$done" == "true" ]]; then
        return 0
    else
        log_error "Agent failed to complete task within $AGENT_MAX_STEPS steps."
        return 1
    fi
}

# ==============================================================================
# Handlers
# ==============================================================================

_agent_handle_tool() {
    local response="$1"
    
    # Extract content inside <tool_code>...</tool_code>
    # Using sed to handle multi-line content safely
    local tool_block
    tool_block=$(echo "$response" | sed -n '/<tool_code>/,/<\/tool_code>/p' | sed '1d;$d')

    if [[ -z "$tool_block" ]]; then
        _agent_record_result "Error: Empty tool block"
        return
    fi

    log_info "Agent is using a tool..."
    
    # Parse the command name (first word)
    local tool_name
    tool_name=$(echo "$tool_block" | head -n1 | awk '{print $1}')
    
    # Security Check: Only allow mapped tools from tools.sh
    # We parse the arguments differently depending on the tool.
    # For now, we assume the tool_block is a BASH SCRIPT FRAGMENT that calls the tool functions directly.
    # OR we parse the specific format defined in system_agent.md.
    # Let's enforce the format: "tool_name arg1 arg2..."
    
    # Execute and capture output
    local output
    output=$(eval "$tool_block" 2>&1)
    local exit_code=$?

    # Record result
    _agent_record_result "Tool Output (Exit Code: $exit_code):" "$output"
}

_agent_handle_question() {
    local response="$1"
    
    # Extract XML fields
    # Note: Primitive parsing. In production, use a real parser.
    local question
    question=$(echo "$response" | grep -oP '(?<=<question>).*?(?=</question>)' || echo "Question parse error")
    
    local rec_id
    rec_id=$(echo "$response" | grep -oP '(?<=<recommendation_id>).*?(?=</recommendation_id>)')
    
    local rec_reason
    rec_reason=$(echo "$response" | grep -oP '(?<=<reasoning>).*?(?=</reasoning>)')
    
    # Options need to be parsed into ID|Desc format
    # Assuming <option id="A">Desc</option> lines
    local options_list
    options_list=$(echo "$response" | grep '<option id=' | sed -E 's/.*id="([^\"]+)">(.+)<\/option>/\1|\2/')

    # Call Interaction Library
    local user_answer
    user_answer=$(interaction_present_smart_question "$question" "$rec_id" "$rec_reason" "$options_list")
    
    _agent_record_result "User Answer: $user_answer"
}

_agent_record_result() {
    local header="$1"
    local content="${2:-}"

    # Only write to history file if it's defined and exists
    if [[ -n "$AGENT_HISTORY_FILE" && -w "$AGENT_HISTORY_FILE" ]]; then
        echo "" >> "$AGENT_HISTORY_FILE"
        echo "## User/System" >> "$AGENT_HISTORY_FILE"
        echo "$header" >> "$AGENT_HISTORY_FILE"
        if [[ -n "$content" ]]; then
            echo "
\`\`\`" >> "$AGENT_HISTORY_FILE"
            echo "$content" >> "$AGENT_HISTORY_FILE"
            echo "
\`\`\`" >> "$AGENT_HISTORY_FILE"
        fi
    fi
}
