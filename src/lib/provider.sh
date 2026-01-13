#!/usr/bin/env bash
# src/lib/provider.sh - Provider abstraction layer for AI models

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=src/lib/spinner.sh
source "${LIB_DIR}/spinner.sh"
# shellcheck source=src/lib/activity.sh
source "${LIB_DIR}/activity.sh"

# Load configuration
config_load

# Provider registry
declare -A PROVIDER_REGISTRY
declare -A PROVIDER_DESCRIPTIONS

# Register a provider
provider_register() {
    local name="$1"
    local script="$2"
    local description="${3:-}"
    
    PROVIDER_REGISTRY["$name"]="$script"
    PROVIDER_DESCRIPTIONS["$name"]="$description"
    
    log_debug "Registered provider: $name ($script)"
}

# List all registered providers
provider_list() {
    for name in "${!PROVIDER_REGISTRY[@]}"; do
        echo "$name: ${PROVIDER_DESCRIPTIONS[$name]:-}"
    done
}

# Get provider script path
provider_get_script() {
    local name="$1"
    echo "${PROVIDER_REGISTRY[$name]:-}"
}

# Check if provider is registered
provider_is_registered() {
    local name="$1"
    [[ -n "${PROVIDER_REGISTRY[$name]:-}" ]]
}

# Load provider script
provider_load() {
    local name="$1"
    local script
    
    script="$(provider_get_script "$name")"
    if [[ -z "$script" ]]; then
        log_error "Provider not registered: $name"
        return 1
    fi
    
    if [[ ! -f "$script" ]]; then
        log_error "Provider script not found: $script"
        return 1
    fi
    
    # shellcheck source=/dev/null
    source "$script"
    
    log_debug "Loaded provider: $name"
}

# Get provider for a specific phase
provider_get_for_phase() {
    local phase="$1"
    local provider_var="PROVIDER_${phase^^}"
    local provider
    local default_provider
    
    # First, get the default provider if set
    default_provider="$(config_get "PROVIDER_DEFAULT")"
    
    # Check phase-specific provider
    if provider="$(config_get "$provider_var")"; then
        # If phase-specific is set and different from default, use it
        # If it's the same as default, still use phase-specific to allow explicit overrides
        echo "$provider"
        return 0
    fi
    
    # Fall back to default provider
    if [[ -n "$default_provider" ]]; then
        echo "$default_provider"
        return 0
    fi
    
    # Final fallback to claude for backward compatibility
    echo "claude"
}

# Resolve capability level for a phase
provider_resolve_capability() {
    local phase="$1"
    local capability_var="CAPABILITY_${phase^^}"
    local capability
    
    # Check phase-specific capability override
    if capability="$(config_get "$capability_var")"; then
        echo "$capability"
        return 0
    fi
    
    # Default capability mapping based on phase
    case "$phase" in
        clarify|arch|plan|build)
            echo "high"
            ;;
        specs|gate)
            echo "medium"
            ;;
        feedback)
            echo "low"
            ;;
        *)
            echo "medium"  # Default to medium for unknown phases
            ;;
    esac
}

# Resolve model name for provider and capability
provider_resolve_model() {
    local provider="$1"
    local capability="$2"
    local model_var="PROVIDER_${provider^^}_MODEL_${capability^^}"
    local model
    
    # Check provider-specific model mapping
    if model="$(config_get "$model_var")"; then
        echo "$model"
        return 0
    fi
    
    # Log warning and return empty
    log_warn "No model configured for $provider with capability $capability"
    return 1
}

# Generic provider invocation
provider_invoke() {
    local provider="$1"
    local model="$2"
    local prompt_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Validate inputs
    if [[ -z "$provider" ]]; then
        log_error "Provider not specified"
        return 1
    fi
    
    if [[ -z "$model" ]]; then
        log_error "Model not specified"
        return 1
    fi
    
    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi
    
    # Load provider
    if ! provider_load "$provider"; then
        log_error "Failed to load provider: $provider"
        return 1
    fi
    
    # Check if provider supports invoke
    if ! declare -f "provider_${provider}_invoke" >/dev/null; then
        log_error "Provider $provider does not support invoke"
        return 1
    fi
    
    # Call provider's invoke function
    log_debug "Invoking $provider with model $model"

    # Use temp file to capture output while allowing stderr to pass through
    local temp_output
    temp_output="$(mktemp)"
    local exit_code=0
    local start_time
    start_time="$(date +%s)"

    # Setup cleanup trap for Ctrl+C
    local _cleanup_done=""
    _provider_cleanup() {
        [[ -n "$_cleanup_done" ]] && return
        _cleanup_done=1
        spinner_stop
        activity_status_clear
        rm -f "$temp_output" 2>/dev/null
        echo "" >&2
        log_warn "Interrupted"
    }
    trap '_provider_cleanup; exit 130' INT
    trap '_provider_cleanup; exit 143' TERM

    # Log LLM activity start
    activity_llm_start "$provider" "$model" "${PROVIDER_CURRENT_PHASE:-}"

    # Log prompt content at trace level
    if [[ -f "$prompt_file" ]]; then
        activity_llm_prompt "$(cat "$prompt_file")"
    fi

    # Start spinner during the blocking call (visual feedback)
    spinner_start "Thinking"

    # Run provider - runs in foreground, Ctrl+C goes directly to it
    # Note: 2>&1 is needed because some providers (claude --print) may output to stderr
    if "provider_${provider}_invoke" "$model" "$prompt_file" "${extra_args[@]}" > "$temp_output" 2>&1; then
        exit_code=0
    else
        exit_code=$?
    fi

    # Clear trap
    trap - INT TERM

    # Stop spinner after completion
    spinner_stop

    # Calculate duration and log completion
    local end_time duration
    end_time="$(date +%s)"
    duration=$((end_time - start_time))

    # Log response at trace level
    if [[ -f "$temp_output" ]]; then
        activity_llm_response "$(cat "$temp_output")"
    fi

    # Log completion
    activity_llm_complete "$duration" "unknown"
    activity_info "[$provider] completed in ${duration}s"

    # Output the captured result
    cat "$temp_output"
    rm -f "$temp_output"

    return $exit_code
}

