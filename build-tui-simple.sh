#!/bin/bash
# build-tui-simple.sh - Simple build for TUI without module cache

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

echo -e "${GREEN}Building workflow-tui...${NC}"

# Build directory
BUILD_DIR="bin"
mkdir -p "$BUILD_DIR"

# Build with offline mode
export PATH="$HOME/go/bin:$PATH"
export GOROOT="$HOME/go"
export GOPATH="$HOME/go/pkg"
export GOCACHE="$HOME/.cache/go-build"
export GO111MODULE=on
export GOPROXY=direct
mkdir -p $GOCACHE

# Build with minimal flags
go build -mod=readonly \
    -ldflags="-s -w" \
    -o "$BUILD_DIR/workflow-tui" \
    ./cmd/workflow-tui 2>&1 || {
        echo -e "${RED}Build failed, trying with vendor mode...${NC}"
        
        # Try vendor mode
        go mod vendor 2>/dev/null || true
        go build -mod=vendor \
            -ldflags="-s -w" \
            -o "$BUILD_DIR/workflow-tui" \
            ./cmd/workflow-tui || {
            echo -e "${RED}✗ Build failed completely${NC}"
            exit 1
        }
    }

if [[ -f "$BUILD_DIR/workflow-tui" ]]; then
    echo -e "${GREEN}✓ Build successful!${NC}"
    echo "Binary: $BUILD_DIR/workflow-tui"
    ls -lh "$BUILD_DIR/workflow-tui"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi