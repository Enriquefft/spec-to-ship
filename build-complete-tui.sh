#!/bin/bash
# build-complete-tui.sh - Complete TUI build and installation

set -euo pipefail

echo "=== Building Complete TUI System ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Step 1: Check Go
echo -e "${YELLOW}Step 1: Checking Go installation...${NC}"
if command -v go &>/dev/null; then
    GO_VERSION=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | cut -c3-)
    if [[ "$(printf '%s\n' "1.22" "$GO_VERSION" | sort -V | head -n1)" == "1.22" ]]; then
        echo -e "${GREEN}✓ Go $GO_VERSION installed${NC}"
    else
        echo -e "${RED}✗ Go $GO_VERSION is too old${NC}"
        echo "Run ./setup-go.sh to install Go 1.22"
        exit 1
    fi
else
    echo -e "${RED}✗ Go not installed${NC}"
    echo "Run ./setup-go.sh to install Go 1.22"
    exit 1
fi

# Step 2: Build Go TUI
echo ""
echo -e "${YELLOW}Step 2: Building Go TUI application...${NC}"
export GOPATH="${HOME}/.local/go"
export GOCACHE="${HOME}/.cache/go-build"
mkdir -p "$GOPATH" "$GOCACHE"

# Build for multiple platforms
platforms=("linux/amd64" "darwin/amd64" "windows/amd64")

for platform in "${platforms[@]}"; do
    GOOS=${platform%/*}
    GOARCH=${platform#*/}
    
    output="bin/workflow-tui-${GOOS}-${GOARCH}"
    if [[ "$GOOS" == "windows" ]]; then
        output="${output}.exe"
    fi
    
    echo "Building for $GOOS/$GOARCH..."
    
    if GOOS=$GOOS GOARCH=$GOARCH go build \
        -ldflags="-s -w" \
        -o "$output" \
        ./cmd/workflow-tui 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $output"
    else
        echo -e "  ${RED}✗${NC} Build failed for $platform"
    fi
done

# Step 3: Create convenience wrapper
echo ""
echo -e "${YELLOW}Step 3: Creating workflow-tui wrapper...${NC}"

# Determine platform
CURRENT_GOOS=$(go env GOOS)
CURRENT_GOARCH=$(go env GOARCH)

# Create simple wrapper
cat > "workflow-tui-${CURRENT_GOOS}" <<'EOF'
#!/bin/bash
# workflow-tui wrapper - launches appropriate binary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BINARY="workflow-tui-${CURRENT_GOOS}-${CURRENT_GOARCH}"

# Add .exe for Windows
if [[ "$CURRENT_GOOS" == "windows" ]]; then
    BINARY="${BINARY}.exe"
fi

# Export Go path if not in PATH
if ! command -v go &>/dev/null && [[ -d "$HOME/go" ]]; then
    export PATH="$HOME/go/bin:$PATH"
fi

# Launch the binary
exec "$SCRIPT_DIR/bin/$BINARY" "$@"
EOF

chmod +x "workflow-tui-${CURRENT_GOOS}"

echo -e "${GREEN}✓${NC} Created wrapper: workflow-tui-${CURRENT_GOOS}"

# Step 4: Install to system (optional)
echo ""
echo -e "${YELLOW}Step 4: Installation options...${NC}"
echo ""
echo "TUI components ready:"
ls -lh bin/workflow-tui-* 2>/dev/null || echo "  No binaries built"
echo ""
echo "To install system-wide:"
echo "  sudo cp bin/workflow-tui-$(go env GOOS)-$(go env GOARCH) /usr/local/bin/workflow-tui"
echo ""
echo "To install for user:"
echo "  cp bin/workflow-tui-$(go env GOOS)-$(go env GOARCH) ~/.local/bin/workflow-tui"
echo ""
echo "Or use the wrapper:"
echo "  ./workflow-tui-$(go env GOOS) --help"

# Step 5: Test
echo ""
echo -e "${YELLOW}Step 5: Quick test...${NC}"

# Test if binary exists
BINARY="bin/workflow-tui-${CURRENT_GOOS}-${CURRENT_GOARCH}"
if [[ "$CURRENT_GOOS" == "windows" ]]; then
    BINARY="${BINARY}.exe"
fi

if [[ -f "$BINARY" ]]; then
    echo -e "${GREEN}✓ Binary built successfully${NC}"
    
    # Quick smoke test
    if timeout 2s "$BINARY" --version &>/dev/null; then
        echo -e "${GREEN}✓ Binary runs${NC}"
    else
        echo -e "${YELLOW}⚠ Binary may need testing${NC}"
    fi
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
echo ""
echo "Next steps:"
echo "1. Install workflow-tui to your PATH"
echo "2. Run: export WORKFLOW_TUI=true"
echo "3. Test: workflow clarify"
echo ""
echo "The TUI will show:"
echo "  - Split screen with workflow status (top)"
echo "  - Real-time LLM communication stream (bottom)"
echo "  - Message injection with Ctrl+I"