# Generic provider streaming
provider_stream() {
    local provider="$1"
    local model="$2"
    local prompt_file="$3"
    shift 3
    local extra_args=("$@")
    
    # Validate inputs
    if [[ -z "$provider" ]]; then
        log_error "Provider not specified"
        return 1
    fi
    
    if [[ -z "$model" ]]; then
        log_error "Model not specified"
        return 1
    fi
    
    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt file not found: $prompt_file"
        return 1
    fi
    
    # Load provider
    if ! provider_load "$provider"; then
        log_error "Failed to load provider: $provider"
        return 1
    fi
    
    # Check if provider supports stream
    if ! declare -f "provider_${provider}_stream" >/dev/null; then
        # Fall back to invoke if stream not supported
        log_warn "Provider $provider does not support streaming, using invoke"
        "provider_${provider}_invoke" "$model" "$prompt_file" "${extra_args[@]}"
        return $?
    fi
    
    # Call provider's stream function
    log_debug "Streaming from $provider with model $model"
    "provider_${provider}_stream" "$model" "$prompt_file" "${extra_args[@]}"
}

# Validate provider is available
provider_validate() {
    local provider="$1"
    
    # Load provider
    if ! provider_load "$provider"; then
        log_error "Failed to load provider: $provider"
        return 1
    fi
    
    # Check if provider supports validate
    if ! declare -f "provider_${provider}_validate" >/dev/null; then
        # Default validation: check if provider script exists
        local script
        script="$(provider_get_script "$provider")"
        [[ -f "$script" ]]
        return $?
    fi
    
    # Call provider's validate function
    "provider_${provider}_validate"
}

# List models for provider
provider_list_models() {
    local provider="$1"
    
    # Load provider
    if ! provider_load "$provider"; then
        log_error "Failed to load provider: $provider"
        return 1
    fi
    
    # Check if provider supports list_models
    if ! declare -f "provider_${provider}_list_models" >/dev/null; then
        log_warn "Provider $provider does not support listing models"
        return 1
    fi
    
    # Call provider's list_models function
    "provider_${provider}_list_models"
}

# Announce which provider is being used (for transparency)
provider_announce() {
    local phase="$1"
    local provider model capability

    provider="$(provider_get_for_phase "$phase")"
    capability="$(provider_resolve_capability "$phase")"

    if model="$(provider_resolve_model "$provider" "$capability" 2>/dev/null)"; then
        log_info "Using provider: ${COLOR_CYAN}${provider}${COLOR_RESET} (${model})"
        log_info "Phase: ${phase} (capability: ${capability})"
    else
        log_info "Using provider: ${COLOR_CYAN}${provider}${COLOR_RESET}"
        log_info "Phase: ${phase} (capability: ${capability})"
    fi
}

# Get fallback chain for a provider
# Default chain: specified -> opencode -> claude -> gemini
provider_get_fallback_chain() {
    local primary="$1"
    local -a chain=("$primary")

    # Add fallbacks in priority order
    for fallback in opencode claude gemini; do
        if [[ "$fallback" != "$primary" ]] && provider_is_registered "$fallback"; then
            chain+=("$fallback")
        fi
    done

    echo "${chain[@]}"
}

# Track current phase for activity logging
PROVIDER_CURRENT_PHASE=""

