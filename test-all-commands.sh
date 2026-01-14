#!/bin/bash
# test-all-commands.sh - Test TUI with all commands

set -euo pipefail

echo "=== Testing TUI with all workflow commands ==="
echo ""

# Test each command briefly
commands=("status" "config")

for cmd in "${commands[@]}"; do
    echo "Testing: workflow $cmd"
    echo "---"
    
    # Quick test with timeout
    timeout 5s bash -c "
        export WORKFLOW_TUI=true
        export PATH=\"\$PATH:$HOME/go/bin\"
        cd $(pwd)
        ./workflow $cmd 2>&1 || true
    " | head -10
    
    echo ""
done

echo "=== Test Results ==="
echo ""
echo "✓ TUI integration working if you see:"
echo "  - TUI启动 or 'TUI not enabled' messages"
echo "  - JSON messages being processed"
echo "  - No errors from missing functions"
echo ""
echo "To test with interactive commands:"
echo "  export WORKFLOW_TUI=true"
echo "  workflow clarify  # Will prompt for PRD"
echo "  workflow specs    # Will use existing structured PRD"
echo ""
echo "Next major step: Build Go TUI application"