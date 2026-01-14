#!/bin/bash
# integrate-tui-phases.sh - Add TUI integration to all commands

set -euo pipefail

echo "=== Integrating TUI into all workflow phases ==="

# List of commands to update
commands=("arch" "specs" "plan" "build" "gate" "status")

# Function to add phase tracking to a command
add_phase_tracking() {
    local cmd="$1"
    local file="src/commands/${cmd}.sh"
    
    if [[ ! -f "$file" ]]; then
        echo "Skipping $cmd - file not found"
        return
    fi
    
    echo "Processing $cmd..."
    
    # Find the main function and add phase start
    # Pattern: log_info "Starting <phase> phase..."
    
    case "$cmd" in
        arch)
            # Add after config_load
            sed -i '/config_load/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "arch"\\n    else\\n        log_info "Starting architecture phase..."\\n    fi' "$file"
            ;;
        specs)
            sed -i '/log_info.*specification/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "specs"\\n    else\\n        log_info "Starting specification generation..."\\n    fi' "$file"
            ;;
        plan)
            sed -i '/log_info.*planning/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "plan"\\n    else\\n        log_info "Starting planning phase..."\\n    fi' "$file"
            ;;
        build)
            sed -i '/log_info.*build phase/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "build"\\n    else\\n        log_info "Starting build phase..."\\n    fi' "$file"
            ;;
        gate)
            sed -i '/log_info.*gate phase/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "gate"\\n    else\\n        log_info "Starting gate validation..."\\n    fi' "$file"
            ;;
        status)
            # Status is special - not really a phase
            ;;
    esac
    
    # Add phase complete before exit/success
    case "$cmd" in
        arch|specs|plan|build|gate)
            # Find successful completion patterns
            sed -i '/log_info.*completed/a\\n    # Emit phase complete\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_complete "'$cmd'" "true" "0"\\n    fi' "$file"
            ;;
    esac
}

# Process all commands
for cmd in "${commands[@]}"; do
    add_phase_tracking "$cmd"
done

echo ""
echo "=== Integration complete! ==="
echo ""
echo "Next steps:"
echo "1. Review the changes in src/commands/"
echo "2. Test with: WORKFLOW_TUI=true workflow <command>"
echo "3. Remove old activity.sh and spinner.sh when ready"