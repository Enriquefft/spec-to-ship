#!/bin/bash
# setup-go.sh - Install and configure Go 1.22

set -euo pipefail

echo "=== Setting up Go 1.22 for TUI ==="

# Check if Go 1.22+ already installed
if command -v go &>/dev/null; then
    GO_VERSION=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | cut -c3-)
    MIN_VERSION="1.22"
    
    if [[ "$(printf '%s\n' "$MIN_VERSION" "$GO_VERSION" | sort -V | head -n1)" == "$MIN_VERSION" ]]; then
        echo "✓ Go $GO_VERSION already installed"
        echo "GOPATH: ${GOPATH:-$HOME/go}"
        echo "GOROOT: ${GOROOT:-$(go env GOROOT)}"
        return 0
    else
        echo "Go version $GO_VERSION is too old, need 1.22+"
    fi
fi

# Download and install Go 1.22.0
GO_VERSION="1.22.0"
GO_ARCHIVE="go${GO_VERSION}.linux-amd64.tar.gz"

echo "Downloading Go $GO_VERSION..."
cd /tmp
wget -q "https://go.dev/dl/${GO_ARCHIVE}"

echo "Extracting to /usr/local..."
if [[ $EUID -eq 0 ]]; then
    sudo tar -C /usr/local -xzf "$GO_ARCHIVE"
else
    # User install - create local go directory
    mkdir -p "$HOME/.local"
    tar -C "$HOME/.local" -xzf "$GO_ARCHIVE"
    
    # Add to PATH in .bashrc if not already there
    if ! grep -q 'export PATH=.*\.local/go/bin' "$HOME/.bashrc"; then
        echo "" >> "$HOME/.bashrc"
        echo "# Go 1.22 for Spec-to-Ship TUI" >> "$HOME/.bashrc"
        echo 'export PATH=$PATH:$HOME/.local/go/bin' >> "$HOME/.bashrc"
        echo 'export GOPATH=$HOME/.local/go' >> "$HOME/.bashrc"
    fi
    
    echo ""
    echo "=== Go installed for current user ==="
    echo "Location: $HOME/.local/go"
    echo ""
    echo "IMPORTANT: Run the following to use Go:"
    echo "  source ~/.bashrc"
    echo "  export PATH=\$PATH:$HOME/.local/go/bin"
    echo "  export GOPATH=$HOME/.local/go"
fi

# Cleanup
rm -f "/tmp/$GO_ARCHIVE"

echo ""
echo "Installation complete!"