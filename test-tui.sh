#!/bin/bash
# test-tui.sh - Test the new TUI system

set -euo pipefail

# Source the TUI bridge
source src/lib/tui_bridge.sh

# Initialize TUI
export WORKFLOW_TUI=true
tui_init || {
    echo "TUI initialization failed, falling back to bash mode"
    WORKFLOW_TUI=false
}

# Test messages
echo "Testing TUI message system..."

if tui_is_enabled; then
    # Phase start
    tui_phase_start "test" "Task 1" "Task 2" "Task 3"
    sleep 1
    
    # LLM interaction
    tui_llm_start "test" "claude" "claude-opus-4" "task_123"
    sleep 1
    
    tui_llm_prompt "task_123" "This is a test prompt to demonstrate the TUI system. It should show up in the LLM stream panel." 25
    sleep 1
    
    tui_llm_response "task_123" "This is a test response from the LLM. It demonstrates that messages are flowing through the bridge correctly." 30 1500
    sleep 1
    
    tui_llm_complete "task_123" 1500 "true"
    sleep 1
    
    # Task updates
    tui_task_start "task_1" "Process test data"
    sleep 1
    
    tui_task_update "task_1" "in_progress" 0.5 "Processing test data..."
    sleep 1
    
    tui_task_complete "task_1" "true" 2000
    sleep 1
    
    # Phase complete
    tui_phase_complete "test" "true" 5000
    
    echo ""
    echo "Test complete! The TUI should have shown:"
    echo "- Phase 'test' starting"
    echo "- LLM interaction with prompt/response"
    echo "- Task 1 updates and completion"
    echo "- Phase completion"
    echo ""
    echo "Press Ctrl+C to exit"
    
    # Keep running
    while true; do
        sleep 5
        tui_log "info" "Still running test..." "test-tui"
    done
else
    echo "TUI not enabled. Try: export WORKFLOW_TUI=true"
fi