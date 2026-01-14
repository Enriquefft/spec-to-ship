#!/bin/bash
# plan-add-message-injection.sh - Plan for implementing Ctrl+I message injection

set -euo pipefail

echo "=== Plan: Message Injection Implementation ==="
echo ""

# Check current state
echo "🔍 Current TUI Status:"
if [[ -f "bin/workflow-tui-simple" ]]; then
    echo "✓ Base TUI exists"
else
    echo "✗ Base TUI missing"
fi

if [[ -f "bin/workflow-tui-interactive" ]]; then
    echo "✓ Interactive TUI exists"
else
    echo "✗ Interactive TUI missing"
fi

echo ""
echo "📋 Next Implementation Steps:"
echo ""

cat <<'EOF'
## Phase 1: Enhanced TUI Bridge
- Add message injection channel to TUI bridge
- Modify provider.sh to support message interception
- Add injection message type to protocol

## Phase 2: Enhanced TUI Application
- Add stdin input handling in Go TUI
- Implement injection UI component
- Add message queue for delayed injection
- Add visual feedback for injected messages

## Phase 3: Provider Enhancement
- Add injection point in provider layer
- Capture injected messages before LLM call
- Modify provider invocation to handle injected messages
- Maintain message correlation

## Phase 4: Testing & Validation
- Test injection with various LLM providers
- Validate message ordering
- Test error handling
- Ensure no impact on normal workflow

## Technical Implementation

### Message Protocol Extension
```json
// New message type
{
  "type": "inject_message",
  "task_id": "current_task",
  "content": "User injected message",
  "timestamp": "2025-01-14T10:00:00Z"
}

// Enhanced llm_start
{
  "type": "llm_start",
  "task_id": "task_123",
  "injection_queue": ["msg1", "msg2"],
  "phase": "clarify",
  "provider": "claude",
  "model": "claude-opus-4"
}
```

### Directory Structure
```
src/
├── lib/
│   ├── tui_bridge.sh (modify)
│   └── provider.sh (modify)
└── cmd/
    ├── workflow-tui-simple (enhance)
    └── workflow-tui-injection (new)
        ├── main.go
        └── injection.go
```

### Commands to Execute
```bash
# Create enhanced TUI with injection support
cd /home/hybridz/Projects/spec-to-ship
mkdir -p cmd/workflow-tui-injection

# Build enhanced TUI
go build -o bin/workflow-tui-injection ./cmd/workflow-tui-injection

# Update TUI bridge to use enhanced version
sed -i 's/workflow-tui-simple/workflow-tui-injection/g' src/lib/tui_bridge.sh

# Test injection
export WORKFLOW_TUI=true
export PATH="$(pwd)/bin:$PATH"
export GOROOT="$HOME/go"

# Start enhanced TUI
bin/workflow-tui-injection &
```

## Success Criteria
- [ ] Injection messages appear in TUI
- [ ] Messages reach LLM provider
- [ ] LLM responses include context from injections
- [ ] No disruption to normal workflow
- [ ] Clear visual indication of injected vs normal messages
- [ ] Error handling works correctly
- [ ] Backward compatibility maintained

## Time Estimate: 2-3 hours

## Dependencies
- Go 1.22+
- Existing TUI system
- Provider integration
- Message protocol

## Risk Assessment
- Low: Building on existing working system
- Medium: Complex interaction with LLM providers
- Mitigation: Incremental implementation with fallbacks
EOF

echo ""
echo "✓ Plan created: plan-add-message-injection.md"

# Ask user if ready to proceed
echo ""
read -p "Ready to implement message injection? (y/N): " response
case "${response}" in
    y|Y)
        echo "✓ Proceeding with implementation..."
        exit 0
        ;;
    *)
        echo "✗ Implementation cancelled"
        exit 1
        ;;
esac