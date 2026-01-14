#!/usr/bin/env bash
# src/lib/activity.sh - Transparent activity logging with status line and expandable sections
#
# Features:
#   - Status line: Updates at bottom of terminal showing current activity
#   - Session logs: Detailed activity written to .workflow/logs/
#   - Verbose levels: -v (info), -vv (debug), -vvv (trace with prompts/responses)
#   - Expandable sections: Phase summaries with details on demand

set -euo pipefail

# Source common if not already loaded
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -z "${COLOR_RESET:-}" ]]; then
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
fi

# ============================================================================
# Configuration
# ============================================================================

# Verbose level: 0=quiet, 1=info, 2=debug, 3=trace
ACTIVITY_VERBOSE_LEVEL="${ACTIVITY_VERBOSE_LEVEL:-0}"

# Activity log file (separate from main log, more detailed)
ACTIVITY_LOG_FILE="${ACTIVITY_LOG_FILE:-}"

# Status line state
_ACTIVITY_STATUS_ENABLED="${_ACTIVITY_STATUS_ENABLED:-true}"
_ACTIVITY_STATUS_LINE=""
_ACTIVITY_START_TIME=""
_ACTIVITY_PHASE=""
_ACTIVITY_TASK=""

# Section tracking for expandable summaries
declare -a _ACTIVITY_SECTIONS=()
declare -A _ACTIVITY_SECTION_DATA=()

# ============================================================================
# Verbose Level Helpers
# ============================================================================

# activity_set_verbose(level) - Set verbose level (0-3)
activity_set_verbose() {
    local level="${1:-0}"
    case "$level" in
        0|1|2|3) ACTIVITY_VERBOSE_LEVEL="$level" ;;
        *) ACTIVITY_VERBOSE_LEVEL=0 ;;
    esac
    export ACTIVITY_VERBOSE_LEVEL
}

# activity_verbose_level() - Get current verbose level
activity_verbose_level() {
    echo "$ACTIVITY_VERBOSE_LEVEL"
}

# _activity_should_log(level) - Check if should log at level
_activity_should_log() {
    local level="$1"
    [[ "$ACTIVITY_VERBOSE_LEVEL" -ge "$level" ]]
}

# ============================================================================
# Activity Log File
# ============================================================================

# activity_init_log(log_dir) - Initialize activity log file
activity_init_log() {
    local log_dir="${1:-.workflow/logs}"

    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi

    ACTIVITY_LOG_FILE="${log_dir}/activity_$(date '+%Y%m%d_%H%M%S').log"
    export ACTIVITY_LOG_FILE

    # Write header
    {
        echo "# Activity Log - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# Verbose Level: $ACTIVITY_VERBOSE_LEVEL"
        echo "# =============================================="
        echo ""
    } >> "$ACTIVITY_LOG_FILE"
}

# _activity_log_write(level, category, message, [details]) - Write to activity log
_activity_log_write() {
    local level="$1"
    local category="$2"
    local message="$3"
    local details="${4:-}"

    [[ -z "$ACTIVITY_LOG_FILE" ]] && return 0

    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S.%3N')"
    local level_name
    case "$level" in
        1) level_name="INFO" ;;
        2) level_name="DEBUG" ;;
        3) level_name="TRACE" ;;
        *) level_name="LOG" ;;
    esac

    {
        echo "[$timestamp] [$level_name] [$category] $message"
        if [[ -n "$details" ]]; then
            echo "$details" | sed 's/^/    /'
        fi
    } >> "$ACTIVITY_LOG_FILE"
}

# ============================================================================
# Status Line Display
# ============================================================================

# _activity_get_terminal_height() - Get terminal height
_activity_get_terminal_height() {
    tput lines 2>/dev/null || echo 24
}

# _activity_save_cursor() - Save cursor position
_activity_save_cursor() {
    printf '\033[s' >&2
}

# _activity_restore_cursor() - Restore cursor position
_activity_restore_cursor() {
    printf '\033[u' >&2
}

# _activity_move_to_status_line() - Move cursor to bottom status line
_activity_move_to_status_line() {
    local height
    height="$(_activity_get_terminal_height)"
    printf '\033[%d;1H' "$height" >&2
}

# _activity_clear_status_line() - Clear the status line
_activity_clear_status_line() {
    if [[ -t 2 ]] && [[ "$_ACTIVITY_STATUS_ENABLED" == "true" ]]; then
        _activity_save_cursor
        _activity_move_to_status_line
        printf '\033[K' >&2  # Clear line
        _activity_restore_cursor
    fi
}

