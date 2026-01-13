#!/usr/bin/env bash
# src/lib/interaction.sh - Unified User Interaction Library
# Combines HITL (Human-in-the-Loop) functionality with Smart Questions UI.
# Handles all user interaction: prompts, selections, confirmations, and logging.
#
# This file consolidates the former hitl.sh functionality into a single module.

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"

# ==============================================================================
# Module State (initialized once)
# ==============================================================================

# HITL log file location (initialized lazily)
_INTERACTION_HITL_LOG=""
_INTERACTION_INITIALIZED=false

# ==============================================================================
# Internal Helpers
# ==============================================================================

# _interaction_ensure_init() - Initialize module state once
_interaction_ensure_init() {
    [[ "$_INTERACTION_INITIALIZED" == "true" ]] && return 0

    local git_root
    if git_root="$(get_git_root 2>/dev/null)"; then
        _INTERACTION_HITL_LOG="${git_root}/docs/hitl-log.md"
    else
        _INTERACTION_HITL_LOG="docs/hitl-log.md"
    fi

    # Create docs directory if needed
    ensure_dir "$(dirname "$_INTERACTION_HITL_LOG")" 2>/dev/null || true

    # Initialize log file if it doesn't exist
    if [[ ! -f "$_INTERACTION_HITL_LOG" ]]; then
        cat > "$_INTERACTION_HITL_LOG" <<'EOF'
# Human-in-the-Loop Interaction Log

This file records all HITL interactions during the workflow execution.

---

EOF
    fi

    _INTERACTION_INITIALIZED=true
}

# _parse_timeout(timeout_str) - Parse timeout string to seconds
# Input: "5m", "30s", "1h", or raw seconds
# Output: Integer seconds
_parse_timeout() {
    local timeout="$1"

    case "$timeout" in
        *s) echo "${timeout%s}" ;;
        *m) echo "$((${timeout%m} * 60))" ;;
        *h) echo "$((${timeout%h} * 3600))" ;;
        *)  echo "$timeout" ;;
    esac
}

# _handle_recommendation(input, rec_id) - Map aliases to recommendation
# Returns: Mapped input or original
_handle_recommendation() {
    local input="$1"
    local rec_id="$2"

    case "${input,,}" in
        y|yes|rec|recommended|suggested)
            if [[ -n "$rec_id" ]]; then
                echo "$rec_id"
                log_debug "User accepted recommendation: $rec_id"
                return 0
            fi
            ;;
    esac

    echo "$input"
}

# ==============================================================================
# HITL Configuration Functions
# ==============================================================================

# hitl_is_enabled() - Check if HITL is enabled
hitl_is_enabled() {
    local enabled
    enabled="$(config_get HITL_ENABLED)"
    [[ "$enabled" == "true" ]]
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
            [[ "$trigger_type" == "task" ]] && return 0
            ;;
        milestone)
            [[ "$trigger_type" == "milestone" ]] && return 0
            ;;
        uncertain)
            [[ "$trigger_type" == "uncertain" ]] && return 0
            ;;
        every:*)
            local interval="${mode#every:}"
            if [[ "$trigger_type" == "iteration" && $((iteration % interval)) -eq 0 ]]; then
                return 0
            fi
            ;;
    esac

    return 1
}

# ==============================================================================
# Logging Functions
# ==============================================================================

# hitl_log(question, response, action) - Log HITL interaction
hitl_log() {
    local question="$1"
    local response="$2"
    local action="$3"

    _interaction_ensure_init

    local timestamp
    timestamp="$(_timestamp)"

    cat >> "$_INTERACTION_HITL_LOG" <<EOF
## Interaction at $timestamp

**Question**: $question

**Response**: $response

**Action**: $action

---

EOF

    log_debug "Logged HITL interaction to: $_INTERACTION_HITL_LOG"
}

# Alias for backward compatibility
_init_hitl_log() {
    _interaction_ensure_init
}

# ==============================================================================
# Display Functions
# ==============================================================================

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

