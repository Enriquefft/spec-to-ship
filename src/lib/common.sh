#!/usr/bin/env bash
# src/lib/common.sh - Shared utilities for logging, colors, and error handling

# Enable strict mode
set -euo pipefail

# Color codes for terminal output (only set if not already set)
if [[ -z "${COLOR_RESET:-}" ]]; then
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_RED='\033[0;31m'
    readonly COLOR_YELLOW='\033[0;33m'
    readonly COLOR_GREEN='\033[0;32m'
    readonly COLOR_BLUE='\033[0;34m'
    readonly COLOR_GRAY='\033[0;90m'
fi

# Log level configuration
VERBOSE="${VERBOSE:-false}"
LOG_LEVEL="${WORKFLOW_LOG_LEVEL:-INFO}"
COMPONENT="${COMPONENT:-workflow}"

# Log file path (set by calling script)
LOG_FILE="${LOG_FILE:-}"

# Get timestamp for logs
_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Sanitize message to remove secrets
_sanitize_message() {
    local message="$1"

    # Define secret patterns to redact
    local patterns=(
        's/sk-[a-zA-Z0-9]{32,}/[REDACTED_API_KEY]/g'
        's/ghp_[a-zA-Z0-9]{36}/[REDACTED_GITHUB_TOKEN]/g'
        's/gho_[a-zA-Z0-9]{36}/[REDACTED_GITHUB_OAUTH]/g'
        's/AIza[0-9A-Za-z_-]{35}/[REDACTED_GOOGLE_KEY]/g'
        's/Bearer [a-zA-Z0-9._~+\/-]+=*/Bearer [REDACTED_TOKEN]/g'
        's/token[=:][[:space:]]*[a-zA-Z0-9._~+\/-]+=*/token=[REDACTED_TOKEN]/gi'
        's/password[=:][[:space:]]*[^[:space:]]+/password=[REDACTED_PASSWORD]/gi'
        's/secret[=:][[:space:]]*[^[:space:]]+/secret=[REDACTED_SECRET]/gi'
        's/apikey[=:][[:space:]]*[^[:space:]]+/apikey=[REDACTED_KEY]/gi'
        's/api_key[=:][[:space:]]*[^[:space:]]+/api_key=[REDACTED_KEY]/gi'
        's/-----BEGIN[[:space:]].*PRIVATE KEY-----.*-----END[[:space:]].*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g'
    )

    # Apply all patterns (suppress errors for portability)
    for pattern in "${patterns[@]}"; do
        message="$(echo "$message" | sed -E "$pattern" 2>/dev/null)" || true
    done

    echo "$message"
}

# Log to file if LOG_FILE is set
_log_to_file() {
    local level="$1"
    local message="$2"

    if [[ -n "$LOG_FILE" ]]; then
        # Sanitize message before writing to file
        local sanitized_message
        sanitized_message="$(_sanitize_message "$message")"
        echo "[$(_timestamp)] [$level] [$COMPONENT] $sanitized_message" >> "$LOG_FILE"
    fi
}

# log_debug(message) - Log debug message (only if VERBOSE=true)
log_debug() {
    local message="$1"

    _log_to_file "DEBUG" "$message"

    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${COLOR_GRAY}[DEBUG] [$COMPONENT] $message${COLOR_RESET}" >&2
    fi
}

# log_info(message) - Log info message
log_info() {
    local message="$1"

    _log_to_file "INFO" "$message"
    echo -e "${COLOR_BLUE}[INFO] [$COMPONENT] $message${COLOR_RESET}" >&2
}

# log_warn(message) - Log warning message
log_warn() {
    local message="$1"

    _log_to_file "WARN" "$message"
    echo -e "${COLOR_YELLOW}[WARN] [$COMPONENT] $message${COLOR_RESET}" >&2
}

# log_error(message) - Log error message
log_error() {
    local message="$1"

    _log_to_file "ERROR" "$message"
    echo -e "${COLOR_RED}[ERROR] [$COMPONENT] $message${COLOR_RESET}" >&2
}

# die(message, exit_code) - Log error and exit
die() {
    local message="$1"
    local exit_code="${2:-1}"

    log_error "$message"
    exit "$exit_code"
}

# require_command(cmd) - Check if command exists
require_command() {
    local cmd="$1"

    if ! command -v "$cmd" &> /dev/null; then
        die "Required command not found: $cmd" 1
    fi

    log_debug "Found required command: $cmd"
    return 0
}

# require_file(path) - Check if file exists
require_file() {
    local path="$1"

    if [[ ! -f "$path" ]]; then
        die "Required file not found: $path" 1
    fi

    log_debug "Found required file: $path"
    return 0
}

# ensure_dir(path) - Create directory if not exists
ensure_dir() {
    local path="$1"

    if [[ ! -d "$path" ]]; then
        if ! mkdir -p "$path"; then
            log_error "Failed to create directory: $path"
            return 1
        fi
        log_debug "Created directory: $path"
    fi

    return 0
}

# is_in_git_repo() - Check if current directory is in a git repo
is_in_git_repo() {
    git rev-parse --is-inside-work-tree &> /dev/null
}

# get_git_root() - Get git repository root path
get_git_root() {
    if ! is_in_git_repo; then
        return 1
    fi

    git rev-parse --show-toplevel
}

# confirm_action(prompt) - Prompt user for yes/no confirmation
confirm_action() {
    local prompt="$1"
    local response

    echo -n "${prompt} [y/N]: " >&2
    read -r response

    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# parse_options(args) - Helper for parsing command-line options
# Usage: while parse_opt; do case "$opt" in ...; esac; done
parse_opt() {
    if [[ $# -eq 0 ]]; then
        return 1
    fi

    opt="$1"
    return 0
}
