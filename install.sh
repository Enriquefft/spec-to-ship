#!/usr/bin/env bash
# install.sh - Install workflow command globally

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly RESET='\033[0m'

# Installation directory (default: ~/.local/bin)
INSTALL_DIR="${HOME}/.local/bin"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
    cat <<EOF
install.sh - Install workflow command globally

USAGE:
    ./install.sh [options]

OPTIONS:
    -d, --dir DIR       Install to DIR instead of ~/.local/bin
    -u, --uninstall     Uninstall the workflow command
    -h, --help          Show this help message

EXAMPLES:
    # Install to default location (~/.local/bin)
    ./install.sh

    # Install to custom location
    ./install.sh --dir /usr/local/bin

    # Uninstall
    ./install.sh --uninstall

NOTES:
    - The installation creates a symlink, so updates to the repo will
      automatically be reflected in the installed command
    - Make sure the installation directory is in your PATH
    - On most systems, ~/.local/bin is already in PATH

EOF
}

# Parse command-line options
UNINSTALL=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -u|--uninstall)
            UNINSTALL=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}ERROR: Unknown option: $1${RESET}" >&2
            show_help
            exit 1
            ;;
    esac
done

# Uninstall if requested
if [[ "$UNINSTALL" == "true" ]]; then
    echo -e "${BLUE}Uninstalling workflow command...${RESET}"

    if [[ -L "${INSTALL_DIR}/workflow" ]]; then
        rm "${INSTALL_DIR}/workflow"
        echo -e "${GREEN}✓ Removed symlink: ${INSTALL_DIR}/workflow${RESET}"
    else
        echo -e "${YELLOW}⚠ Symlink not found: ${INSTALL_DIR}/workflow${RESET}"
    fi

    echo -e "${GREEN}Uninstall complete${RESET}"
    exit 0
fi

# Install
echo -e "${BLUE}Installing workflow command...${RESET}"

# Create installation directory if it doesn't exist
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}Creating directory: $INSTALL_DIR${RESET}"
    mkdir -p "$INSTALL_DIR"
fi

# Check if workflow script exists
if [[ ! -f "${SCRIPT_DIR}/src/workflow" ]]; then
    echo -e "${RED}ERROR: workflow script not found at ${SCRIPT_DIR}/src/workflow${RESET}" >&2
    exit 1
fi

# Create symlink
if [[ -L "${INSTALL_DIR}/workflow" ]]; then
    echo -e "${YELLOW}⚠ Symlink already exists, removing old one${RESET}"
    rm "${INSTALL_DIR}/workflow"
fi

ln -s "${SCRIPT_DIR}/src/workflow" "${INSTALL_DIR}/workflow"
echo -e "${GREEN}✓ Created symlink: ${INSTALL_DIR}/workflow -> ${SCRIPT_DIR}/src/workflow${RESET}"

# Check if INSTALL_DIR is in PATH
if [[ ":$PATH:" == *":${INSTALL_DIR}:"* ]]; then
    echo -e "${GREEN}✓ ${INSTALL_DIR} is in your PATH${RESET}"
else
    echo -e "${YELLOW}⚠ WARNING: ${INSTALL_DIR} is NOT in your PATH${RESET}"
    echo ""
    echo "To add it to your PATH, add this line to your ~/.bashrc or ~/.zshrc:"
    echo ""
    echo -e "    ${BLUE}export PATH=\"${INSTALL_DIR}:\$PATH\"${RESET}"
    echo ""
    echo "Then reload your shell with: source ~/.bashrc"
fi

echo ""
echo -e "${GREEN}Installation complete!${RESET}"
echo ""
echo "Try running: workflow --help"
echo ""
