#!/usr/bin/env bash
# src/lib/providers/copilot.sh - GitHub Copilot CLI provider

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Set provider description
PROVIDER_DESCRIPTION="GitHub Copilot CLI"

# Validate Copilot CLI is available
provider_copilot_validate() {
    if ! command -v copilot &> /dev/null; then
        log_error "GitHub Copilot CLI not found. Install from: https://github.com/github/copilot-cli"
        return 1
    fi

    if ! timeout 5s copilot --version >/dev/null 2>&1; then
        log_warn "Copilot CLI may not be authenticated. Run 'copilot' and complete login."
    fi

    return 0
}

# Map model names to Copilot CLI format
provider_copilot_map_model() {
    local model="$1"
    local normalized="${model,,}"
    normalized="${normalized// /-}"

    case "$normalized" in
        high|opus|claude-opus*|copilot-high)
            echo "claude-opus-4.5"
            ;;
        medium|sonnet|claude-sonnet-4.5|claude-sonnet-4-5|claude-sonnet|copilot-medium)
            echo "claude-sonnet-4.5"
            ;;
        claude-sonnet-4)
            echo "claude-sonnet-4"
            ;;
        low|haiku|claude-haiku*|copilot-low)
            echo "claude-haiku-4.5"
            ;;
        gpt-5.1-codex-max)
            echo "gpt-5.1-codex-max"
            ;;
        gpt-5.1-codex)
            echo "gpt-5.1-codex"
            ;;
        gpt-5.2)
            echo "gpt-5.2"
            ;;
        gpt-5.1)
            echo "gpt-5.1"
            ;;
        gpt-5)
            echo "gpt-5"
            ;;
        gpt-5.1-codex-mini)
            echo "gpt-5.1-codex-mini"
            ;;
        gpt-5-mini)
            echo "gpt-5-mini"
            ;;
        gpt-4.1)
            echo "gpt-4.1"
            ;;
        gemini-3-pro*|gemini-3-pro-\(preview\))
            echo "gemini-3-pro-preview"
            ;;
        *)
            echo "$model"
            ;;
    esac
}

# Execute command with exponential backoff retry
_provider_copilot_retry_with_backoff() {
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

# Copilot provider invoke implementation
provider_copilot_invoke() {
    local model="$1"
    local prompt_file="$2"
    shift 2
    local extra_args=("$@")

    # Map model name
    local model_name
    model_name="$(provider_copilot_map_model "$model")"

    log_info "Invoking Copilot ($model) with prompt: $prompt_file"
    log_debug "Model ID: $model_name"

    # Log prompt content if verbose
    if [[ "$VERBOSE" == "true" ]]; then
        log_debug "Prompt content:"
        log_debug "$(cat "$prompt_file")"
    fi

    local prompt_content
    prompt_content="$(cat "$prompt_file")"

    # Prepare copilot command
    local copilot_cmd=(copilot --prompt "$prompt_content")

    # Add model selection when specified
    if [[ -n "$model_name" ]]; then
        copilot_cmd+=(--model "$model_name")
    fi

    # Add any extra arguments
    if [[ ${#extra_args[@]} -gt 0 ]]; then
        copilot_cmd+=("${extra_args[@]}")
    fi

    # Invoke Copilot with retry - stdout captured by caller, let stderr pass through
    if _provider_copilot_retry_with_backoff "${copilot_cmd[@]}"; then
        return 0
    else
        local exit_code=$?
        log_error "Copilot invocation failed with exit code $exit_code"
        return $exit_code
    fi
}

# Copilot provider stream implementation (same as invoke for now)
provider_copilot_stream() {
    provider_copilot_invoke "$@"
}

# List available Copilot models
provider_copilot_list_models() {
    echo "Available Copilot models:"
    echo "  Claude Sonnet 4.5 (default) - 1x"
    echo "  Claude Haiku 4.5 - 0.33x"
    echo "  Claude Opus 4.5 - 3x"
    echo "  Claude Sonnet 4 - 1x"
    echo "  GPT-5.1-Codex-Max - 1x"
    echo "  GPT-5.1-Codex - 1x"
    echo "  GPT-5.2 - 1x"
    echo "  GPT-5.1 (requires enablement) - 1x"
    echo "  GPT-5 - 1x"
    echo "  GPT-5.1-Codex-Mini - 0.33x"
    echo "  GPT-5 mini - 0x"
    echo "  GPT-4.1 - 0x"
    echo "  Gemini 3 Pro (Preview) - 1x"
}

# Initialize provider when loaded
provider_copilot_init() {
    # Set default model mappings if not configured
    if ! config_get "PROVIDER_COPILOT_MODEL_HIGH" >/dev/null; then
        config_set "PROVIDER_COPILOT_MODEL_HIGH" "Claude Opus 4.5"
    fi

    if ! config_get "PROVIDER_COPILOT_MODEL_MEDIUM" >/dev/null; then
        config_set "PROVIDER_COPILOT_MODEL_MEDIUM" "Claude Sonnet 4.5"
    fi

    if ! config_get "PROVIDER_COPILOT_MODEL_LOW" >/dev/null; then
        config_set "PROVIDER_COPILOT_MODEL_LOW" "Claude Haiku 4.5"
    fi
}

# Auto-initialize
provider_copilot_init
