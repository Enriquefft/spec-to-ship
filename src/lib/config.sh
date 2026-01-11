#!/usr/bin/env bash
# src/lib/config.sh - Configuration loading and validation

# Source common utilities
LIB_DIR="${LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Default configuration values
declare -A CONFIG_DEFAULTS=(
    [MODEL_CLARIFY]="opus"
    [MODEL_SPECS]="sonnet"
    [MODEL_ARCH]="opus"
    [MODEL_PLAN]="opus"
    [MODEL_BUILD_PRIMARY]="opus"
    [MODEL_BUILD_SECONDARY]="sonnet"
    [MODEL_GATE]="sonnet"
    [MODEL_FEEDBACK]="haiku"
    [HITL_ENABLED]="false"
    [HITL_MODE]="milestone"
    [HITL_TIMEOUT]=""
    [BUILD_MAX_ITERATIONS]="0"
    [BUILD_BACKPRESSURE_TESTS]="true"
    [BUILD_BACKPRESSURE_TYPECHECK]="false"
    [BUILD_BACKPRESSURE_LINT]="true"
    [RETRY_MAX_ATTEMPTS]="3"
    [RETRY_BASE_DELAY]="2"
)

# Current configuration (populated by config_load)
declare -A CONFIG

# Valid model names
readonly VALID_MODELS=("opus" "sonnet" "haiku")

# Valid HITL modes
readonly VALID_HITL_MODES=("task" "milestone" "uncertain")

# config_load() - Load configuration from file or environment
config_load() {
    local config_file="${WORKFLOW_CONFIG:-}"
    local git_root

    # Determine config file location
    if [[ -z "$config_file" ]]; then
        if git_root="$(get_git_root)"; then
            config_file="${git_root}/.workflow/config.sh"
        else
            config_file=".workflow/config.sh"
        fi
    fi

    # Load defaults first
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        CONFIG["$key"]="${CONFIG_DEFAULTS[$key]}"
    done

    # Load from file if exists
    if [[ -f "$config_file" ]]; then
        log_debug "Loading configuration from: $config_file"

        # Source the config file in a subshell to avoid pollution
        local config_content
        config_content="$(cat "$config_file")"

        # Parse key=value pairs
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue

            # Remove leading/trailing whitespace and quotes
            key="${key#"${key%%[![:space:]]*}"}"
            key="${key%"${key##*[![:space:]]}"}"
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
            value="${value%\"}"
            value="${value#\"}"

            # Set configuration value
            if [[ -n "$key" ]]; then
                CONFIG["$key"]="$value"
                log_debug "Loaded config: $key=$value"
            fi
        done <<< "$config_content"
    else
        log_warn "Configuration file not found: $config_file (using defaults)"
    fi

    # Override with environment variables
    for key in "${!CONFIG_DEFAULTS[@]}"; do
        local env_var="WORKFLOW_${key}"
        if [[ -n "${!env_var:-}" ]]; then
            CONFIG["$key"]="${!env_var}"
            log_debug "Overrode config with env var: $key=${!env_var}"
        fi
    done

    return 0
}

# config_get(key) - Get configuration value
config_get() {
    local key="$1"

    if [[ -n "${CONFIG[$key]:-}" ]]; then
        echo "${CONFIG[$key]}"
        return 0
    fi

    return 1
}

# config_set(key, value) - Set configuration value (runtime only)
config_set() {
    local key="$1"
    local value="$2"

    if [[ ! -v CONFIG_DEFAULTS[$key] ]]; then
        log_error "Invalid configuration key: $key"
        return 1
    fi

    CONFIG["$key"]="$value"
    log_debug "Set config: $key=$value"
    return 0
}

# config_validate() - Validate all configuration values
config_validate() {
    local errors=0

    # Validate model selections
    for key in MODEL_CLARIFY MODEL_SPECS MODEL_ARCH MODEL_PLAN MODEL_BUILD_PRIMARY MODEL_BUILD_SECONDARY MODEL_GATE MODEL_FEEDBACK; do
        local model="${CONFIG[$key]}"
        local valid=false

        for valid_model in "${VALID_MODELS[@]}"; do
            if [[ "$model" == "$valid_model" ]]; then
                valid=true
                break
            fi
        done

        if [[ "$valid" == "false" ]]; then
            log_error "Invalid model for $key: $model (must be one of: ${VALID_MODELS[*]})"
            ((errors++))
        fi
    done

    # Validate HITL mode
    local hitl_mode="${CONFIG[HITL_MODE]}"
    local valid=false

    for valid_mode in "${VALID_HITL_MODES[@]}"; do
        if [[ "$hitl_mode" == "$valid_mode" ]]; then
            valid=true
            break
        fi
    done

    # Also check for every:N pattern
    if [[ "$hitl_mode" =~ ^every:[0-9]+$ ]]; then
        valid=true
    fi

    if [[ "$valid" == "false" ]]; then
        log_error "Invalid HITL mode: $hitl_mode (must be one of: ${VALID_HITL_MODES[*]}, or every:N)"
        ((errors++))
    fi

    # Validate boolean values
    for key in HITL_ENABLED BUILD_BACKPRESSURE_TESTS BUILD_BACKPRESSURE_TYPECHECK BUILD_BACKPRESSURE_LINT; do
        local value="${CONFIG[$key]}"
        if [[ "$value" != "true" && "$value" != "false" ]]; then
            log_error "Invalid boolean value for $key: $value (must be true or false)"
            ((errors++))
        fi
    done

    # Validate integer values
    for key in BUILD_MAX_ITERATIONS RETRY_MAX_ATTEMPTS RETRY_BASE_DELAY; do
        local value="${CONFIG[$key]}"
        if ! [[ "$value" =~ ^[0-9]+$ ]]; then
            log_error "Invalid integer value for $key: $value"
            ((errors++))
        fi
    done

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    log_debug "Configuration validation passed"
    return 0
}

# config_model_for_phase(phase) - Get model name for specific workflow phase
config_model_for_phase() {
    local phase="$1"

    case "$phase" in
        clarify)
            config_get "MODEL_CLARIFY"
            ;;
        specs)
            config_get "MODEL_SPECS"
            ;;
        arch)
            config_get "MODEL_ARCH"
            ;;
        plan)
            config_get "MODEL_PLAN"
            ;;
        build)
            config_get "MODEL_BUILD_PRIMARY"
            ;;
        gate)
            config_get "MODEL_GATE"
            ;;
        feedback)
            config_get "MODEL_FEEDBACK"
            ;;
        *)
            log_error "Unknown phase: $phase"
            return 1
            ;;
    esac
}
