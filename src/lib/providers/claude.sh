#!/usr/bin/env bash
# src/lib/providers/claude.sh - Claude provider implementation

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Set provider description
PROVIDER_DESCRIPTION="Anthropic Claude Code CLI"

# Validate Claude CLI is available
provider_claude_validate() {
    if ! command -v claude &> /dev/null; then
        log_error "Claude CLI not found. Please install from: https://github.com/anthropics/claude-code"
        return 1
    fi
    
    # Check if API key is configured
    if ! claude --help &> /dev/null; then
        log_warn "Claude CLI may not be properly configured"
    fi
    
    return 0
}

# Map model names to Claude CLI format
provider_claude_map_model() {
    local model="$1"
    
    case "$model" in
        opus|claude-opus|claude-opus-*)
            echo "claude-opus-4-20250514"
            ;;
        sonnet|claude-sonnet|claude-sonnet-*)
            echo "claude-sonnet-4-5-20250929"
            ;;
        haiku|claude-haiku|claude-haiku-*)
            echo "claude-haiku-4-20250319"
            ;;
        claude-*)
            # Already in Claude format
            echo "$model"
            ;;
        *)
            log_warn "Unknown Claude model: $model, using sonnet"
            echo "claude-sonnet-4-5-20250929"
            ;;
    esac
}

# Execute command with exponential backoff retry
_provider_claude_retry_with_backoff() {
    local max_attempts
    local base_delay
    max_attempts="$(config_get "RETRY_MAX_ATTEMPTS")"
    base_delay="$(config_get "RETRY_BASE_DELAY")"
    
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

# Claude provider invoke implementation
provider_claude_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_claude_map_model "$model")"
    
    log_info "Invoking Claude ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi
    
    # Prepare claude command
    local claude_cmd=(claude --print --model "$model_name")
    
    # Add any extra arguments
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        claude_cmd+=("${extra_args[@]}")
    fi
    
    # Invoke Claude with retry
    local output
    local exit_code
    
    if output=$(_provider_claude_retry_with_backoff "${claude_cmd[@]}" < "$prompt_file" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Echo output (regardless of exit code)
    echo "$output"
    
    # Log errors if needed
    if [[ $exit_code -ne 0 ]]; then
        log_error "Claude invocation failed with exit code $exit_code"
        log_error "Output: $output"
    fi
    
    return $exit_code
}

# Claude provider stream implementation
provider_claude_stream() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_claude_map_model "$model")"
    
    log_info "Streaming from Claude ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Prepare claude command for streaming
    local claude_cmd=(claude --model "$model_name")
    
    # Add any extra arguments (excluding --print for streaming)
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        # Filter out --print if present
        for arg in "${extra_args[@]}"; do
            if [[ "$arg" != "--print" ]]; then
                claude_cmd+=("$arg")
            fi
        done
    fi
    
    # Stream directly to stdout
    _provider_claude_retry_with_backoff "${claude_cmd[@]}" < "$prompt_file"
}

# Claude provider with context files
provider_claude_with_context() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local context_files=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_claude_map_model "$model")"
    
    log_info "Invoking Claude with context files"
    log_debug "Model: $model_name"
    log_debug "Context files: ${context_files[*]}"
    
    # Validate context files
    for file in "${context_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Context file not found: $file"
            return 1
        fi
    done
    
    # Combine prompt and context files
    local temp_prompt
    temp_prompt="$(mktemp)"
    
    # Add context files first
    for file in "${context_files[@]}"; do
        echo "--- Context: $file ---" >> "$temp_prompt"
        cat "$file" >> "$temp_prompt"
        echo "" >> "$temp_prompt"
    done
    
    # Add main prompt
    echo "--- Main Prompt ---" >> "$temp_prompt"
    cat "$prompt_file" >> "$temp_prompt"
    
    # Invoke with combined prompt
    provider_claude_invoke "$model_name" "$temp_prompt"
    local result=$?
    
    # Cleanup
    rm -f "$temp_prompt"
    
    return $result
}

# Claude provider interactive session
provider_claude_interactive() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_claude_map_model "$model")"
    
    log_info "Starting interactive Claude session ($model)"
    
    # Prepare claude command for interactive mode
    local claude_cmd=(claude --model "$model_name")
    
    # Add any extra arguments
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        claude_cmd+=("${extra_args[@]}")
    fi
    
    # Check if prompt file has content
    if [[ -s "$prompt_file" ]]; then
        # Send initial message and start interactive mode
        {
            cat "$prompt_file"
            echo ""  # Ensure newline after prompt
        } | _provider_claude_retry_with_backoff "${claude_cmd[@]}"
    else
        # Just start interactive mode
        _provider_claude_retry_with_backoff "${claude_cmd[@]}"
    fi
}

# List available Claude models
provider_claude_list_models() {
    echo "Available Claude models:"
    echo "  opus (claude-opus-4-20250514) - Most capable model"
    echo "  sonnet (claude-sonnet-4-5-20250929) - Balanced model"
    echo "  haiku (claude-haiku-4-20250319) - Fast model"
}

# Claude provider with input from stdin
provider_claude_invoke_with_input() {
    local model="$1"
    local prompt_file="$2"
    local input_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_claude_map_model "$model")"
    
    log_info "Invoking Claude with input from $input_file"
    
    # Combine prompt and input
    local temp_prompt
    temp_prompt="$(mktemp)"
    
    cat "$prompt_file" > "$temp_prompt"
    echo "" >> "$temp_prompt"
    cat "$input_file" >> "$temp_prompt"
    
    # Invoke with combined prompt
    provider_claude_invoke "$model_name" "$temp_prompt" "${extra_args[@]}"
    local result=$?
    
    # Cleanup
    rm -f "$temp_prompt"
    
    return $result
}

# Initialize provider when loaded
provider_claude_init() {
    # Set default model mappings if not configured
    if ! config_get "PROVIDER_CLAUDE_MODEL_HIGH" >/dev/null; then
        config_set "PROVIDER_CLAUDE_MODEL_HIGH" "claude-opus-4-20250514"
    fi
    
    if ! config_get "PROVIDER_CLAUDE_MODEL_MEDIUM" >/dev/null; then
        config_set "PROVIDER_CLAUDE_MODEL_MEDIUM" "claude-sonnet-4-5-20250929"
    fi
    
    if ! config_get "PROVIDER_CLAUDE_MODEL_LOW" >/dev/null; then
        config_set "PROVIDER_CLAUDE_MODEL_LOW" "claude-haiku-4-20250319"
    fi
}

# Auto-initialize
provider_claude_init