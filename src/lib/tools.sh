#!/usr/bin/env bash
# src/lib/tools.sh - Standardized tools for Agentic Workflow
# These functions are "called" by the agent via XML tags.

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/interaction.sh
source "${LIB_DIR}/interaction.sh"

# ==============================================================================
# Internal Helpers
# ==============================================================================

_agent_is_permission_denied() {
    echo "$1" | grep -qi "permission denied"
}

# _agent_handle_permission_denied(action, target, retry_hint)
# Returns 0 if caller should retry once, 1 otherwise.
_agent_handle_permission_denied() {
    local action="$1"
    local target="$2"
    local retry_hint="$3"

    if ! hitl_is_enabled; then
        echo "Permission denied while $action: $target. Fix permissions and retry, or enable HITL for guided recovery." >&2
        return 1
    fi

    local options=(
        "I'll fix permissions now; retry once"
        "Show the command to run manually"
        "Skip this step (return error)"
    )

    local choice
    choice=$(hitl_select_option "Permission denied while $action on $target. How should we proceed?" 1 "Retry after you adjust permissions" "${options[@]}") || return 1

    case "$choice" in
        "I'll fix permissions now; retry once")
            hitl_prompt "Fix permissions, then press Enter to retry." "clarification" "" >/dev/null || true
            return 0
            ;;
        "Show the command to run manually")
            if [[ -n "$retry_hint" ]]; then
                echo "Run manually:" >&2
                echo "$retry_hint" >&2
            fi
            return 1
            ;;
        *)
            return 1
            ;;
    esac
}

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
    local mkdir_output=""
    if ! mkdir_output=$(mkdir -p "$dir" 2>&1); then
        echo "$mkdir_output" >&2
        if _agent_is_permission_denied "$mkdir_output" && _agent_handle_permission_denied "creating directory" "$dir" "mkdir -p \"$dir\""; then
            if ! mkdir -p "$dir"; then
                echo "Permission denied while creating directory after retry: $dir" >&2
                return 1
            fi
        else
            return 1
        fi
    fi

    # Write content
    local write_output=""
    if ! write_output=$( { echo "$content" > "$path"; } 2>&1 ); then
        echo "$write_output" >&2
        if _agent_is_permission_denied "$write_output" && _agent_handle_permission_denied "writing file" "$path" "cat > \"$path\" <<'EOF'\n$content\nEOF"; then
            if ! echo "$content" > "$path" 2>/dev/null; then
                echo "Permission denied while writing file after retry: $path" >&2
                return 1
            fi
        else
            return 1
        fi
    fi
    
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
    local output
    output=$(eval "$cmd" 2>&1)
    local exit_code=$?
    echo "$output"
    echo "--- End Output (Exit Code: $exit_code) ---"

    if [[ $exit_code -ne 0 ]] && _agent_is_permission_denied "$output"; then
        if _agent_handle_permission_denied "running command" "$cmd" "$cmd"; then
            echo "Retrying after permission fix..." >&2
            output=$(eval "$cmd" 2>&1)
            exit_code=$?
            echo "$output"
            echo "--- End Output (Exit Code: $exit_code) ---"
        fi
    fi

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
