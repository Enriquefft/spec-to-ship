#!/usr/bin/env bash
# src/lib/brownfield.sh - Support for existing/brownfield projects

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Project Detection
# ==============================================================================

# brownfield_detect(project_root) - Detect if project is brownfield (has existing code)
# Returns: 0 if brownfield, 1 if greenfield
brownfield_detect() {
    local project_root="${1:-.}"

    # Check for common indicators of existing project
    local indicators=0

    # Source code exists
    if [[ -d "$project_root/src" ]] && [[ -n "$(ls -A "$project_root/src" 2>/dev/null)" ]]; then
        ((indicators++))
    fi

    # Has git history
    if [[ -d "$project_root/.git" ]]; then
        local commit_count
        commit_count=$(cd "$project_root" && git rev-list --count HEAD 2>/dev/null || echo "0")
        if [[ "$commit_count" -gt 5 ]]; then
            ((indicators++))
        fi
    fi

    # Has dependencies installed
    if [[ -d "$project_root/node_modules" ]] || [[ -d "$project_root/.venv" ]] || [[ -d "$project_root/vendor" ]]; then
        ((indicators++))
    fi

    # Has test files
    if find "$project_root" -name "*test*" -o -name "*spec*" 2>/dev/null | grep -q .; then
        ((indicators++))
    fi

    # Has documentation
    if [[ -f "$project_root/README.md" ]] && [[ $(wc -l < "$project_root/README.md") -gt 20 ]]; then
        ((indicators++))
    fi

    # Consider brownfield if 2+ indicators
    [[ $indicators -ge 2 ]]
}

# brownfield_analyze(project_root) - Analyze existing project for integration
brownfield_analyze() {
    local project_root="${1:-.}"

    local analysis=""
    analysis+="# Brownfield Analysis"$'\n\n'
    analysis+="**Project**: $project_root"$'\n'
    analysis+="**Analyzed**: $(date -Iseconds)"$'\n\n'

    # Existing structure
    analysis+="## Existing Structure"$'\n\n'

    # Count existing code
    local -A file_counts
    file_counts=()

    for ext in sh py js ts go rs java; do
        local count
        count=$(find "$project_root" -name "*.$ext" -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l)
        if [[ $count -gt 0 ]]; then
            file_counts["$ext"]=$count
        fi
    done

    analysis+="| Type | Count |"$'\n'
    analysis+="|------|-------|"$'\n'
    for ext in "${!file_counts[@]}"; do
        analysis+="| .$ext | ${file_counts[$ext]} |"$'\n'
    done
    analysis+=$'\n'

    # Existing tests
    analysis+="## Test Coverage"$'\n\n'

    local test_files
    test_files=$(find "$project_root" -name "*test*.sh" -o -name "*test*.py" -o -name "*.test.js" -o -name "*.spec.ts" 2>/dev/null | wc -l)
    analysis+="Test files found: $test_files"$'\n\n'

    # Integration points
    analysis+="## Integration Points"$'\n\n'
    analysis+="Recommended integration approach:"$'\n\n'

    if [[ -f "$project_root/package.json" ]]; then
        analysis+="- **npm scripts**: Add workflow commands to package.json scripts"$'\n'
    fi

    if [[ -f "$project_root/Makefile" ]]; then
        analysis+="- **Makefile**: Add workflow targets to existing Makefile"$'\n'
    fi

    if [[ -d "$project_root/.github" ]]; then
        analysis+="- **GitHub Actions**: Integrate with existing CI workflows"$'\n'
    fi

    if [[ -f "$project_root/.gitlab-ci.yml" ]]; then
        analysis+="- **GitLab CI**: Add workflow stages to pipeline"$'\n'
    fi

    analysis+=$'\n'"## Recommendations"$'\n\n'
    analysis+="1. Run \`workflow explore\` for detailed codebase analysis"$'\n'
    analysis+="2. Create specs that reference existing code structure"$'\n'
    analysis+="3. Use \`--focus\` flag to target specific areas for changes"$'\n'
    analysis+="4. Set up constitution to protect existing patterns"$'\n'

    echo "$analysis"
}

# ==============================================================================
# Gap Analysis
# ==============================================================================

