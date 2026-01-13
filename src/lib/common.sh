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
    readonly COLOR_CYAN='\033[0;36m'
    readonly COLOR_GRAY='\033[0;90m'
    readonly COLOR_BOLD='\033[1m'
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
# Optimized: Single sed invocation with all patterns combined
_sanitize_message() {
    local message="$1"

    # Apply all secret patterns in a single sed invocation for performance
    # shellcheck disable=SC2016  # $ in sed patterns are not variables
    echo "$message" | sed -E \
        -e 's/sk-[a-zA-Z0-9]{32,}/[REDACTED_API_KEY]/g' \
        -e 's/ghp_[a-zA-Z0-9]{36}/[REDACTED_GITHUB_TOKEN]/g' \
        -e 's/gho_[a-zA-Z0-9]{36}/[REDACTED_GITHUB_OAUTH]/g' \
        -e 's/AIza[0-9A-Za-z_-]{35}/[REDACTED_GOOGLE_KEY]/g' \
        -e 's/Bearer [a-zA-Z0-9._~+\/-]+=*/Bearer [REDACTED_TOKEN]/g' \
        -e 's/token[=:][[:space:]]*[a-zA-Z0-9._~+\/-]+=*/token=[REDACTED_TOKEN]/gi' \
        -e 's/password[=:][[:space:]]*[^[:space:]]+/password=[REDACTED_PASSWORD]/gi' \
        -e 's/secret[=:][[:space:]]*[^[:space:]]+/secret=[REDACTED_SECRET]/gi' \
        -e 's/apikey[=:][[:space:]]*[^[:space:]]+/apikey=[REDACTED_KEY]/gi' \
        -e 's/api_key[=:][[:space:]]*[^[:space:]]+/api_key=[REDACTED_KEY]/gi' \
        -e 's/-----BEGIN[[:space:]].*PRIVATE KEY-----.*-----END[[:space:]].*PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
        2>/dev/null || echo "$message"
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

# resolve_prompt_template(prompt_name, project_root) - Resolve path to prompt template
# Arguments:
#   prompt_name: Name of prompt file (e.g., "PROMPT_clarify.md")
#   project_root: Project root directory
# Returns: Absolute path to prompt template file
resolve_prompt_template() {
    local prompt_name="$1"
    local project_root="$2"
    local prompt_file

    # Check project-specific prompts first
    if [[ -f "${project_root}/src/prompts/${prompt_name}" ]]; then
        prompt_file="${project_root}/src/prompts/${prompt_name}"
    # Check workflow installation via WORKFLOW_BIN
    elif [[ -n "${WORKFLOW_BIN:-}" ]] && [[ -f "$(dirname "$WORKFLOW_BIN")/../prompts/${prompt_name}" ]]; then
        prompt_file="$(dirname "$WORKFLOW_BIN")/../prompts/${prompt_name}"
    else
        # Fallback: use prompts from current script location
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
        prompt_file="${script_dir}/prompts/${prompt_name}"
    fi

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt template not found: $prompt_file"
        return 1
    fi

    log_debug "Resolved prompt template: $prompt_file"
    echo "$prompt_file"
    return 0
}

# present_alternatives(title, opt1_name, opt1_desc, opt1_pros, opt1_cons, opt2_name, opt2_desc, opt2_pros, opt2_cons, opt3_name, opt3_desc, opt3_pros, opt3_cons, recommended, [rec_reasoning]) - Present alternatives and get user choice
# Arguments: title, then for each of 3 options: name, description, pros (comma-sep), cons (comma-sep), then recommended option (A/B/C), optional reasoning
# Returns: Selected option (A, B, C, or custom command if user provides custom)
# Follows the speckit.clarify pattern: recommendation at top, table format, accepts "yes"/"recommended"
present_alternatives() {
    local title="$1"
    local opt_a_name="$2"
    local opt_a_desc="$3"
    local opt_a_pros="$4"
    local opt_a_cons="$5"
    local opt_b_name="$6"
    local opt_b_desc="$7"
    local opt_b_pros="$8"
    local opt_b_cons="$9"
    local opt_c_name="${10}"
    local opt_c_desc="${11}"
    local opt_c_pros="${12}"
    local opt_c_cons="${13}"
    local recommended="${14}"
    local rec_reasoning="${15:-Best balance of benefits vs trade-offs for most use cases}"

    # Header
    echo "" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}$title${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2

    # Recommendation (Prominent at top)
    if [[ "$recommended" =~ ^[ABC]$ ]]; then
        local rec_name
        case "$recommended" in
            A) rec_name="$opt_a_name" ;;
            B) rec_name="$opt_b_name" ;;
            C) rec_name="$opt_c_name" ;;
        esac
        echo -e "${COLOR_GREEN}**Recommended:** Option [$recommended] ($rec_name) - $rec_reasoning${COLOR_RESET}" >&2
        echo "" >&2
    fi

    # Options Table
    echo "| Option | Description |" >&2
    echo "|--------|-------------|" >&2
    echo "| A | $opt_a_name: $opt_a_desc |" >&2
    echo "| B | $opt_b_name: $opt_b_desc |" >&2
    echo "| C | $opt_c_name: $opt_c_desc |" >&2
    echo "| Short | Provide a different short answer (<=5 words) |" >&2
    echo "" >&2

    # Details (collapsible info)
    echo -e "${COLOR_GRAY}Details:${COLOR_RESET}" >&2
    echo -e "${COLOR_GRAY}  [A] Pros: $opt_a_pros | Cons: $opt_a_cons${COLOR_RESET}" >&2
    echo -e "${COLOR_GRAY}  [B] Pros: $opt_b_pros | Cons: $opt_b_cons${COLOR_RESET}" >&2
    echo -e "${COLOR_GRAY}  [C] Pros: $opt_c_pros | Cons: $opt_c_cons${COLOR_RESET}" >&2
    echo "" >&2

    # Instructions
    echo "You can reply with the option letter (e.g., \"A\"), accept the recommendation" >&2
    echo "by saying \"yes\" or \"recommended\", or provide your own short answer." >&2
    echo "" >&2
    echo -n "Your choice: " >&2

    # Get user choice
    local choice
    read -r choice

    # Process aliases
    case "${choice,,}" in
        y|yes|rec|recommended|suggested)
            if [[ "$recommended" =~ ^[ABC]$ ]]; then
                choice="$recommended"
                log_debug "User accepted recommendation: $recommended"
            fi
            ;;
        a|b|c)
            choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
            ;;
    esac

    # Return choice
    case "$choice" in
        A|B|C)
            echo "$choice"
            return 0
            ;;
        *)
            # Custom option
            if [[ -n "$choice" ]]; then
                echo "$choice"
                return 0
            else
                log_error "No option selected"
                return 1
            fi
            ;;
    esac
}
