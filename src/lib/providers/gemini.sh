#!/bin/bash
# Gemini provider for spec-to-ship workflow
# Integrates with Google's Gemini CLI

# Register the provider
provider_gemini_register() {
    log_debug "Registering Gemini provider"
    
    # Check if gemini CLI is installed
    if ! command -v gemini &>/dev/null; then
        log_error "Gemini CLI not found. Install it with: npm install -g @google/gemini-cli"
        return 1
    fi
    
    log_debug "Gemini CLI found at: $(command -v gemini)"
    return 0
}

# Validate Gemini provider
provider_gemini_validate() {
    log_debug "Validating Gemini provider"
    
    # Check if CLI is installed
    if ! command -v gemini &>/dev/null; then
        log_error "Gemini CLI is not installed"
        return 1
    fi
    
    # Try to check if authenticated (gemini doesn't have a direct auth status command)
    # We'll check by running a simple command
    if ! timeout 5s gemini --version &>/dev/null; then
        log_warn "Gemini CLI may not be properly configured"
        return 1
    fi
    
    log_debug "Gemini provider validation successful"
    return 0
}

# List available Gemini models
provider_gemini_list_models() {
    echo "Available Gemini models:"
    echo "  gemini-3-pro-preview - High capability (latest, most capable)"
    echo "  gemini-1.5-flash - Medium capability (fast, efficient)"
    echo "  gemini-1.5-flash - Low capability (fastest, for quick tasks)"
    echo ""
    echo "Capability mappings:"
    echo "  High capability:   gemini-3-pro-preview"
    echo "  Medium capability: gemini-1.5-flash"
    echo "  Low capability:   gemini-1.5-flash"
}

# Map capability level to model name
provider_gemini_map_model() {
    local capability="$1"
    
    case "$capability" in
        high)
            echo "gemini-3-pro-preview"  # Full model name
            ;;
        medium)
            echo "gemini-2.5-flash"  # Use 2.5 instead of 1.5
            ;;
        low)
            echo "gemini-2.5-flash"  # Use 2.5-flash for low capability too
            ;;
        *)
            log_error "Unknown capability level for Gemini: $capability"
            return 1
            ;;
    esac
}

# Invoke Gemini with retry logic
provider_gemini_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Map model name if needed
    local model_name
    model_name="$(provider_gemini_map_model "$model")"
    
    log_info "Invoking Gemini ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"
    
    # Set model as environment variable to avoid interactive prompts
    export GEMINI_MODEL="$model_name"
    
    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi
    
    # Prepare gemini command
    # Don't use approval-mode yolo for programmatic use
    local gemini_cmd=(gemini --model "$model_name" --output-format text)
    
    # Disable any interactive prompts
    export GEMINI_AUTO_ANSWER="true"
    export GEMINI_DISABLE_INTERACTIVE="true"
    
    # Check if we should add the file as argument or stdin
    local file_size
    file_size=$(stat -c%s "$prompt_file" 2>/dev/null || echo "0")
    
    # For small files, include as argument, for large files use stdin
    if [[ $file_size -lt 1000 ]]; then
        # Small file - read content and pass as argument
        local prompt_content
        prompt_content="$(cat "$prompt_file")"
        
        # Invoke with retry - stdout captured by caller, let stderr pass through
        if _provider_gemini_retry_with_backoff "${gemini_cmd[@]}" "$prompt_content"; then
            return 0
        else
            local exit_code=$?
            log_error "Gemini invocation failed with exit code $exit_code"
            return $exit_code
        fi
    else
        # Large file - use stdin - stdout captured by caller, let stderr pass through
        if _provider_gemini_retry_with_backoff "${gemini_cmd[@]}" < "$prompt_file"; then
            return 0
        else
            local exit_code=$?
            log_error "Gemini invocation failed with exit code $exit_code"
            return $exit_code
        fi
    fi
}

# Retry with exponential backoff
_provider_gemini_retry_with_backoff() {
    local base_delay="${RETRY_BASE_DELAY:-2}"
    local max_attempts="${RETRY_MAX_ATTEMPTS:-3}"
    
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