# _activity_render_status_line() - Render the current status line
_activity_render_status_line() {
    [[ -t 2 ]] || return 0
    [[ "$_ACTIVITY_STATUS_ENABLED" == "true" ]] || return 0
    [[ -z "$_ACTIVITY_STATUS_LINE" ]] && return 0

    local elapsed=""
    if [[ -n "$_ACTIVITY_START_TIME" ]]; then
        local now
        now="$(date +%s)"
        elapsed=" (${_ACTIVITY_START_TIME}s)"
        elapsed=" ($((now - _ACTIVITY_START_TIME))s)"
    fi

    local status_text="$_ACTIVITY_STATUS_LINE$elapsed"
    local term_width
    term_width="$(tput cols 2>/dev/null || echo 80)"

    # Truncate if too long
    if [[ ${#status_text} -gt $((term_width - 4)) ]]; then
        status_text="${status_text:0:$((term_width - 7))}..."
    fi

    _activity_save_cursor
    _activity_move_to_status_line
    # Dim gray background, white text
    printf '\033[48;5;236m\033[38;5;252m %-*s \033[0m' "$((term_width - 2))" "$status_text" >&2
    _activity_restore_cursor
}

# activity_status(message, [phase], [task]) - Update status line
activity_status() {
    local message="$1"
    local phase="${2:-}"
    local task="${3:-}"

    _ACTIVITY_STATUS_LINE="$message"
    [[ -n "$phase" ]] && _ACTIVITY_PHASE="$phase"
    [[ -n "$task" ]] && _ACTIVITY_TASK="$task"

    # Log to activity file at level 1+
    _activity_log_write 1 "STATUS" "$message"

    _activity_render_status_line
}

# activity_status_start(message) - Start a timed status
activity_status_start() {
    local message="$1"
    _ACTIVITY_START_TIME="$(date +%s)"
    activity_status "$message"
}

# activity_status_clear() - Clear status line
activity_status_clear() {
    _ACTIVITY_STATUS_LINE=""
    _ACTIVITY_START_TIME=""
    _activity_clear_status_line
}

# ============================================================================
# Inline Logging (respects verbose levels)
# ============================================================================

# activity_info(message) - Log info (verbose level 1+)
activity_info() {
    local message="$1"
    _activity_log_write 1 "INFO" "$message"

    if _activity_should_log 1; then
        _activity_clear_status_line
        echo -e "${COLOR_BLUE}[activity]${COLOR_RESET} $message" >&2
        _activity_render_status_line
    fi
}

# activity_debug(message) - Log debug (verbose level 2+)
activity_debug() {
    local message="$1"
    _activity_log_write 2 "DEBUG" "$message"

    if _activity_should_log 2; then
        _activity_clear_status_line
        echo -e "${COLOR_GRAY}[debug]${COLOR_RESET} $message" >&2
        _activity_render_status_line
    fi
}

# activity_trace(message, [details]) - Log trace with optional details (verbose level 3)
activity_trace() {
    local message="$1"
    local details="${2:-}"
    _activity_log_write 3 "TRACE" "$message" "$details"

    if _activity_should_log 3; then
        _activity_clear_status_line
        echo -e "${COLOR_GRAY}[trace]${COLOR_RESET} $message" >&2
        if [[ -n "$details" ]]; then
            # Show truncated details
            local lines
            lines="$(echo "$details" | head -5)"
            local total_lines
            total_lines="$(echo "$details" | wc -l)"
            echo -e "${COLOR_GRAY}$lines${COLOR_RESET}" >&2
            if [[ "$total_lines" -gt 5 ]]; then
                echo -e "${COLOR_GRAY}  ... ($((total_lines - 5)) more lines in log)${COLOR_RESET}" >&2
            fi
        fi
        _activity_render_status_line
    fi
}

# ============================================================================
# Provider/LLM Activity Logging
# ============================================================================

# activity_llm_start(provider, model, phase) - Log LLM invocation start
activity_llm_start() {
    local provider="$1"
    local model="$2"
    local phase="${3:-}"

    activity_status_start "[$provider] $model - ${phase:-thinking}..."
    _activity_log_write 1 "LLM" "Starting: provider=$provider model=$model phase=$phase"
}

# activity_llm_prompt(prompt_content) - Log prompt being sent (level 3)
activity_llm_prompt() {
    local prompt_content="$1"
    local preview="${prompt_content:0:200}"
    _activity_log_write 3 "LLM_PROMPT" "Sending prompt" "$prompt_content"

    if _activity_should_log 3; then
        _activity_clear_status_line
        echo -e "${COLOR_GRAY}[prompt] ${preview}...${COLOR_RESET}" >&2
        _activity_render_status_line
    fi
}

# activity_llm_complete(duration, tokens) - Log LLM completion
activity_llm_complete() {
    local duration="${1:-0}"
    local tokens="${2:-unknown}"

    _activity_log_write 1 "LLM" "Completed: duration=${duration}s tokens=$tokens"
    activity_status_clear
}

# activity_llm_response(response_content) - Log response received (level 3)
activity_llm_response() {
    local response_content="$1"
    local preview="${response_content:0:200}"
    _activity_log_write 3 "LLM_RESPONSE" "Received response" "$response_content"

    if _activity_should_log 3; then
        _activity_clear_status_line
        echo -e "${COLOR_GRAY}[response] ${preview}...${COLOR_RESET}" >&2
        _activity_render_status_line
    fi
}

# ============================================================================
# Expandable Sections
# ============================================================================

# activity_section_start(id, title) - Start a new section
activity_section_start() {
    local id="$1"
    local title="$2"

    _ACTIVITY_SECTIONS+=("$id")
    _ACTIVITY_SECTION_DATA["${id}_title"]="$title"
    _ACTIVITY_SECTION_DATA["${id}_start"]="$(date +%s)"
    _ACTIVITY_SECTION_DATA["${id}_tokens"]=0
    _ACTIVITY_SECTION_DATA["${id}_details"]=""

    _activity_log_write 1 "SECTION" "Started: $id - $title"
}

# activity_section_add_detail(id, detail) - Add detail to section
activity_section_add_detail() {
    local id="$1"
    local detail="$2"

    local existing="${_ACTIVITY_SECTION_DATA["${id}_details"]:-}"
    _ACTIVITY_SECTION_DATA["${id}_details"]="${existing}${detail}\n"
}

# activity_section_set_tokens(id, tokens) - Set token count for section
activity_section_set_tokens() {
    local id="$1"
    local tokens="$2"
    _ACTIVITY_SECTION_DATA["${id}_tokens"]="$tokens"
}

# activity_section_end(id, status) - End section and display summary
activity_section_end() {
    local id="$1"
    local status="${2:-success}"

    local title="${_ACTIVITY_SECTION_DATA["${id}_title"]:-$id}"
    local start="${_ACTIVITY_SECTION_DATA["${id}_start"]:-0}"
    local tokens="${_ACTIVITY_SECTION_DATA["${id}_tokens"]:-0}"
    local details="${_ACTIVITY_SECTION_DATA["${id}_details"]:-}"

    local now
    now="$(date +%s)"
    local duration=$((now - start))

    _activity_log_write 1 "SECTION" "Ended: $id status=$status duration=${duration}s tokens=$tokens"

    # Clear status line before printing section summary
    _activity_clear_status_line

    # Display expandable section summary
    local status_icon status_color
    case "$status" in
        success|done|completed)
            status_icon="✓"
            status_color="$COLOR_GREEN"
            ;;
        error|failed)
            status_icon="✗"
            status_color="$COLOR_RED"
            ;;
        warning|partial)
            status_icon="⚠"
            status_color="$COLOR_YELLOW"
            ;;
        *)
            status_icon="○"
            status_color="$COLOR_BLUE"
            ;;
    esac

    # Main summary line
    local token_display=""
    if [[ "$tokens" -gt 0 ]]; then
        if [[ "$tokens" -ge 1000 ]]; then
            token_display=", $(echo "scale=1; $tokens/1000" | bc)k tokens"
        else
            token_display=", ${tokens} tokens"
        fi
    fi

    echo -e "${status_color}${status_icon}${COLOR_RESET} ${COLOR_BOLD}$title${COLOR_RESET} ${COLOR_GRAY}(${duration}s${token_display})${COLOR_RESET}" >&2

    # Show details hint if there are details
    if [[ -n "$details" ]]; then
        local detail_count
        detail_count="$(echo -e "$details" | grep -c . || echo 0)"
        echo -e "  ${COLOR_GRAY}└─ $detail_count details (see log: $ACTIVITY_LOG_FILE)${COLOR_RESET}" >&2

        # In verbose mode, show first few details inline
        if _activity_should_log 2; then
            echo -e "$details" | head -3 | while read -r line; do
                [[ -n "$line" ]] && echo -e "     ${COLOR_GRAY}$line${COLOR_RESET}" >&2
            done
        fi
    fi

    echo "" >&2
}

# ============================================================================
# Initialization and Cleanup
# ============================================================================

# activity_init(verbose_level, log_dir) - Initialize activity system
activity_init() {
    local verbose_level="${1:-0}"
    local log_dir="${2:-.workflow/logs}"

    activity_set_verbose "$verbose_level"
    activity_init_log "$log_dir"

    # Enable status line if TTY
    if [[ -t 2 ]]; then
        _ACTIVITY_STATUS_ENABLED="true"
        # Reserve bottom line
        echo "" >&2
    else
        _ACTIVITY_STATUS_ENABLED="false"
    fi

    _activity_log_write 1 "INIT" "Activity logging initialized (verbose=$verbose_level)"
}

# activity_cleanup() - Clean up activity system
activity_cleanup() {
    activity_status_clear

    if [[ -n "$ACTIVITY_LOG_FILE" ]]; then
        _activity_log_write 1 "CLEANUP" "Session ended"
        echo "" >> "$ACTIVITY_LOG_FILE"
        echo "# Session ended: $(date '+%Y-%m-%d %H:%M:%S')" >> "$ACTIVITY_LOG_FILE"
    fi
}

# Setup cleanup trap
trap activity_cleanup EXIT
