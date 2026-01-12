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
    list            List all available providers
    validate        Validate provider availability
    models          List models for a provider
    config          Show provider configuration
    set-default     Set default provider for all phases
    test            Test provider with sample prompt and timing

EXAMPLES:
    workflow provider list
    workflow provider validate claude
    workflow provider models opencode
    workflow provider config
    workflow provider set-default opencode
    workflow provider test claude

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

    # Default provider
    local default_prov
    default_prov="$(config_get "PROVIDER_DEFAULT")"
    printf "Default provider: \033[0;36m%s\033[0m\n" "${default_prov:-claude}"
    echo

    # Provider settings
    echo "Provider selection per phase:"
    printf "  %-10s %-12s %-10s %s\n" "PHASE" "PROVIDER" "CAPABILITY" "MODEL"
    printf "  %-10s %-12s %-10s %s\n" "-----" "--------" "----------" "-----"
    for phase in clarify specs arch plan build gate feedback; do
        local prov_var="PROVIDER_${phase^^}"
        local cap_var="CAPABILITY_${phase^^}"
        local provider capability model
        provider="$(config_get "$prov_var")"
        provider="${provider:-$default_prov}"
        capability="$(config_get "$cap_var")"
        capability="${capability:-medium}"
        model="$(provider_resolve_model "$provider" "$capability" 2>/dev/null || echo "<not configured>")"
        printf "  %-10s %-12s %-10s %s\n" "${phase^}" "$provider" "$capability" "$model"
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
}

# Set default provider
cmd_provider_set_default() {
    local provider="${1:-}"

    if [[ -z "$provider" ]]; then
        echo "Error: Provider name required"
        echo "Usage: workflow provider set-default <provider>"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi

    if ! provider_is_registered "$provider"; then
        echo "Error: Unknown provider '$provider'"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi

    # Validate provider works
    echo "Validating provider '$provider'..."
    if ! provider_validate "$provider"; then
        echo "✗ Provider '$provider' is not available"
        echo "Please check your API key or credentials for this provider"
        return 1
    fi

    # Get config file path
    local git_root config_file
    git_root="$(get_git_root 2>/dev/null || echo ".")"
    config_file="${git_root}/.workflow/config.sh"

    # Create config directory if needed
    mkdir -p "$(dirname "$config_file")"

    # Update or create config file
    if [[ -f "$config_file" ]]; then
        # Update existing PROVIDER_DEFAULT or add it
        if grep -q '^PROVIDER_DEFAULT=' "$config_file"; then
            sed -i "s/^PROVIDER_DEFAULT=.*/PROVIDER_DEFAULT=\"$provider\"/" "$config_file"
        else
            echo "PROVIDER_DEFAULT=\"$provider\"" >> "$config_file"
        fi
    else
        # Create new config file
        cat > "$config_file" <<EOF
# Workflow configuration
# Generated by: workflow provider set-default

PROVIDER_DEFAULT="$provider"
EOF
    fi

    printf "✓ Default provider set to '\033[0;36m%s\033[0m'\n" "$provider"
    echo "Configuration saved to: $config_file"
    echo
    echo "All phases will now use '$provider' unless specifically overridden."
}

# Test provider with timing
cmd_provider_test() {
    local provider="${1:-}"

    if [[ -z "$provider" ]]; then
        # Test all providers
        echo "Testing all providers..."
        echo
        printf "%-12s %-12s %-10s %s\n" "PROVIDER" "STATUS" "LATENCY" "MODEL"
        printf "%-12s %-12s %-10s %s\n" "--------" "------" "-------" "-----"

        for prov in $(provider_list | cut -d: -f1); do
            _test_provider_row "$prov"
        done
        return 0
    fi

    if ! provider_is_registered "$provider"; then
        echo "Error: Unknown provider '$provider'"
        echo "Available providers: $(provider_list | cut -d: -f1 | tr '\n' ' ')"
        return 1
    fi

    echo "Testing provider: $provider"
    echo

    # Validate first
    echo -n "Validation: "
    if ! provider_validate "$provider"; then
        echo "✗ Failed (provider not available)"
        return 1
    fi
    echo "✓ Passed"

    # Test with simple prompt
    echo -n "Response test: "

    local temp_prompt
    temp_prompt=$(mktemp)
    echo "Respond with exactly: OK" > "$temp_prompt"

    local start_time end_time duration response
    start_time=$(date +%s%3N)

    # Get model for high capability
    local model
    model="$(provider_resolve_model "$provider" "high" 2>/dev/null)"

    if [[ -z "$model" ]]; then
        echo "✗ No model configured for high capability"
        rm -f "$temp_prompt"
        return 1
    fi

    if response=$(provider_invoke "$provider" "$model" "$temp_prompt" 2>&1); then
        end_time=$(date +%s%3N)
        duration=$((end_time - start_time))
        echo "✓ Passed (${duration}ms)"
        echo
        echo "Model: $model"
        echo "Response preview: ${response:0:100}..."
    else
        echo "✗ Failed"
        echo "Error: $response"
        rm -f "$temp_prompt"
        return 1
    fi

    rm -f "$temp_prompt"
}

# Helper to test a single provider and print row
_test_provider_row() {
    local provider="$1"
    local status="✗ Failed"
    local latency="-"
    local model="-"

    if provider_validate "$provider" 2>/dev/null; then
        model="$(provider_resolve_model "$provider" "high" 2>/dev/null || echo "-")"

        # Quick ping test
        local temp_prompt start_time end_time
        temp_prompt=$(mktemp)
        echo "Say: OK" > "$temp_prompt"
        start_time=$(date +%s%3N)

        if provider_invoke "$provider" "$model" "$temp_prompt" >/dev/null 2>&1; then
            end_time=$(date +%s%3N)
            latency="$((end_time - start_time))ms"
            status="${COLOR_GREEN}✓ OK${COLOR_RESET}"
        fi

        rm -f "$temp_prompt"
    fi

    printf "%-12s %-12b %-10s %s\n" "$provider" "$status" "$latency" "$model"
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
        set-default)
            cmd_provider_set_default "$@"
            ;;
        test)
            cmd_provider_test "$@"
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