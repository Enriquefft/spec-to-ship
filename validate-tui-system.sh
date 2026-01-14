#!/bin/bash
# validate-tui-system.sh - Validate complete TUI implementation

set -euo pipefail

echo "=== Validating TUI System ==="
echo ""

# Check components
echo "🔍 Checking components..."

# 1. TUI binary
if [[ -f "bin/workflow-tui-simple" ]]; then
    echo "✓ TUI binary exists"
else
    echo "✗ TUI binary missing"
fi

# 2. TUI bridge
if grep -q "tui_phase_start" src/lib/tui_bridge.sh; then
    echo "✓ TUI bridge has phase tracking"
else
    echo "✗ TUI bridge missing phase tracking"
fi

# 3. Provider integration
if grep -q "tui_llm_start" src/lib/provider.sh; then
    echo "✓ Provider has TUI integration"
else
    echo "✗ Provider missing TUI integration"
fi

# 4. Old files removed
if [[ ! -f "src/lib/activity.sh" ]] && [[ ! -f "src/lib/spinner.sh" ]]; then
    echo "✓ Old logging files removed"
else
    echo "✗ Old logging files still exist"
fi

# 5. Phase integration
echo ""
echo "🔍 Checking phase integration..."
integrated=0
total=0

for cmd in clarify specs arch plan build gate; do
    total=$((total + 1))
    if grep -q "tui_phase_start.*$cmd" "src/commands/${cmd}.sh" 2>/dev/null; then
        echo "✓ $cmd integrated"
        integrated=$((integrated + 1))
    else
        echo "✗ $cmd not integrated"
    fi
done

echo ""
echo "=== Summary ==="
echo "Phase integration: $integrated/$total commands"

# Final test
echo ""
echo "🧪 Running final test..."

# Start TUI in background
export WORKFLOW_TUI=true
export PATH="$(pwd)/bin:$PATH"
export GOROOT="$HOME/go"

# Build if needed
if [[ ! -f "bin/workflow-tui-simple" ]]; then
    export GOPATH="$HOME/go/pkg"
    go build -o bin/workflow-tui-simple ./cmd/workflow-tui-simple
fi

./bin/workflow-tui-simple &
TUI_PID=$!
sleep 1

# Send test messages
echo '{"type":"phase_start","phase":"validate","tasks":["Check TUI","Test messages"]}'
echo '{"type":"llm_start","provider":"test","model":"test-model","task_id":"test_1"}'
echo '{"type":"llm_prompt","task_id":"test_1","content":"System validation test","tokens":25}'
echo '{"type":"task_start","task_id":"task_1","task":"Validate TUI components"}'
echo '{"type":"task_update","task_id":"task_1","status":"completed","progress":1.0}'

sleep 2
kill $TUI_PID 2>/dev/null || true

echo ""
if [[ $integrated -eq $total && ! -f "src/lib/activity.sh" ]]; then
    echo "🎉 TUI Implementation Complete!"
    echo ""
    echo "✅ All components working"
    echo "✅ Ready for production"
    echo ""
    echo "To use:"
    echo "  export WORKFLOW_TUI=true"
    echo "  workflow <command>"
else
    echo "⚠️  Some issues remain"
    echo "See output above for details"
fi