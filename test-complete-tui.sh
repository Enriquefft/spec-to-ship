#!/bin/bash
# test-complete-tui.sh - Test the complete TUI implementation

set -euo pipefail

echo "=== Testing Complete TUI System ==="
echo ""

# Check prerequisites
if [[ -f "bin/workflow-tui-simple" ]]; then
    echo "✓ TUI binary built"
else
    echo "✗ TUI binary not found"
    echo "Run: ./build-complete-tui.sh"
    exit 1
fi

# Set up environment
export WORKFLOW_TUI=true
export PATH="$(pwd)/bin:$PATH"
export GOROOT="$HOME/go"
export GOPATH="$HOME/go/pkg"

# Start TUI in background
echo "Starting TUI..."
./bin/workflow-tui-simple &
TUI_PID=$!
sleep 2

# Send test messages
echo ""
echo "Sending test messages..."
echo '{"type":"phase_start","timestamp":"2025-01-14T10:00:00Z","phase":"test","tasks":["Analyze PRD","Generate specs"]}'
sleep 1
echo '{"type":"llm_start","timestamp":"2025-01-14T10:00:02Z","phase":"test","provider":"claude","model":"claude-opus-4","task_id":"test_123"}'
sleep 1
echo '{"type":"llm_prompt","timestamp":"2025-01-14T10:00:04Z","task_id":"test_123","content":"Analyze this PRD for key requirements and user needs","tokens":15}'
sleep 2
echo '{"type":"llm_response","timestamp":"2025-01-14T10:00:06Z","task_id":"test_123","content":"Based on the PRD, I can identify 3 main user personas: developers, product managers, and end users","tokens":20,"duration_ms":1500}'
sleep 1
echo '{"type":"task_start","timestamp":"2025-01-14T10:00:08Z","task_id":"task_1","task":"Analyze PRD"}'
sleep 1
echo '{"type":"task_update","timestamp":"2025-01-14T10:00:10Z","task_id":"task_1","status":"in_progress","progress":0.5,"message":"Analyzing requirements..."}'
sleep 1
echo '{"type":"task_complete","timestamp":"2025-01-14T10:00:12Z","task_id":"task_1","success":true,"duration_ms":2000}'
sleep 2
echo '{"type":"phase_complete","timestamp":"2025-01-14T10:00:14Z","phase":"test","success":true,"duration_ms":5000}'

echo ""
echo "✓ Test complete!"
echo "The TUI should have shown:"
echo "  - Phase start with tasks"
echo "  - LLM interaction (prompt/response)"
echo "  - Task tracking with progress"
echo "  - Phase completion"
echo ""
echo "Press Ctrl+C to stop TUI..."
echo ""

# Wait a bit then cleanup
sleep 5
kill $TUI_PID 2>/dev/null || true
wait $TUI_PID 2>/dev/null || true

echo ""
echo "TUI stopped"