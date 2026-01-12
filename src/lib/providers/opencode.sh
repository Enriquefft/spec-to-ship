#!/bin/bash
# src/lib/providers/opencode.sh - OpenCode provider implementation

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Set provider description
PROVIDER_DESCRIPTION="OpenCode - Multi-provider AI assistant"

# Validate OpenCode is available
provider_opencode_validate() {
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
provider_opencode_map_model() {
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
_provider_opencode_retry_with_backoff() {
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
provider_opencode_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_map_model "$model")"
    
log_info "Invoking OpenCode ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi
    
# Check file size - if small, include as message, otherwise attach as file
    local file_size
    file_size=$(stat -c%s "$prompt_file" 2>/dev/null || stat -f%z "$prompt_file" 2>/dev/null || echo "0")
    
    local opencode_cmd
    if [[ $file_size -lt 1000 ]]; then
        # Small file - include content as message
        local message
        message="$(cat "$prompt_file")"
        opencode_cmd=(opencode run "$message" --model "$model_name" --format default)
    else
        # Large file - use attachment approach
        local opencode_cmd=(opencode run "Please respond to the content in the attached file." --model "$model_name" --format default)
        
        # Add prompt file as attachment
        opencode_cmd+=(-f "$prompt_file")
    fi
    
    # Add context files if specified in extra args
    local context_files=()
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == --context* ]]; then
            # Extract context files
            local files="${arg#--context=}"
            IFS=',' read -ra context_files <<< "$files"
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
    
    # Add prompt file for large files (already added above)
    if [[ $file_size -ge 1000 ]]; then
        # Already added above
        :
    fi
    
    # Add any extra arguments (excluding context)
    for arg in "${extra_args[@]}"; do
        if [[ ! "$arg" =~ ^--context= ]]; then
            # Only add if it starts with -
            if [[ "$arg" =~ ^- ]]; then
                opencode_cmd+=("$arg")
            fi
        fi
    done
    
    # Invoke OpenCode with retry
    local output
    local exit_code
    
    if output=$(_provider_opencode_retry_with_backoff "${opencode_cmd[@]}" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Echo output (regardless of exit code)
    echo "$output"
    
    # Log errors if needed
    if [[ $exit_code -ne 0 ]]; then
        log_error "OpenCode invocation failed with exit code $exit_code"
        log_error "Output: $output"
    fi
    
    return $exit_code
}

# OpenCode provider stream implementation
provider_opencode_stream() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_map_model "$model")"
    
    log_info "Streaming from OpenCode ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Prepare opencode command for streaming
    local message="Please respond to the content in the attached file."
    local opencode_cmd=(opencode run "$message" --model "$model_name" --format default)
    
    # Add context files if specified
    local context_files=()
    for arg in "${extra_args[@]}"; do
        if [[ "$arg" == --context* ]]; then
            local files="${arg#--context=}"
            IFS=',' read -ra context_files <<< "$files"
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
    
    # Filter streaming-specific args (excluding context)
    for arg in "${extra_args[@]}"; do
        if [[ ! "$arg" =~ ^--context= ]] && [[ "$arg" =~ ^- ]]; then
            opencode_cmd+=("$arg")
        fi
    done
    
    # Stream directly to stdout
    _provider_opencode_retry_with_backoff "${opencode_cmd[@]}"
}

# OpenCode provider with context files
provider_opencode_with_context() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local context_files=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_map_model "$model")"
    
    log_info "Invoking OpenCode with context files"
    log_debug "Model: $model_name"
    log_debug "Context files: ${context_files[*]}"
    
    # Validate context files
    for file in "${context_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Context file not found: $file"
            return 1
        fi
    done
    
    # Prepare opencode command with context files
    local message="Please respond to the content in the attached files."
    local opencode_cmd=(opencode run "$message" --model "$model_name" --format default)
    
    # Add file arguments for each context file
    for file in "${context_files[@]}"; do
        opencode_cmd+=(-f "$file")
    done
    
    # Add the prompt file
    opencode_cmd+=(-f "$prompt_file")
    
    # Invoke with context
    _provider_opencode_retry_with_backoff "${opencode_cmd[@]}"
}

# OpenCode provider interactive session
provider_opencode_interactive() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_map_model "$model")"
    
    log_info "Starting OpenCode interactive session ($model)"
    
    # Prepare opencode command for interactive mode
    local opencode_cmd=(opencode --model "$model_name")
    
    # Add any extra arguments
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        opencode_cmd+=("${extra_args[@]}")
    fi
    
    # Check if prompt file has content
    if [[ -s "$prompt_file" ]]; then
        # Send initial message and start interactive mode
        {
            cat "$prompt_file"
            echo ""  # Ensure newline after prompt
        } | _provider_opencode_retry_with_backoff "${opencode_cmd[@]}"
    else
        # Just start interactive mode
        _provider_opencode_retry_with_backoff "${opencode_cmd[@]}"
    fi
}

# List available OpenCode models
provider_opencode_list_models() {
    echo "Available OpenCode models:"
    
    # Get models from opencode
    if opencode models 2>/dev/null; then
        echo ""
        echo "Capability mappings:"
        # Use configuration values
        local high_model medium_model low_model
        high_model="$(config_get "PROVIDER_OPENCODE_MODEL_HIGH")"
        medium_model="$(config_get "PROVIDER_OPENCODE_MODEL_MEDIUM")"
        low_model="$(config_get "PROVIDER_OPENCODE_MODEL_LOW")"
        
        echo "  High capability:   ${high_model:-opencode/grok-code}"
        echo "  Medium capability: ${medium_model:-opencode/gpt-5-nano}"
        echo "  Low capability:   ${low_model:-opencode/glm-4.7-free}"
        
        # Show any additional models
        local extra_model
        extra_model="$(config_get "PROVIDER_OPENCODE_MODEL_EXTRA")"
        if [[ -n "$extra_model" ]]; then
            echo "  Extra model:      $extra_model"
        fi
    else
        echo "  opencode/grok-code - High capability"
        echo "  opencode/gpt-5-nano - Medium capability"
        echo "  opencode/glm-4.7-free - Low capability"
        echo "  opencode/big-pickle - Alternative model"
        echo "  opencode/minimax-m2.1-free - Free model"
    fi
}

# OpenCode provider with input from stdin alternative using file
provider_opencode_invoke_with_input() {
    local model="$1"
    local prompt_file="$2"
    local input_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Map model name
    local model_name
    model_name="$(provider_opencode_map_model "$model")"
    
    log_info "Invoking OpenCode with input from $input_file"
    
    # Combine prompt and input into a temp file
    local temp_prompt
    temp_prompt="$(mktemp)"
    
    {
        cat "$prompt_file"
        echo ""
        echo "--- Input ---"
        cat "$input_file"
    } > "$temp_prompt"
    
    # Invoke with combined prompt
    provider_opencode_invoke "$model_name" "$temp_prompt" "${extra_args[@]}"
    local result=$?
    
    # Cleanup
    rm -f "$temp_prompt"
    
    return $result
}

# Initialize provider when loaded
provider_opencode_init() {
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
provider_opencode_init
