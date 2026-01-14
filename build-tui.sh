#!/bin/bash
# build-tui.sh - Build the workflow TUI application

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Check if Go is installed
if ! command -v go &> /dev/null; then
    echo -e "${RED}Error: Go is not installed${NC}"
    echo "Please install Go 1.22 or later from https://golang.org/"
    exit 1
fi

# Check Go version
GO_VERSION=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | cut -c3-)
MIN_VERSION="1.22"

if [ "$(printf '%s\n' "$MIN_VERSION" "$GO_VERSION" | sort -V | head -n1)" != "$MIN_VERSION" ]; then
    echo -e "${RED}Error: Go version $GO_VERSION is too old${NC}"
    echo "Please upgrade to Go $MIN_VERSION or later"
    exit 1
fi

echo -e "${GREEN}Building workflow-tui...${NC}"

# Build directory
BUILD_DIR="bin"
mkdir -p "$BUILD_DIR"

# Build arguments
BUILD_FLAGS=(
    -ldflags="-s -w"  # Strip debug symbols
    -trimpath
)

# Build for current platform
go build "${BUILD_FLAGS[@]}" \
    -o "$BUILD_DIR/workflow-tui" \
    ./cmd/workflow-tui

# Check if build succeeded
if [[ -f "$BUILD_DIR/workflow-tui" ]]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo "Binary: $BUILD_DIR/workflow-tui"
    
    # Show file info
    ls -lh "$BUILD_DIR/workflow-tui"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi

# Optionally install to system PATH
if [[ "${1:-}" == "--install" ]]; then
    INSTALL_DIR="${HOME}/.local/bin"
    mkdir -p "$INSTALL_DIR"
    cp "$BUILD_DIR/workflow-tui" "$INSTALL_DIR/"
    
    # Check if INSTALL_DIR is in PATH
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        echo -e "${YELLOW}Warning: $INSTALL_DIR is not in your PATH${NC}"
        echo "Add the following to your shell profile:"
        echo "export PATH=\"\$PATH:\$HOME/.local/bin\""
    fi
    
    echo -e "${GREEN}✓ Installed to $INSTALL_DIR/workflow-tui${NC}"
fi