#!/usr/bin/env bash
# src/lib/hitl.sh - Human-in-the-loop interaction handling

# Source common utilities
LIB_DIR="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"

# HITL log file location
HITL_LOG=""

# _init_hitl_log() - Initialize HITL log file
_init_hitl_log() {
    local git_root
    if git_root="$(get_git_root)"; then
        HITL_LOG="${git_root}/docs/hitl-log.md"
    else
        HITL_LOG="docs/hitl-log.md"
    fi

    # Create docs directory if needed
    ensure_dir "$(dirname "$HITL_LOG")"

    # Initialize log file if it doesn't exist
    if [[ ! -f "$HITL_LOG" ]]; then
        cat > "$HITL_LOG" <<EOF
# Human-in-the-Loop Interaction Log

This file records all HITL interactions during the workflow execution.

---

EOF
    fi
}

# hitl_is_enabled() - Check if HITL is enabled
hitl_is_enabled() {
    local enabled
    enabled="$(config_get HITL_ENABLED)"

    if [[ "$enabled" == "true" ]]; then
        return 0
    fi

    return 1
}

# hitl_mode() - Get current HITL mode
hitl_mode() {
    config_get HITL_MODE
}

# hitl_should_pause(trigger_type, iteration) - Check if HITL should pause
hitl_should_pause() {
    local trigger_type="$1"
    local iteration="${2:-0}"

    # Check if HITL is enabled
    if ! hitl_is_enabled; then
        return 1
    fi

    local mode
    mode="$(hitl_mode)"

    case "$mode" in
        task)
            # Pause after every task
            if [[ "$trigger_type" == "task" ]]; then
                return 0
            fi
            ;;
        milestone)
            # Pause after milestones
            if [[ "$trigger_type" == "milestone" ]]; then
                return 0
            fi
            ;;
        uncertain)
            # Pause only when uncertain
            if [[ "$trigger_type" == "uncertain" ]]; then
                return 0
            fi
            ;;
        every:*)
            # Pause every N iterations
            local interval="${mode#every:}"
            if [[ "$trigger_type" == "iteration" && $((iteration % interval)) -eq 0 ]]; then
                return 0
            fi
            ;;
    esac

    return 1
}

# hitl_prompt(question, type, options) - Prompt user for input
hitl_prompt() {
    local question="$1"
    local type="${2:-clarification}"
    local options="${3:-}"

    _init_hitl_log

    local timeout
    timeout="$(config_get HITL_TIMEOUT || echo "")"

    # Display question
    echo "" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}HITL PROMPT [$type]${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2
    echo "$question" >&2
    echo "" >&2

    # Display options if provided
    if [[ -n "$options" ]]; then
        echo "Options:" >&2
        echo "$options" >&2
        echo "" >&2
    fi

    # Display timeout if set
    if [[ -n "$timeout" ]]; then
        echo -e "${COLOR_GRAY}(Auto-continue in $timeout if no response)${COLOR_RESET}" >&2
    fi

    echo -n "Your response: " >&2

    # Read user input with timeout
    local response
    if [[ -n "$timeout" ]]; then
        # Parse timeout (e.g., "5m" -> 300 seconds)
        local timeout_seconds
        case "$timeout" in
            *s) timeout_seconds="${timeout%s}" ;;
            *m) timeout_seconds=$((${timeout%m} * 60)) ;;
            *h) timeout_seconds=$((${timeout%h} * 3600)) ;;
            *) timeout_seconds="$timeout" ;;
        esac

        if read -r -t "$timeout_seconds" response; then
            echo "" >&2
        else
            echo "" >&2
            log_warn "HITL timeout reached, auto-continuing"
            response="__TIMEOUT__"
        fi
    else
        read -r response
    fi

    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2

    # Log interaction
    hitl_log "$question" "$response" "Captured response"

    # Return response
    if [[ "$response" == "__TIMEOUT__" ]]; then
        return 1
    fi

    echo "$response"
    return 0
}

# hitl_prompt_yn(question) - Prompt for yes/no response
hitl_prompt_yn() {
    local question="$1"

    local response
    if ! response=$(hitl_prompt "$question" "decision" "y) Yes\nn) No"); then
        # Timeout - default to no
        return 1
    fi

    case "$response" in
        [yY]|[yY][eE][sS])
            echo "y"
            return 0
            ;;
        *)
            echo "n"
            return 1
            ;;
    esac
}

# hitl_log(question, response, action) - Log HITL interaction
hitl_log() {
    local question="$1"
    local response="$2"
    local action="$3"

    _init_hitl_log

    local timestamp
    timestamp="$(_timestamp)"

    cat >> "$HITL_LOG" <<EOF
## Interaction at $timestamp

**Question**: $question

**Response**: $response

**Action**: $action

---

EOF

    log_debug "Logged HITL interaction to: $HITL_LOG"
}

# hitl_show_context(title, content) - Display context to user
hitl_show_context() {
    local title="$1"
    local content="$2"

    echo "" >&2
    echo -e "${COLOR_BLUE}━━━ $title ━━━${COLOR_RESET}" >&2
    echo "" >&2
    echo "$content" >&2
    echo "" >&2
}

# hitl_confirm_action(action_description) - Confirm before proceeding
hitl_confirm_action() {
    local action_description="$1"

    echo "" >&2
    echo -e "${COLOR_YELLOW}About to: $action_description${COLOR_RESET}" >&2
    echo "" >&2

    if hitl_prompt_yn "Proceed with this action?"; then
        log_info "User confirmed action: $action_description"
        return 0
    else
        log_warn "User rejected action: $action_description"
        return 1
    fi
}

# hitl_review_changes(files) - Show changes and confirm
hitl_review_changes() {
    local files=("$@")

    echo "" >&2
    echo -e "${COLOR_BLUE}━━━ Changes to Review ━━━${COLOR_RESET}" >&2
    echo "" >&2

    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "File: $file" >&2
            echo "" >&2
            if git diff --cached "$file" 2>/dev/null | head -50; then
                echo "" >&2
            else
                echo "No changes staged for this file" >&2
            fi
        fi
    done

    if hitl_prompt_yn "Approve these changes?"; then
        log_info "User approved changes"
        return 0
    else
        log_warn "User rejected changes"
        return 1
    fi
}

# hitl_select_option(prompt, options_array) - Select from multiple options
hitl_select_option() {
    local prompt="$1"
    shift
    local options=("$@")

    local formatted_options=""
    local i=1
    for option in "${options[@]}"; do
        formatted_options+="$i) $option\n"
        ((i++))
    done

    local response
    if ! response=$(hitl_prompt "$prompt" "selection" "$formatted_options"); then
        # Timeout - return first option
        echo "${options[0]}"
        return 0
    fi

    # Validate numeric input
    if [[ "$response" =~ ^[0-9]+$ ]] && [[ $response -ge 1 ]] && [[ $response -le ${#options[@]} ]]; then
        echo "${options[$((response - 1))]}"
        return 0
    else
        log_warn "Invalid selection: $response, using first option"
        echo "${options[0]}"
        return 0
    fi
}
