#!/usr/bin/env bash
# src/lib/config.sh - Configuration loading and validation

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# Default configuration values
# Use -g flag for global scope when sourced from within a function
declare -gA CONFIG_DEFAULTS 2>/dev/null || declare -A CONFIG_DEFAULTS
CONFIG_DEFAULTS=(
    # Provider selection
    [PROVIDER_DEFAULT]="claude"
    [PROVIDER_CLARIFY]="claude"
    [PROVIDER_CONSTITUTION]="claude"
    [PROVIDER_SPECS]="claude"
    [PROVIDER_ARCH]="claude"
    [PROVIDER_PLAN]="claude"
    [PROVIDER_BUILD]="claude"
    [PROVIDER_GATE]="claude"
    [PROVIDER_FEEDBACK]="claude"

    # Provider-specific model mappings
    [PROVIDER_CLAUDE_MODEL_HIGH]="claude-opus-4-20250514"
    [PROVIDER_CLAUDE_MODEL_MEDIUM]="claude-sonnet-4-5-20250929"
    [PROVIDER_CLAUDE_MODEL_LOW]="claude-haiku-4-20250319"
    [PROVIDER_OPENCODE_MODEL_HIGH]="opencode/big-pickle"
    [PROVIDER_OPENCODE_MODEL_MEDIUM]="opencode/glm-4.7-free"
    [PROVIDER_OPENCODE_MODEL_LOW]="opencode/grok-code"
    # Additional model options (not used by default, available for override)
    [PROVIDER_OPENCODE_MODEL_EXTRA]="opencode/minimax-m2.1-free"
    
    # Gemini provider model mappings
    [PROVIDER_GEMINI_MODEL_HIGH]="gemini-3-pro-preview"
    [PROVIDER_GEMINI_MODEL_MEDIUM]="gemini-2.5-flash"
    [PROVIDER_GEMINI_MODEL_LOW]="gemini-2.5-flash"

    # Capability overrides per phase
    [CAPABILITY_CLARIFY]="high"
    [CAPABILITY_CONSTITUTION]="high"
    [CAPABILITY_SPECS]="medium"
    [CAPABILITY_ARCH]="high"
    [CAPABILITY_PLAN]="high"
    [CAPABILITY_BUILD]="high"
    [CAPABILITY_GATE]="medium"
    [CAPABILITY_FEEDBACK]="low"

    # Legacy model mappings (backward compatibility)
    [MODEL_CLARIFY]="opus"
    [MODEL_CONSTITUTION]="opus"
    [MODEL_SPECS]="sonnet"
    [MODEL_ARCH]="opus"
    [MODEL_PLAN]="opus"
    [MODEL_BUILD_PRIMARY]="opus"
    [MODEL_BUILD_SECONDARY]="sonnet"
    [MODEL_GATE]="sonnet"
    [MODEL_FEEDBACK]="haiku"

    # HITL Settings
    [HITL_ENABLED]="false"
    [HITL_MODE]="milestone"
    [HITL_TIMEOUT]=""

    # Build Settings
    [BUILD_MAX_ITERATIONS]="0"
    [BUILD_BACKPRESSURE_TESTS]="true"
    [BUILD_BACKPRESSURE_TYPECHECK]="false"
    [BUILD_BACKPRESSURE_LINT]="true"

    # Test command (auto-detected if empty)
    # Examples: "npm test", "make test", "pytest", "cargo test", "deno test"
    [TEST_COMMAND]=""

    # Retry Settings
    [RETRY_MAX_ATTEMPTS]="3"
    [RETRY_BASE_DELAY]="2"

    # Token Optimization
    [PROMPT_COMPACT]="true"
    [CONTEXT_CACHE_TTL]="3600"

    # Adaptive Model Selection
    [ADAPTIVE_ENABLED]="true"
    [ADAPTIVE_RETRY_BEFORE_ESCALATE]="2"
    [ADAPTIVE_TOOL_STEP_DOWNGRADE]="true"
    [ADAPTIVE_HISTORY_COMPRESS_THRESHOLD]="10"
    [ADAPTIVE_DEFAULT_COMPLEXITY]="high"
)

# Current configuration (populated by config_load)
# Use -g flag for global scope when sourced from within a function
declare -gA CONFIG 2>/dev/null || declare -A CONFIG

