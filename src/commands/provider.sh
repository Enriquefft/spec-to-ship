#!/usr/bin/env bash
# src/commands/provider.sh - Manage AI providers

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=src/lib/provider.sh
source "${LIB_DIR}/provider.sh"

# Show help for provider command
show_provider_help() {
    cat <<EOF
workflow provider - Manage AI providers

USAGE:
    workflow provider [subcommand] [options]

SUBCOMMANDS:
    list          List all available providers
    validate      Validate provider availability
    models        List models for a provider
    config        Show provider configuration

EXAMPLES:
    workflow provider list
    workflow provider validate claude
    workflow provider models opencode
    workflow provider config

EXIT CODES:
    0   Success
    1   Error

EOF
}

# List all providers
cmd_provider_list() {
    echo "Available providers:"
    provider_list
    echo
    echo "Provider for each phase:"
    echo "  Clarify: $(provider_get_for_phase clarify)"
    echo "  Specs:   $(provider_get_for_phase specs)"
    echo "  Arch:    $(provider_get_for_phase arch)"
    echo "  Plan:    $(provider_get_for_phase plan)"
    echo "  Build:   $(provider_get_for_phase build)"
    echo "  Gate:    $(provider_get_for_phase gate)"
    echo "  Feedback: $(provider_get_for_phase feedback)"
}

# Validate a provider
cmd_provider_validate() {
    local provider="${1:-}"
    
    if [[ -z "$provider" ]]; then
        echo "Validating all providers..."
        echo
        
        for prov in $(provider_list | cut -d: -f1); do
            echo -n "  $prov: "
            if provider_validate "$prov"; then
                echo "✓ Available"
            else
                echo "✗ Not available"
            fi
        done
        return 0
    fi
    
    echo "Validating provider: $provider"
    if ! provider_is_registered "$provider"; then
        echo "Error: Unknown provider '$provider'"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi
    
    if provider_validate "$provider"; then
        echo "✓ Provider '$provider' is available"
        return 0
    else
        echo "✗ Provider '$provider' is not available"
        return 1
    fi
}

# List models for a provider
cmd_provider_models() {
    local provider="${1:-}"
    
    if [[ -z "$provider" ]]; then
        echo "Error: Provider name required"
        echo "Usage: workflow provider models <provider>"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi
    
    if ! provider_is_registered "$provider"; then
        echo "Error: Unknown provider '$provider'"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi
    
    echo "Models for provider '$provider':"
    provider_list_models "$provider"
}

# Show provider configuration
cmd_provider_config() {
    echo "Current provider configuration:"
    echo
    
    # Provider settings
    echo "Provider selection:"
    for phase in clarify specs arch plan build gate feedback; do
        local prov_var="PROVIDER_${phase^^}"
        local provider
        provider="$(config_get "$prov_var")"
        echo "  ${phase^}: ${provider:-<default>}"
    done
    
    echo
    echo "Model mappings:"
    
    # Show model mappings for each provider
    for provider in $(provider_list | cut -d: -f1); do
        echo "  $provider:"
        for cap in high medium low; do
            local model_var="PROVIDER_${provider^^}_MODEL_${cap^^}"
            local model
            model="$(config_get "$model_var")"
            if [[ -n "$model" ]]; then
                echo "    $cap: $model"
            fi
        done
    done
    
    echo
    echo "Capability requirements:"
    for phase in clarify specs arch plan build gate feedback; do
        local cap_var="CAPABILITY_${phase^^}"
        local capability
        capability="$(config_get "$cap_var")"
        echo "  ${phase^}: ${capability:-<default>}"
    done
}

# Main provider command
cmd_provider() {
    local subcmd="${1:-}"
    shift || true
    
    # Load configuration
    config_load
    
    case "$subcmd" in
        list)
            cmd_provider_list "$@"
            ;;
        validate)
            cmd_provider_validate "$@"
            ;;
        models)
            cmd_provider_models "$@"
            ;;
        config)
            cmd_provider_config "$@"
            ;;
        -h|--help|help|"")
            show_provider_help
            ;;
        *)
            log_error "Unknown subcommand: $subcmd"
            show_provider_help
            exit 1
            ;;
    esac
}