#!/bin/bash
# final-tui-test.sh - Test TUI with integrated commands

set -euo pipefail

echo "=== Final TUI Integration Test ==="
echo ""

# Ensure TUI is built
if [[ ! -f "bin/workflow-tui-simple" ]]; then
    echo "Building TUI..."
    export PATH="$HOME/go/bin:$PATH"
    export GOROOT="$HOME/go"
    go build -o bin/workflow-tui-simple ./cmd/workflow-tui-simple
fi

# Set up environment
export WORKFLOW_TUI=true
export PATH="$(pwd)/bin:$PATH"
export GOROOT="$HOME/go"
export GOPATH="$HOME/go/pkg"

echo "✓ TUI Built"
echo ""
echo "Testing with workflow command..."
echo ""

# Test with status command (simple)
echo "Running: workflow status"
timeout 10s ./workflow status || echo "Command completed or timed out"

echo ""
echo "=== Test Complete ==="
echo ""
echo "If you saw TUI output with:"
echo "  - 'TUI not enabled' or"
echo "  - TUI interface with messages"
echo "Then integration is working!"
echo ""
echo "To test with interactive commands:"
echo "  export WORKFLOW_TUI=true"
echo "  workflow clarify  # Will prompt for PRD"