# Valid model names (only set once)
if [[ ! -v VALID_MODELS ]]; then
    readonly VALID_MODELS=(
        "opus" "sonnet" "haiku"  # Legacy model names
        "claude-opus-4-20250514" "claude-sonnet-4-5-20250929" "claude-haiku-4-20250319"  # Claude models
        "opencode/grok-code" "opencode/gpt-5-nano" "opencode/glm-4.7-free"  # OpenCode models
    )
fi

# Valid provider names (only set once)
if [[ ! -v VALID_PROVIDERS ]]; then
    readonly VALID_PROVIDERS=("claude" "opencode" "openai")
fi

# Valid capability levels (only set once)
if [[ ! -v VALID_CAPABILITIES ]]; then
    readonly VALID_CAPABILITIES=("high" "medium" "low")
fi

# Valid HITL modes (only set once)
if [[ ! -v VALID_HITL_MODES ]]; then
    readonly VALID_HITL_MODES=("task" "milestone" "uncertain")
fi

# ==============================================================================
# O(1) Validation Maps (for performance)
# ==============================================================================

# Build associative arrays for O(1) validation lookups
declare -gA _VALID_MODELS_MAP 2>/dev/null || declare -A _VALID_MODELS_MAP
declare -gA _VALID_PROVIDERS_MAP 2>/dev/null || declare -A _VALID_PROVIDERS_MAP
declare -gA _VALID_CAPABILITIES_MAP 2>/dev/null || declare -A _VALID_CAPABILITIES_MAP
declare -gA _VALID_HITL_MODES_MAP 2>/dev/null || declare -A _VALID_HITL_MODES_MAP

# Initialize maps once
if [[ ! -v _CONFIG_MAPS_INITIALIZED ]]; then
    for m in "${VALID_MODELS[@]}"; do _VALID_MODELS_MAP["$m"]=1; done
    for p in "${VALID_PROVIDERS[@]}"; do _VALID_PROVIDERS_MAP["$p"]=1; done
    for c in "${VALID_CAPABILITIES[@]}"; do _VALID_CAPABILITIES_MAP["$c"]=1; done
    for h in "${VALID_HITL_MODES[@]}"; do _VALID_HITL_MODES_MAP["$h"]=1; done
    _CONFIG_MAPS_INITIALIZED=true
fi

# _is_valid_model(model) - O(1) model validation
_is_valid_model() {
    [[ -v "_VALID_MODELS_MAP[$1]" ]]
}

# _is_valid_provider(provider) - O(1) provider validation
_is_valid_provider() {
    [[ -v "_VALID_PROVIDERS_MAP[$1]" ]]
}

# _is_valid_capability(capability) - O(1) capability validation
_is_valid_capability() {
    [[ -v "_VALID_CAPABILITIES_MAP[$1]" ]]
}

