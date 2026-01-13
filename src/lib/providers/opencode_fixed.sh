#!/bin/bash
# src/lib/providers/opencode_fixed.sh - OpenCode provider implementation with proper file handling

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Set provider description
PROVIDER_DESCRIPTION="OpenCode - Multi-provider AI assistant (fixed version)"

# Validate OpenCode is available
provider_opencode_fixed_validate() {
    if ! command -v opencode &> /dev/null; then
        log_error "OpenCode not found. Please install from: https://opencode.ai"
        return 1
    fi
    
    # Check if opencode is authenticated
    if ! opencode auth status &> /dev/null; then
        log_warn "OpenCode may not be authenticated. Run 'opencode auth' to configure."
    fi
    
    return 0
}

# Map model names to OpenCode format
provider_opencode_fixed_map_model() {
    local model="$1"
    
    case "$model" in
        opencode/*)
            # Already in OpenCode format
            echo "$model"
            ;;
        claude-opus-*)
            echo "opencode/${model#claude-}"
            ;;
        opus|high)
            echo "opencode/grok-code"
            ;;
        sonnet|medium)
            echo "opencode/gpt-5-nano"
            ;;
        haiku|low)
            echo "opencode/glm-4.7-free"
            ;;
        *)
            log_warn "Unknown OpenCode model: $model, using opencode/gpt-5-nano"
            echo "opencode/gpt-5-nano"
            ;;
    esac
}

# Execute command with exponential backoff retry
_provider_opencode_fixed_retry_with_backoff() {
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

# OpenCode provider invoke implementation
provider_opencode_fixed_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_fixed_map_model "$model")"
    
    log_info "Invoking OpenCode ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi
    
    # Prepare opencode command
    # Message comes first, then options, then files
    local opencode_cmd=(opencode run --model "$model_name" --format default)
    
    # Create a message to prompt the AI to read the file
    local message="Please respond to the content in the attached file."
    
    # Add context files if specified in extra args
    local context_files=()
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == --context* ]]; then
            # Extract context files
            local files="${arg#--context=}"
            IFS=',' read -ra context_files <<< "$files"
        fi
    done
    
    # Add any extra arguments that are not context-related
    for arg in "${extra_args[@]}"; do
        if [[ ! "$arg" =~ ^--context= ]]; then
            # Check if it's a valid option
            if [[ "$arg" =~ ^- ]]; then
                opencode_cmd+=("$arg")
            fi
        fi
    done
    
    # Add file arguments for context files
    if [[ ${#context_files[@]} -gt 0 ]]; then
        for file in "${context_files[@]}"; do
            if [[ -f "$file" ]]; then
                opencode_cmd+=(-f "$file")
            else
                log_warn "Context file not found: $file"
            fi
        done
    fi
    
    # Add the prompt file
    opencode_cmd+=(-f "$prompt_file")
    
    # Invoke OpenCode with retry - stdout captured by caller, let stderr pass through
    if _provider_opencode_fixed_retry_with_backoff "${opencode_cmd[@]}" "$message"; then
        return 0
    else
        local exit_code=$?
        log_error "OpenCode invocation failed with exit code $exit_code"
        return $exit_code
    fi
}

# OpenCode provider stream implementation
provider_opencode_fixed_stream() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_fixed_map_model "$model")"
    
    log_info "Streaming from OpenCode ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Prepare opencode command for streaming
    local opencode_cmd=(opencode run --model "$model_name" --format default)
    
    # Add any valid extra arguments
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" =~ ^- ]]; then
            opencode_cmd+=("$arg")
        fi
    done
    
    # Add the prompt file
    opencode_cmd+=(-f "$prompt_file")
    
    # Stream directly to stdout
    _provider_opencode_fixed_retry_with_backoff "${opencode_cmd[@]}" "Please respond to the content in the attached file."
}

# Initialize provider when loaded
provider_opencode_fixed_init() {
    # Set default model mappings if not configured
    if ! config_get "PROVIDER_OPENCODE_MODEL_HIGH" >/dev/null; then
        config_set "PROVIDER_OPENCODE_MODEL_HIGH" "opencode/grok-code"
    fi
    
    if ! config_get "PROVIDER_OPENCODE_MODEL_MEDIUM" >/dev/null; then
        config_set "PROVIDER_OPENCODE_MODEL_MEDIUM" "opencode/gpt-5-nano"
    fi
    
    if ! config_get "PROVIDER_OPENCODE_MODEL_LOW" >/dev/null; then
        config_set "PROVIDER_OPENCODE_MODEL_LOW" "opencode/glm-4.7-free"
    fi
}

# Auto-initialize
provider_opencode_fixed_init
