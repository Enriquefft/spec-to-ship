#!/usr/bin/env bash
# src/lib/claude.sh - Claude CLI wrapper with retry logic

# Source common utilities
LIB_DIR="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"

# Validate Claude CLI is available
_check_claude_cli() {
    if ! command -v claude &> /dev/null; then
        die "Claude CLI not found. Please install from: https://github.com/anthropics/claude-code"
    fi
}

# _map_model_name(model) - Map model names to Claude CLI format
_map_model_name() {
    local model="$1"

    case "$model" in
        opus)
            echo "claude-opus-4-20250514"
            ;;
        sonnet)
            echo "claude-sonnet-4-5-20250929"
            ;;
        haiku)
            echo "claude-haiku-4-20250319"
            ;;
        *)
            log_warn "Unknown model: $model, using sonnet"
            echo "claude-sonnet-4-5-20250929"
            ;;
    esac
}

# _retry_with_backoff(command, args...) - Execute command with exponential backoff
_retry_with_backoff() {
    local max_attempts
    local base_delay
    max_attempts="$(config_get RETRY_MAX_ATTEMPTS)"
    base_delay="$(config_get RETRY_BASE_DELAY)"

    local attempt=1
    local delay="$base_delay"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts"

        if "$@"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_warn "Attempt $attempt failed, retrying in ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi

        ((attempt++))
    done

    log_error "All $max_attempts attempts failed"
    return 1
}

# claude_invoke(model, prompt_file) - Invoke Claude with specified model and prompt
claude_invoke() {
    local model="$1"
    local prompt_file="$2"

    _check_claude_cli

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    local model_name
    model_name="$(_map_model_name "$model")"

    log_info "Invoking Claude ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"

    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi

    local output
    local exit_code

    # Invoke Claude with retry
    if output=$(_retry_with_backoff claude --model "$model_name" < "$prompt_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    # Log output
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Claude response:"
        log_debug "$output"
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Claude invocation failed"
        log_error "$output"
        return 1
    fi

    echo "$output"
    return 0
}

# claude_invoke_with_input(model, prompt_file, input) - Invoke Claude with prompt and stdin
claude_invoke_with_input() {
    local model="$1"
    local prompt_file="$2"
    local input="$3"

    _check_claude_cli

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    local model_name
    model_name="$(_map_model_name "$model")"

    log_info "Invoking Claude ($model) with prompt and input: $prompt_file"
    log_debug "Model ID: $model_name"

    # Create temporary combined prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "$input"
    } > "$temp_prompt"

    # Log combined prompt if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Combined prompt:"
        log_debug "$(cat "$temp_prompt")"
    fi

    local output
    local exit_code

    # Invoke Claude with retry
    if output=$(_retry_with_backoff claude --model "$model_name" < "$temp_prompt" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Log output
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Claude response:"
        log_debug "$output"
    fi

    if [[ $exit_code -ne 0 ]]; then
        log_error "Claude invocation failed"
        log_error "$output"
        return 1
    fi

    echo "$output"
    return 0
}

# claude_stream(model, prompt_file) - Invoke Claude with streaming output
claude_stream() {
    local model="$1"
    local prompt_file="$2"

    _check_claude_cli

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    local model_name
    model_name="$(_map_model_name "$model")"

    log_info "Invoking Claude ($model) with streaming: $prompt_file"
    log_debug "Model ID: $model_name"

    # Stream directly to stdout/stderr
    if ! claude --model "$model_name" < "$prompt_file"; then
        log_error "Claude streaming invocation failed"
        return 1
    fi

    return 0
}

# claude_invoke_interactive(model, system_prompt) - Start interactive Claude session
claude_invoke_interactive() {
    local model="$1"
    local system_prompt="${2:-}"

    _check_claude_cli

    local model_name
    model_name="$(_map_model_name "$model")"

    log_info "Starting interactive Claude session ($model)"
    log_debug "Model ID: $model_name"

    local claude_args=("--model" "$model_name")

    if [[ -n "$system_prompt" ]]; then
        claude_args+=("--system" "$system_prompt")
    fi

    # Start interactive session
    if ! claude "${claude_args[@]}"; then
        log_error "Interactive Claude session failed"
        return 1
    fi

    return 0
}

# claude_with_context(model, prompt_file, context_files...) - Invoke with multiple context files
claude_with_context() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local context_files=("$@")

    _check_claude_cli

    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi

    # Validate all context files exist
    for ctx_file in "${context_files[@]}"; do
        if [[ ! -f "$ctx_file" ]]; then
            log_error "Context file not found: $ctx_file"
            return 1
        fi
    done

    local model_name
    model_name="$(_map_model_name "$model")"

    log_info "Invoking Claude ($model) with ${#context_files[@]} context files"
    log_debug "Model ID: $model_name"

    # Create combined prompt with context
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# Context Files"
        echo ""

        for ctx_file in "${context_files[@]}"; do
            echo "## File: $ctx_file"
            echo ""
            echo '```'
            cat "$ctx_file"
            echo '```'
            echo ""
        done
    } > "$temp_prompt"

    # Invoke Claude
    local output
    if output=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        echo "$output"
        return 0
    else
        rm -f "$temp_prompt"
        trap - EXIT
        return 1
    fi
}