# High-level convenience function for phase invocation with fallback support
provider_invoke_for_phase() {
    local phase="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")

    local provider model capability
    local -a fallback_chain

    # Track current phase for activity logging
    PROVIDER_CURRENT_PHASE="$phase"
    export PROVIDER_CURRENT_PHASE

    # Start activity section for this phase
    activity_section_start "phase_${phase}" "Phase: $phase"

    # Get provider for phase
    provider="$(provider_get_for_phase "$phase")"

    # Get capability for phase
    capability="$(provider_resolve_capability "$phase")"

    # Get fallback chain
    read -r -a fallback_chain <<< "$(provider_get_fallback_chain "$provider")"

    # Try each provider in fallback chain
    local attempt=0
    local max_attempts=${#fallback_chain[@]}

    for try_provider in "${fallback_chain[@]}"; do
        ((attempt++))

        # Announce provider (transparency)
        if [[ $attempt -eq 1 ]]; then
            provider_announce "$phase"
            activity_section_add_detail "phase_${phase}" "Provider: $provider ($capability)"
        else
            log_warn "Trying fallback provider: ${COLOR_CYAN}${try_provider}${COLOR_RESET} (attempt $attempt/$max_attempts)"
            activity_section_add_detail "phase_${phase}" "Fallback to: $try_provider (attempt $attempt)"
        fi

        # Resolve model
        if ! model="$(provider_resolve_model "$try_provider" "$capability" 2>/dev/null)"; then
            log_debug "No model configured for $try_provider with capability $capability"
            continue
        fi

        activity_section_add_detail "phase_${phase}" "Model: $model"

        # Validate provider
        if ! provider_validate "$try_provider" 2>/dev/null; then
            log_debug "Provider $try_provider is not available"
            continue
        fi

        # Try to invoke provider (don't capture stderr - let spinner/progress show)
        local result
        if result=$(provider_invoke "$try_provider" "$model" "$prompt_file" "${extra_args[@]}"); then
            echo "$result"
            activity_section_end "phase_${phase}" "success"
            PROVIDER_CURRENT_PHASE=""
            return 0
        else
            local exit_code=$?
            log_warn "Provider $try_provider failed with exit code $exit_code"
            activity_section_add_detail "phase_${phase}" "Error: exit code $exit_code"

            # Check if this is a rate limit or transient error
            if [[ "$result" == *"rate limit"* ]] || [[ "$result" == *"429"* ]] || [[ "$result" == *"503"* ]]; then
                log_info "Rate limit or temporary error - trying fallback..."
                continue
            fi

            # For other errors, still try fallback but log the error
            log_debug "Error from $try_provider: ${result:0:200}"
        fi
    done

    activity_section_end "phase_${phase}" "failed"
    PROVIDER_CURRENT_PHASE=""
    log_error "All providers in fallback chain failed"
    return 1
}

# Direct capability invocation (bypasses phase resolution)
# Used by adaptive model selection for per-step capability control
provider_invoke_with_capability() {
    local capability="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")

    local provider model

    # Validate capability
    case "$capability" in
        high|medium|low) ;;
        *)
            log_error "Invalid capability: $capability (expected high|medium|low)"
            return 1
            ;;
    esac

    # Get default provider (same as build phase)
    provider="$(provider_get_for_phase "build")"

    # Resolve model for specified capability
    if ! model="$(provider_resolve_model "$provider" "$capability" 2>/dev/null)"; then
        log_error "No model configured for capability: $capability"
        return 1
    fi

    log_debug "Direct capability invocation: $capability -> $provider/$model"

    # Invoke provider directly (no fallback chain for step-level invocations)
    provider_invoke "$provider" "$model" "$prompt_file" "${extra_args[@]}"
}

# Auto-detect provider from model name
provider_detect_from_model() {
    local model="$1"
    
    case "$model" in
        claude-*)
            echo "claude"
            ;;
        opencode/*)
            echo "opencode"
            ;;
        gpt-*|o1*)
            echo "openai"
            ;;
        gemini-*)
            echo "gemini"
            ;;
        *)
            # Default to configured default provider
            provider_get_for_phase "default"
            ;;
    esac
}

# Legacy model mapping for backward compatibility
provider_map_legacy_model() {
    local legacy_model="$1"
    local provider capability
    
    # Detect provider from legacy model or use default
    if [[ "$legacy_model" =~ ^claude- ]]; then
        provider="claude"
    elif [[ "$legacy_model" =~ ^opencode/ ]]; then
        provider="opencode"
    else
        # Map legacy model names to capabilities
        case "$legacy_model" in
            opus)
                capability="high"
                ;;
            sonnet)
                capability="medium"
                ;;
            haiku)
                capability="low"
                ;;
            *)
                capability="medium"
                ;;
        esac
        
        # Get default provider
        provider="$(config_get "PROVIDER_DEFAULT")"
        provider="${provider:-claude}"
        
        # Resolve model for capability
        provider_resolve_model "$provider" "$capability"
        return
    fi
    
    # If model already has provider prefix, return as-is
    echo "$legacy_model"
}

# Initialize provider system
provider_init() {
    local providers_dir="${LIB_DIR}/providers"
    
    # Auto-register providers from providers directory
    if [[ -d "$providers_dir" ]]; then
        for provider_script in "$providers_dir"/*.sh; do
            if [[ -f "$provider_script" ]]; then
                # Extract provider name from filename
                local provider_name
                provider_name="$(basename "$provider_script" .sh)"
                
                # Register provider (description will be set by provider script)
                provider_register "$provider_name" "$provider_script"
            fi
        done
    fi
    
    log_debug "Initialized provider system"
}

# Auto-initialize when sourced
provider_init