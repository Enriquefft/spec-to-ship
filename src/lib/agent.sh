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

# ==============================================================================
# Constants
# ==============================================================================
AGENT_MAX_STEPS=15
AGENT_HISTORY_FILE=""

# ==============================================================================
# Main Loop
# ==============================================================================

# agent_run_task(task_description, context_files...)
# Main entry point to start an agentic task.
agent_run_task() {
    local task="$1"
    shift
    local context_files=($@)

    # 1. Setup Workspace
    AGENT_HISTORY_FILE="$(mktemp)"
    trap 'rm -f "$AGENT_HISTORY_FILE"' EXIT
    
    # 2. Construct Initial System Prompt
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

    # 3. The ReAct Loop
    local step=0
    local done=false
    
    log_info "Agent started on task: ${task:0:50}..."

    while [[ $step -lt $AGENT_MAX_STEPS && "$done" == "false" ]]; do
        ((step++))
        log_debug "Agent Step $step/$AGENT_MAX_STEPS"

        # A. Invoke Provider
        # We assume provider_invoke writes result to stdout
        local response
        # Using build phase configuration by default
        response=$(provider_invoke_for_phase "build" "$AGENT_HISTORY_FILE")
        
        # Log the raw response for debugging
        log_debug "Raw Agent Response: ${response:0:100}..."

        # Append Agent Response to History
        echo "" >> "$AGENT_HISTORY_FILE"
        echo "## Assistant (Step $step)" >> "$AGENT_HISTORY_FILE"
        echo "$response" >> "$AGENT_HISTORY_FILE"

        # B. Parse and Execute
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
        # Maybe force a reminder if it loops too long without acting?
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
    local content="$2"

    echo "" >> "$AGENT_HISTORY_FILE"
    echo "## User/System" >> "$AGENT_HISTORY_FILE"
    echo "$header" >> "$AGENT_HISTORY_FILE"
    if [[ -n "$content" ]]; then
        echo "
```" >> "$AGENT_HISTORY_FILE"
        echo "$content" >> "$AGENT_HISTORY_FILE"
        echo "
```" >> "$AGENT_HISTORY_FILE"
    fi
}