# interaction_render_table(options_list, include_short)
# Renders options in a markdown-style table.
# Format: "A|Description" per line
interaction_render_table() {
    local options_list="$1"
    local include_short="${2:-true}"

    echo "" >&2
    echo "| Option | Description |" >&2
    echo "|--------|-------------|" >&2

    # Render each option row
    while IFS='|' read -r id desc; do
        if [[ -n "$id" ]]; then
            printf "| %s | %s |\n" "$id" "$desc" >&2
        fi
    done <<< "$options_list"

    # Add Short option if requested
    if [[ "$include_short" == "true" ]]; then
        echo "| Short | Provide a different short answer (<=5 words) |" >&2
    fi

    echo "" >&2
}

# ==============================================================================
# Prompt Functions
# ==============================================================================

# hitl_prompt(question, type, options) - Prompt user for input
hitl_prompt() {
    local question="$1"
    local type="${2:-clarification}"
    local options="${3:-}"

    _interaction_ensure_init

    local timeout
    timeout="$(config_get HITL_TIMEOUT 2>/dev/null || echo "")"

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
        local timeout_seconds
        timeout_seconds="$(_parse_timeout "$timeout")"

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

# ==============================================================================
# Selection Functions
# ==============================================================================

# hitl_select_option(prompt, recommended, reasoning, options_array...) - Select from multiple options
hitl_select_option() {
    local prompt="$1"
    local recommended="$2"
    local reasoning="${3:-Best choice for most use cases}"
    shift 3
    local options=("$@")

    _interaction_ensure_init

    # Header
    echo "" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}SELECTION NEEDED${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2
    echo -e "${COLOR_BOLD}$prompt${COLOR_RESET}" >&2
    echo "" >&2

    # Recommendation (Prominent at top)
    if [[ -n "$recommended" && "$recommended" =~ ^[0-9]+$ ]]; then
        local rec_idx=$((recommended - 1))
        if [[ $rec_idx -ge 0 && $rec_idx -lt ${#options[@]} ]]; then
            echo -e "${COLOR_GREEN}**Recommended:** Option [$recommended] (${options[$rec_idx]}) - $reasoning${COLOR_RESET}" >&2
            echo "" >&2
        fi
    fi

    # Options Table
    echo "| Option | Description |" >&2
    echo "|--------|-------------|" >&2
    local i=1
    for option in "${options[@]}"; do
        echo "| $i | $option |" >&2
        ((i++))
    done
    echo "| Short | Provide a different short answer (<=5 words) |" >&2
    echo "" >&2

    # Instructions
    echo "You can reply with the option number (e.g., \"1\"), accept the recommendation" >&2
    echo "by saying \"yes\" or \"recommended\", or provide your own short answer." >&2
    echo "" >&2

    # Timeout display
    local timeout
    timeout="$(config_get HITL_TIMEOUT 2>/dev/null || echo "")"
    if [[ -n "$timeout" ]]; then
        echo -e "${COLOR_GRAY}(Auto-continue in $timeout if no response)${COLOR_RESET}" >&2
    fi

    echo -n "Your choice: " >&2

    # Read with timeout
    local response
    if [[ -n "$timeout" ]]; then
        local timeout_seconds
        timeout_seconds="$(_parse_timeout "$timeout")"

        if ! read -r -t "$timeout_seconds" response; then
            echo "" >&2
            log_warn "HITL timeout reached, using recommendation or first option"
            if [[ -n "$recommended" && "$recommended" =~ ^[0-9]+$ ]]; then
                response="$recommended"
            else
                response="1"
            fi
        fi
    else
        read -r response
    fi

    # Process aliases
    response="$(_handle_recommendation "$response" "$recommended")"

    # Log interaction
    hitl_log "$prompt" "$response" "Selection Response"

    # Validate and return
    if [[ "$response" =~ ^[0-9]+$ ]] && [[ $response -ge 1 ]] && [[ $response -le ${#options[@]} ]]; then
        echo "${options[$((response - 1))]}"
        return 0
    else
        # Custom answer
        if [[ -n "$response" ]]; then
            echo "$response"
            return 0
        else
            log_warn "Invalid selection, using first option"
            echo "${options[0]}"
            return 0
        fi
    fi
}

# interaction_present_smart_question(question, rec_id, rec_reasoning, options_list, include_short)
# Main entry point for the "Smart Question" UI following speckit.clarify pattern.
interaction_present_smart_question() {
    local question="$1"
    local rec_id="$2"
    local rec_reasoning="$3"
    local options_list="$4"
    local include_short="${5:-true}"

    _interaction_ensure_init

    # Header
    echo "" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}CLARIFICATION NEEDED${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2

    # The Question
    echo -e "${COLOR_BOLD}$question${COLOR_RESET}" >&2
    echo "" >&2

    # Recommendation (Prominent at top)
    if [[ -n "$rec_id" && -n "$rec_reasoning" ]]; then
        echo -e "${COLOR_GREEN}**Recommended:** Option [$rec_id] - $rec_reasoning${COLOR_RESET}" >&2
        echo "" >&2
    fi

    # Options Table
    interaction_render_table "$options_list" "$include_short"

    # Instructions
    echo "You can reply with the option letter (e.g., \"A\"), accept the recommendation" >&2
    echo "by saying \"yes\" or \"recommended\", or provide your own short answer." >&2
    echo "" >&2

    # Show default hint if recommendation exists
    local prompt_text="Your choice"
    if [[ -n "$rec_id" ]]; then
        prompt_text="Your choice (default: $rec_id)"
    fi
    echo -n "$prompt_text: " >&2

    # Capture Input
    local user_input
    read -r user_input

    # If user just pressed Enter and we have a recommendation, use it as default
    if [[ -z "$user_input" && -n "$rec_id" ]]; then
        user_input="$rec_id"
    fi

    # Process Input (Map aliases to recommendation)
    local final_answer
    final_answer="$(_handle_recommendation "$user_input" "$rec_id")"

    # Log interaction
    hitl_log "$question" "$final_answer" "Smart Question Response"

    # Return answer
    echo "$final_answer"
}

# interaction_present_short_answer(question, suggested_answer, suggested_reasoning)
# Present a short-answer question with a suggested answer.
interaction_present_short_answer() {
    local question="$1"
    local suggested_answer="$2"
    local suggested_reasoning="$3"

    _interaction_ensure_init

    # Header
    echo "" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}CLARIFICATION NEEDED${COLOR_RESET}" >&2
    echo -e "${COLOR_YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${COLOR_RESET}" >&2
    echo "" >&2

    # The Question
    echo -e "${COLOR_BOLD}$question${COLOR_RESET}" >&2
    echo "" >&2

    # Suggested Answer
    if [[ -n "$suggested_answer" ]]; then
        echo -e "${COLOR_GREEN}**Suggested:** $suggested_answer - $suggested_reasoning${COLOR_RESET}" >&2
        echo "" >&2
    fi

    # Instructions
    echo "Format: Short answer (<=5 words). You can accept the suggestion by saying" >&2
    echo "\"yes\" or \"suggested\", or provide your own answer." >&2
    echo "" >&2
    echo -n "Your answer: " >&2

    # Capture Input
    local user_input
    read -r user_input

    # Process Input
    local final_answer
    final_answer="$(_handle_recommendation "$user_input" "$suggested_answer")"

    # Log interaction
    hitl_log "$question" "$final_answer" "Short Answer Response"

    # Return answer
    echo "$final_answer"
}

# ==============================================================================
# Review Functions
# ==============================================================================

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

# ==============================================================================
# Parsing Helper
# ==============================================================================

# interaction_extract_tag(content, tag) - Extract content between <tag> and </tag>
interaction_extract_tag() {
    local content="$1"
    local tag="$2"

    # Use sed for portability (grep -P not available everywhere)
    echo "$content" | sed -n "s/.*<${tag}>\(.*\)<\/${tag}>.*/\1/p" | head -1
}
