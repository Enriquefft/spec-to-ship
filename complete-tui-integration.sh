#!/bin/bash
# complete-tui-integration.sh - Finalize TUI integration across all commands

set -euo pipefail

echo "=== Completing TUI Integration ==="
echo ""

# Commands to update
declare -a commands=(
    "specs"
    "arch" 
    "plan"
    "build"
    "gate"
    "status"
    "init"
    "config"
    "provider"
    "diff"
    "explore"
    "ci"
)

# Function to add TUI integration
add_tui_integration() {
    local cmd="$1"
    local file="src/commands/${cmd}.sh"
    
    if [[ ! -f "$file" ]]; then
        echo "⚠ Skipping $cmd - file not found"
        return
    fi
    
    echo "🔧 Updating $cmd..."
    
    # Skip if already integrated
    if grep -q "tui_phase_start" "$file"; then
        echo "  ✓ Already integrated"
        return
    fi
    
    # Backup original
    cp "$file" "${file}.backup"
    
    case "$cmd" in
        specs)
            # Find where specs generation starts
            if grep -q "log_info.*generating.*spec" "$file"; then
                sed -i '/log_info.*generating.*spec/i\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "specs"\\n    else\\n        log_info "Starting specifications generation..."\\n    fi' "$file"
                sed -i '/log_info.*specifications.*generated/a\\n    # Emit phase complete\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_complete "specs" "true" "0"\\n    else\\n        log_info "Specifications generation completed"\\n    fi' "$file"
            fi
            ;;
            
        arch)
            # Add to architecture generation
            sed -i '/config_load/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "arch"\\n    else\\n        log_info "Starting architecture generation..."\\n    fi' "$file"
            # Find success message
            if grep -q "Architecture document generated" "$file"; then
                sed -i '/Architecture document generated/a\\n    # Emit phase complete\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_complete "arch" "true" "0"\\n    else\\n        log_info "Architecture generation completed"\\n    fi' "$file"
            fi
            ;;
            
        plan)
            # Add to planning phase
            sed -i '/config_load/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "plan"\\n    else\\n        log_info "Starting planning phase..."\\n    fi' "$file"
            # Find completion
            sed -i '/Implementation plan generated/a\\n    # Emit phase complete\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_complete "plan" "true" "0"\\n    else\\n        log_info "Planning phase completed"\\n    fi' "$file"
            ;;
            
        build)
            # Add to build phase
            sed -i '/log_info.*build phase/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "build"\\n    else\\n        log_info "Starting build phase..."\\n    fi' "$file"
            ;;
            
        gate)
            # Add to gate validation
            sed -i '/config_load/a\\n    # Emit phase start\\n    if tui_is_enabled 2>/dev/null; then\\n        tui_phase_start "gate"\\n    else\\n        log_info "Starting gate validation..."\\n    fi' "$file"
            ;;
            
        init|config|provider|diff|explore|ci|status)
            # These are utility commands, not phases
            echo "  ℹ $cmd is a utility command, skipping phase integration"
            ;;
    esac
}

# Process all commands
for cmd in "${commands[@]}"; do
    add_tui_integration "$cmd"
done

echo ""
echo "=== Integration Summary ==="
echo ""

# Check results
for cmd in "${commands[@]}"; do
    file="src/commands/${cmd}.sh"
    if [[ -f "$file" ]]; then
        if grep -q "tui_phase_start" "$file"; then
            echo "✓ $cmd - Integrated"
        else
            echo "✗ $cmd - Not integrated"
        fi
    fi
done

echo ""
echo "=== Next Steps ==="
echo ""
echo "1. Test integrated commands:"
echo "   export WORKFLOW_TUI=true"
echo "   workflow specs"
echo "   workflow arch"
echo "   workflow plan"
echo ""
echo "2. When satisfied, remove old logging system:"
echo "   rm src/lib/activity.sh"
echo "   rm src/lib/spinner.sh"
echo ""
echo "3. Commit changes:"
echo "   git add -A"
echo "   git commit -m \"Integrate TUI across all commands\""