# brownfield_gap_analysis(project_root, spec_file) - Compare spec to existing code
brownfield_gap_analysis() {
    local project_root="${1:-.}"
    local spec_file="${2:-}"

    local analysis=""
    analysis+="# Gap Analysis"$'\n\n'

    if [[ -z "$spec_file" ]] || [[ ! -f "$spec_file" ]]; then
        analysis+="*No spec file provided - showing existing code structure only*"$'\n\n'
    fi

    # Existing functionality
    analysis+="## Existing Functionality"$'\n\n'

    # Commands/functions
    if [[ -d "$project_root/src/commands" ]]; then
        analysis+="### Commands"$'\n\n'
        for cmd_file in "$project_root"/src/commands/*.sh; do
            if [[ -f "$cmd_file" ]]; then
                local cmd_name
                cmd_name=$(basename "$cmd_file" .sh)
                analysis+="- \`$cmd_name\`"$'\n'
            fi
        done
        analysis+=$'\n'
    fi

    # Libraries
    if [[ -d "$project_root/src/lib" ]]; then
        analysis+="### Libraries"$'\n\n'
        for lib_file in "$project_root"/src/lib/*.sh; do
            if [[ -f "$lib_file" ]]; then
                local lib_name
                lib_name=$(basename "$lib_file" .sh)
                local func_count
                func_count=$(grep -c "^[a-z_]*() {" "$lib_file" 2>/dev/null || echo "0")
                analysis+="- \`$lib_name\` ($func_count functions)"$'\n'
            fi
        done
        analysis+=$'\n'
    fi

    # If spec provided, analyze gaps
    if [[ -n "$spec_file" ]] && [[ -f "$spec_file" ]]; then
        analysis+="## Spec Requirements"$'\n\n'

        # Extract features from spec (look for ## or ### headers)
        analysis+="Features in spec:"$'\n'
        grep -E "^#{2,3} " "$spec_file" | head -20 | sed 's/^/- /'
        analysis+=$'\n\n'

        analysis+="## Gaps Identified"$'\n\n'
        analysis+="*Manual review recommended to identify specific gaps*"$'\n'
    fi

    echo "$analysis"
}

# ==============================================================================
# Incremental Adoption
# ==============================================================================

# brownfield_init(project_root) - Initialize workflow in existing project
brownfield_init() {
    local project_root="${1:-.}"

    log_info "Initializing workflow for brownfield project..."

    # Create .workflow directory
    local workflow_dir="$project_root/.workflow"
    mkdir -p "$workflow_dir"

    # Create minimal config
    if [[ ! -f "$workflow_dir/config.sh" ]]; then
        cat > "$workflow_dir/config.sh" <<'EOF'
# Workflow configuration for brownfield project
# Auto-generated by workflow init --brownfield

# Provider settings (adjust as needed)
PROVIDER_DEFAULT="claude"

# HITL settings - more conservative for existing codebases
HITL_ENABLED="true"
HITL_MODE="milestone"

# Build settings - respect existing patterns
BUILD_BACKPRESSURE_TESTS="true"
BUILD_BACKPRESSURE_LINT="true"

# Brownfield-specific settings
BROWNFIELD_MODE="true"
BROWNFIELD_PROTECT_PATTERNS="true"
EOF
        log_info "Created config: $workflow_dir/config.sh"
    fi

    # Create docs directory if needed
    mkdir -p "$project_root/docs"
    mkdir -p "$project_root/specs"

    # Generate exploration report
    log_info "Running initial exploration..."

    # Run brownfield analysis
    local analysis
    analysis=$(brownfield_analyze "$project_root")
    echo "$analysis" > "$project_root/docs/BROWNFIELD_ANALYSIS.md"
    log_info "Created: docs/BROWNFIELD_ANALYSIS.md"

    echo ""
    log_info "${COLOR_GREEN}✓${COLOR_RESET} Brownfield initialization complete"
    echo ""
    echo "Next steps:"
    echo "  1. Review docs/BROWNFIELD_ANALYSIS.md"
    echo "  2. Run 'workflow explore' for detailed analysis"
    echo "  3. Create specs in specs/ directory"
    echo "  4. Run 'workflow constitution' to establish governance"
}

# brownfield_protect_patterns(project_root) - Generate constitution from existing patterns
brownfield_protect_patterns() {
    local project_root="${1:-.}"

    local constitution=""
    constitution+="# Project Constitution (Auto-generated)"$'\n\n'
    constitution+="**Generated**: $(date -Iseconds)"$'\n'
    constitution+="**Source**: Existing codebase patterns"$'\n\n'

    constitution+="## Principles"$'\n\n'

    # Detect existing patterns and generate protective principles
    local principle_num=0

    # 1. Directory structure
    ((principle_num++))
    constitution+="$principle_num. **Directory Structure**: Maintain existing directory organization. "
    if [[ -d "$project_root/src/commands" ]]; then
        constitution+="Commands in src/commands/, libraries in src/lib/."
    fi
    constitution+=$'\n\n'

    # 2. Naming conventions
    ((principle_num++))
    constitution+="$principle_num. **Naming Conventions**: Follow existing naming patterns. "
    local sample_func
    sample_func=$(grep -rh "^[a-z_]*() {" "$project_root/src" 2>/dev/null | head -1 | cut -d'(' -f1)
    if [[ -n "$sample_func" ]]; then
        constitution+="Functions use snake_case (e.g., \`$sample_func\`)."
    fi
    constitution+=$'\n\n'

    # 3. Error handling
    ((principle_num++))
    if grep -rq "set -euo pipefail" "$project_root/src" 2>/dev/null; then
        constitution+="$principle_num. **Error Handling**: Use strict mode (\`set -euo pipefail\`) in all scripts."$'\n\n'
    fi

    # 4. Documentation
    ((principle_num++))
    if grep -rq "^# [a-z]" "$project_root/src" 2>/dev/null; then
        constitution+="$principle_num. **Documentation**: Add file-level comments explaining purpose. Document public functions."$'\n\n'
    fi

    # 5. Testing
    ((principle_num++))
    if [[ -d "$project_root/tests" ]]; then
        local test_framework=""
        if ls "$project_root/tests"/*.bats &>/dev/null; then
            test_framework="bats"
        elif ls "$project_root/tests"/*.py &>/dev/null; then
            test_framework="pytest"
        fi
        constitution+="$principle_num. **Testing**: All new functionality must have tests"
        if [[ -n "$test_framework" ]]; then
            constitution+=" using $test_framework framework"
        fi
        constitution+="."$'\n\n'
    fi

    constitution+="## Enforcement"$'\n\n'
    constitution+="- **Gate**: Build phase validates against these principles"$'\n'
    constitution+="- **Override**: Use \`--force\` flag with documented justification"$'\n'

    echo "$constitution"
}