# _is_valid_hitl_mode(mode) - O(1) HITL mode validation (also checks every:N pattern)
_is_valid_hitl_mode() {
    [[ -v "_VALID_HITL_MODES_MAP[$1]" ]] || [[ "$1" =~ ^every:[0-9]+$ ]]
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# _apply_provider_defaults() - Apply PROVIDER_DEFAULT to phase-specific providers
# Called after loading config or env vars to cascade default provider
_apply_provider_defaults() {
    local default_provider="${CONFIG_DEFAULTS[PROVIDER_DEFAULT]}"
    local final_default="${CONFIG[PROVIDER_DEFAULT]}"

    # If the final default is different from the original default (claude),
    # unset phase-specific providers that still match the original default
    if [[ "$final_default" != "$default_provider" ]]; then
        for phase in CLARIFY SPECS ARCH PLAN BUILD GATE FEEDBACK; do
            local phase_provider="PROVIDER_${phase}"
            local env_var="WORKFLOW_${phase_provider}"
            local phase_value="${CONFIG[$phase_provider]:-}"
            local env_value="${!env_var:-}"

            # Only unset if:
            # 1. It matches the original default (claude) AND
            # 2. No environment variable was explicitly set for this phase
            if [[ "$phase_value" = "$default_provider" && -z "$env_value" ]]; then
                unset "CONFIG[$phase_provider]"
                log_debug "Unset $phase_provider to allow PROVIDER_DEFAULT to take effect"
            fi
        done
    fi
}

# config_load() - Load configuration from file or environment
config_load() {
    local config_file="${WORKFLOW_CONFIG:-}"
    local git_root
    local key value  # Declare as local to avoid polluting caller's scope

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

            # Remove inline comments (everything after # outside quotes)
            # Simple approach: remove # and everything after it
            if [[ "$value" =~ ([^#]*)(#.*)? ]]; then
                value="${BASH_REMATCH[1]}"
            fi

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

    # Apply provider defaults (consolidated helper - eliminates duplication)
    _apply_provider_defaults

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

# config_validate_no_secrets() - Ensure no secrets in configuration values
config_validate_no_secrets() {
    local errors=0
    local secret_patterns=(
        "sk-[a-zA-Z0-9]{32,}"           # OpenAI/Anthropic API keys
        "ghp_[a-zA-Z0-9]{36}"            # GitHub personal access tokens
        "gho_[a-zA-Z0-9]{36}"            # GitHub OAuth tokens
        "AIza[0-9A-Za-z\\-_]{35}"        # Google API keys
        "[0-9a-f]{32}"                   # MD5 hashes (common for tokens)
        "[0-9a-f]{40}"                   # SHA1 hashes
        "[0-9a-f]{64}"                   # SHA256 hashes
        "-----BEGIN.*PRIVATE KEY-----"   # Private keys
    )

    for key in "${!CONFIG[@]}"; do
        local value="${CONFIG[$key]}"

        # Skip empty values and known safe values
        [[ -z "$value" ]] && continue
        [[ "$value" =~ ^(true|false|[0-9]+|opus|sonnet|haiku|task|milestone|uncertain)$ ]] && continue

        # Check against secret patterns
        for pattern in "${secret_patterns[@]}"; do
            if [[ "$value" =~ $pattern ]]; then
                log_error "Configuration key '$key' appears to contain a secret (matches pattern: $pattern)"
                log_error "Secrets should be stored in environment variables like WORKFLOW_${key}, not in config files"
                ((errors++))
                break
            fi
        done
    done

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

# config_validate() - Validate all configuration values
# Uses O(1) lookups for better performance
config_validate() {
    local errors=0

    # Validate no secrets in config
    if ! config_validate_no_secrets; then
        ((errors++))
    fi

    # Validate model selections (O(1) lookup)
    for key in MODEL_CLARIFY MODEL_CONSTITUTION MODEL_SPECS MODEL_ARCH MODEL_PLAN MODEL_BUILD_PRIMARY MODEL_BUILD_SECONDARY MODEL_GATE MODEL_FEEDBACK; do
        local model="${CONFIG[$key]}"
        if ! _is_valid_model "$model"; then
            log_error "Invalid model for $key: $model (must be one of: ${VALID_MODELS[*]})"
            ((errors++))
        fi
    done

    # Validate HITL mode (O(1) lookup + pattern check)
    local hitl_mode="${CONFIG[HITL_MODE]}"
    if ! _is_valid_hitl_mode "$hitl_mode"; then
        log_error "Invalid HITL mode: $hitl_mode (must be one of: ${VALID_HITL_MODES[*]}, or every:N)"
        ((errors++))
    fi

    # Validate provider values (O(1) lookup)
    for key in PROVIDER_DEFAULT PROVIDER_CLARIFY PROVIDER_CONSTITUTION PROVIDER_SPECS PROVIDER_ARCH PROVIDER_PLAN PROVIDER_BUILD PROVIDER_GATE PROVIDER_FEEDBACK; do
        if [[ -n "${CONFIG[$key]:-}" ]]; then
            local value="${CONFIG[$key]}"
            if ! _is_valid_provider "$value"; then
                log_error "Invalid provider for $key: $value (must be one of: ${VALID_PROVIDERS[*]})"
                ((errors++))
            fi
        fi
    done

    # Validate capability values (O(1) lookup)
    for key in CAPABILITY_CLARIFY CAPABILITY_CONSTITUTION CAPABILITY_SPECS CAPABILITY_ARCH CAPABILITY_PLAN CAPABILITY_BUILD CAPABILITY_GATE CAPABILITY_FEEDBACK; do
        if [[ -n "${CONFIG[$key]:-}" ]]; then
            local value="${CONFIG[$key]}"
            if ! _is_valid_capability "$value"; then
                log_error "Invalid capability for $key: $value (must be one of: ${VALID_CAPABILITIES[*]})"
                ((errors++))
            fi
        fi
    done

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
        constitution)
            config_get "MODEL_CONSTITUTION"
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
