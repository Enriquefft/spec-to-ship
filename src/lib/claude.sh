#!/usr/bin/env bash
# src/lib/claude.sh - Backward compatibility wrapper for Claude provider

# Source provider system
# shellcheck source=src/lib/provider.sh
source "${LIB_DIR}/provider.sh"

# Backward compatibility functions
claude_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Log deprecation warning
    log_warn "claude_invoke() is deprecated. Use provider_invoke() instead."
    
    # Detect provider from model or use default
    local provider
    if provider="$(provider_detect_from_model "$model")"; then
        # Use provider abstraction
        provider_invoke "$provider" "$model" "$prompt_file" "${extra_args[@]}"
    else
        # Fallback to legacy model mapping
        local resolved_model
        if resolved_model="$(provider_map_legacy_model "$model")"; then
            provider_invoke "claude" "$resolved_model" "$prompt_file" "${extra_args[@]}"
        else
            log_error "Failed to resolve model: $model"
            return 1
        fi
    fi
}

claude_stream() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Log deprecation warning
    log_warn "claude_stream() is deprecated. Use provider_stream() instead."
    
    # Detect provider from model or use default
    local provider
    if provider="$(provider_detect_from_model "$model")"; then
        provider_stream "$provider" "$model" "$prompt_file" "${extra_args[@]}"
    else
        # Fallback to legacy model mapping
        local resolved_model
        if resolved_model="$(provider_map_legacy_model "$model")"; then
            provider_stream "claude" "$resolved_model" "$prompt_file" "${extra_args[@]}"
        else
            log_error "Failed to resolve model: $model"
            return 1
        fi
    fi
}

claude_invoke_with_input() {
    local model="$1"
    local prompt_file="$2"
    local input_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Log deprecation warning
    log_warn "claude_invoke_with_input() is deprecated. Use provider_invoke() instead."
    
    # Combine prompt and input into a temporary file
    local temp_prompt
    temp_prompt="$(mktemp)"
    
    {
        cat "$prompt_file"
        echo ""
        echo "--- Input ---"
        cat "$input_file"
    } > "$temp_prompt"
    
    # Use abstraction
    if [[ "$model" =~ ^claude- ]]; then
        claude_invoke "$model" "$temp_prompt" "${extra_args[@]}"
    else
        claude_invoke "$model" "$temp_prompt" "${extra_args[@]}"
    fi
    
    local result=$?
    
    # Cleanup
    rm -f "$temp_prompt"
    
    return $result
}

claude_invoke_interactive() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")
    
    # Log deprecation warning
    log_warn "claude_invoke_interactive() is deprecated. Use provider-specific interactive functions."
    
    # Load claude provider directly for interactive mode
    if ! provider_load "claude"; then
        log_error "Failed to load claude provider"
        return 1
    fi
    
    # Call provider's interactive function
    provider_claude_interactive "$model" "$prompt_file" "${extra_args[@]}"
}

claude_with_context() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local context_files=("$@")
    
    # Log deprecation warning
    log_warn "claude_with_context() is deprecated. Use provider-specific context functions."
    
    # Load claude provider
    if ! provider_load "claude"; then
        log_error "Failed to load claude provider"
        return 1
    fi
    
    # Call provider's context function
    provider_claude_with_context "$model" "$prompt_file" "${context_files[@]}"
}

# Export legacy functions for backward compatibility
export -f claude_invoke claude_stream claude_invoke_with_input claude_invoke_interactive claude_with_context