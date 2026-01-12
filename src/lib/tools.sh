#!/usr/bin/env bash
# src/lib/tools.sh - Standardized tools for Agentic Workflow
# These functions are "called" by the agent via XML tags.

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Tool Definitions
# ==============================================================================

# agent_tool_read_file(path)
# Reads content of a file.
agent_tool_read_file() {
    local path="$1"
    
    if [[ -z "$path" ]]; then
        echo "Error: No file path provided"
        return 1
    fi

    if [[ ! -f "$path" ]]; then
        echo "Error: File not found: $path"
        return 1
    fi

    echo "--- START OF FILE: $path ---"
    cat "$path"
    echo "--- END OF FILE: $path ---"
    return 0
}

# agent_tool_write_file(path, content)
# Writes content to a file. Creates directories if needed.
agent_tool_write_file() {
    local path="$1"
    local content="$2" # Content is passed as a string or via stdin if empty

    if [[ -z "$path" ]]; then
        echo "Error: No file path provided"
        return 1
    fi

    # Read from stdin if content arg is empty
    if [[ -z "$content" ]]; then
        content="$(cat)"
    fi

    # Create directory if it doesn't exist
    local dir
    dir="$(dirname "$path")"
    mkdir -p "$dir"

    # Write content
    echo "$content" > "$path"
    
    echo "Successfully wrote to $path"
    return 0
}

# agent_tool_list_files(path, depth)
# Lists files in a directory (like tree or ls -R)
agent_tool_list_files() {
    local path="${1:-.}"
    local depth="${2:-2}"

    if [[ ! -d "$path" ]]; then
        echo "Error: Directory not found: $path"
        return 1
    fi

    if command -v tree &>/dev/null; then
        tree -L "$depth" -I '.git|node_modules|.DS_Store' "$path"
    else
        find "$path" -maxdepth "$depth" -not -path '*/.*'
    fi
    return 0
}

# agent_tool_run_command(command)
# Executes a shell command.
# SAFETY: This is powerful. In a real system, we'd want strict allowlists.
agent_tool_run_command() {
    local cmd="$1"
    
    if [[ -z "$cmd" ]]; then
        echo "Error: No command provided"
        return 1
    fi

    echo "Executing: $cmd"
    echo "--- Output ---"
    eval "$cmd" 2>&1
    local exit_code=$?
    echo "--- End Output (Exit Code: $exit_code) ---"
    
    return $exit_code
}

# ==============================================================================
# Dispatcher
# ==============================================================================

# agent_dispatch_tool(tool_name, args...)
# Helper to dispatch to specific tool functions
agent_dispatch_tool() {
    local tool_name="$1"
    shift
    
    case "$tool_name" in
        read_file)
            agent_tool_read_file "$@"
            ;;
        write_file)
            agent_tool_write_file "$@"
            ;;
        list_files)
            agent_tool_list_files "$@"
            ;;
        run_command)
            agent_tool_run_command "$@"
            ;;
        *)
            echo "Error: Unknown tool '$tool_name'"
            return 1
            ;;
    esac
}
