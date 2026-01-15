#!/bin/bash
# simple-message-injection.sh - Add basic message injection to TUI

set -euo pipefail

echo "=== Simple Message Injection ==="
echo ""

# Update message types
cat >> internal/message/types.go <<'EOF'

// Add injection message type
func (m *LLMStartMessage) WithInjectionQueue(queue []string) *LLMStartMessage {
    return m
}

type LLMInjectMessage struct {
    BaseMessage
    TaskID  string `json:"task_id,omitempty"`
    Content string `json:"content"`
}

func (m *LLMInjectMessage) GetType() MessageType {
    return TypeLLMInject
}

// Add to DecodeMessage
case TypeLLMInject:
    if strings.HasPrefix(string(data), `"type":"llm_inject"`) {
        var msg LLMInjectMessage
        return &msg, json.Unmarshal(data, &msg)
    }
EOF

echo "✓ Added injection message type"

# Update TUI bridge
echo ""
echo "📝 Updating TUI bridge..."
cat >> src/lib/tui_bridge.sh <<'EOF'

# Add injection function
tui_inject_message() {
    local task_id="$1"
    local content="$2"
    
    local json
    json="$(cat <<INNEREOF
{
  "type": "llm_inject",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "task_id": "$task_id",
  "content": "$content"
}
INNEREOF
)"
    
    tui_emit "$json"
}

# Update provider to check for injection
EOF

echo "✓ Updated TUI bridge with injection support"

echo ""
echo "=== Summary ==="
echo ""
echo "✅ Added message injection capability"
echo ""
echo "Next steps:"
echo "1. Update provider.sh to handle injected messages"
echo "2. Update TUI to display injected messages"
echo "3. Test with: export WORKFLOW_TUI=true"
echo ""
echo "Usage example:"
echo "  tui_inject_message 'task_123' 'Additional context: focus on error handling'"