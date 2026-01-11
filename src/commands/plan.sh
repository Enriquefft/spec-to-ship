#!/usr/bin/env bash
# workflow plan - Generate implementation plan from specs and architecture
set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=src/lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=src/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=src/lib/claude.sh
source "$LIB_DIR/claude.sh"

# cmd_plan - Generate implementation plan from specifications and architecture
cmd_plan() {
    local regen=false
    local milestone=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --regen)
                regen=true
                shift
                ;;
            --milestone)
                if [[ -z "${2:-}" ]]; then
                    die "Option --milestone requires an argument"
                fi
                milestone="$2"
                shift 2
                ;;
            --help)
                _plan_help
                return 0
                ;;
            --*)
                die "Unknown option: $1"
                ;;
            *)
                die "Unexpected argument: $1"
                ;;
        esac
    done

    # Load config
    config_load

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Check for spec files
    local specs_dir="$project_root/specs"
    if [[ ! -d "$specs_dir" ]]; then
        die "Specs directory not found: $specs_dir

Run 'workflow specs' first to generate specification files."
    fi

    # Find all spec files
    local -a spec_files=()
    while IFS= read -r -d '' spec_file; do
        spec_files+=("$spec_file")
    done < <(find "$specs_dir" -name "*.md" -type f -print0 2>/dev/null | sort -z)

    if [[ ${#spec_files[@]} -eq 0 ]]; then
        die "No spec files found in: $specs_dir

Run 'workflow specs' first to generate specification files."
    fi

    # Check for architecture document
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    if [[ ! -f "$arch_file" ]]; then
        die "Architecture document not found: $arch_file

Run 'workflow arch' first to generate architecture document."
    fi

    # Check if implementation plan already exists
    local plan_file="$project_root/docs/IMPLEMENTATION_PLAN.md"
    local plan_exists=false
    if [[ -f "$plan_file" ]]; then
        plan_exists=true
        if [[ "$regen" != "true" ]]; then
            die "Implementation plan already exists: $plan_file

Use --regen to regenerate the plan (this will overwrite existing plan)."
        fi
        log_warn "Regenerating implementation plan (overwrites existing)"
    fi

    log_info "Found ${#spec_files[@]} specification files"
    log_info "Loading architecture document"

    # Get model from config
    local model
    model="$(config_get MODEL_PLAN)"

    # Perform gap analysis on existing code
    log_info "Scanning src/ directory for gap analysis..."
    local gap_analysis
    gap_analysis="$(_analyze_code_gap "$project_root")"

    # Generate implementation plan
    if [[ -n "$milestone" ]]; then
        log_info "Generating plan for milestone: $milestone"
        _plan_generate_milestone "$project_root" "$model" "$milestone" "${spec_files[@]}"
    else
        log_info "Generating complete implementation plan..."
        _plan_generate "$project_root" "$model" "$gap_analysis" "${spec_files[@]}"
    fi

    if [[ -f "$plan_file" ]]; then
        echo ""
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Implementation plan created: $plan_file"

        if [[ "$plan_exists" == "true" ]]; then
            log_info "Plan was regenerated (overwrote existing version)"
        fi

        echo ""
        log_info "Next step: Run 'workflow build' to begin autonomous implementation"
    else
        die "Failed to generate implementation plan"
    fi
}

# _plan_help - Show help for plan command
_plan_help() {
    cat <<'EOF'
USAGE:
    workflow plan [OPTIONS]

DESCRIPTION:
    Generate implementation plan from specifications and architecture.

    Creates a detailed, milestone-based implementation plan with:
    - Ordered tasks with dependencies
    - Test requirements derived from acceptance criteria
    - Parallel execution opportunities
    - Gap analysis comparing specs vs. existing code

OPTIONS:
    --regen                  Regenerate plan (overwrite existing)
    --milestone MILESTONE    Generate plan for specific milestone only
    --help                   Show this help message

WORKFLOW:
    1. Run 'workflow specs' to generate specification files
    2. Run 'workflow arch' to create architecture document
    3. Run 'workflow plan' to generate implementation plan
    4. Run 'workflow build' to begin implementation

EXAMPLES:
    # Generate complete implementation plan
    workflow plan

    # Regenerate existing plan
    workflow plan --regen

    # Generate tasks for specific milestone
    workflow plan --milestone M1

INPUTS:
    specs/*.md               Feature specification files
    docs/ARCHITECTURE.md     System architecture document
    src/*                    Existing code (for gap analysis)

OUTPUTS:
    docs/IMPLEMENTATION_PLAN.md    Implementation plan with tasks

CONFIGURATION:
    MODEL_PLAN               Claude model for planning (default: opus)

EXIT CODES:
    0    Success
    1    Error (no specs/arch found, Claude API failure, invalid options)

NOTES:
    The plan includes task dependencies and state tracking. Tasks are
    organized into milestones following Simple-Lovable-Complete (SLC) approach.
EOF
}

# _analyze_code_gap - Scan src/ directory and analyze gap between specs and existing code
# Arguments: project_root
_analyze_code_gap() {
    local project_root="$1"
    local src_dir="$project_root/src"

    local gap_analysis=""

    if [[ ! -d "$src_dir" ]]; then
        gap_analysis="No src/ directory found. Starting from scratch."
        echo "$gap_analysis"
        return 0
    fi

    # Count files by type
    local file_count
    file_count=$(find "$src_dir" -type f 2>/dev/null | wc -l)

    if [[ $file_count -eq 0 ]]; then
        gap_analysis="src/ directory exists but is empty. Starting from scratch."
        echo "$gap_analysis"
        return 0
    fi

    log_debug "Found $file_count files in src/"

    # Get file tree structure
    local tree_output
    if command -v tree &> /dev/null; then
        tree_output=$(tree -L 3 -I 'node_modules|.git' "$src_dir" 2>/dev/null || echo "")
    else
        tree_output=$(find "$src_dir" -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | head -50 | sort)
    fi

    # Build gap analysis report
    gap_analysis+="## Existing Code Analysis"$'\n'
    gap_analysis+=""$'\n'
    gap_analysis+="**File Count**: $file_count files in src/"$'\n'
    gap_analysis+=""$'\n'
    gap_analysis+="**Directory Structure**:"$'\n'
    gap_analysis+='```'$'\n'
    gap_analysis+="$tree_output"$'\n'
    gap_analysis+='```'$'\n'
    gap_analysis+=""$'\n'
    gap_analysis+="**Gap Analysis Instructions**:"$'\n'
    gap_analysis+="- Compare existing code against specification requirements"$'\n'
    gap_analysis+="- Identify what's already implemented vs. what needs to be built"$'\n'
    gap_analysis+="- Prioritize unimplemented features and missing functionality"$'\n'
    gap_analysis+="- Note any existing code that may need refactoring or updates"$'\n'

    echo "$gap_analysis"
}

# _plan_generate - Generate complete implementation plan
# Arguments: project_root, model, gap_analysis, spec_files...
_plan_generate() {
    local project_root="$1"
    local model="$2"
    local gap_analysis="$3"
    shift 3
    local -a spec_files=("$@")

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_plan.md" "$project_root")"; then
        die "Prompt template not found"
    fi

    # Load architecture
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    local arch_content
    arch_content="$(cat "$arch_file")"

    # Combine all spec files
    log_info "Loading ${#spec_files[@]} specification files..."
    local all_specs=""
    for spec_file in "${spec_files[@]}"; do
        local spec_name
        spec_name="$(basename "$spec_file")"
        log_debug "  - $spec_name"

        all_specs+="---"$'\n'
        all_specs+="## Specification: $spec_name"$'\n'
        all_specs+=""$'\n'
        all_specs+="$(cat "$spec_file")"$'\n'
        all_specs+=""$'\n'
    done

    # Create combined prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "${temp_prompt:-}"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# INPUT: System Architecture"
        echo ""
        echo "$arch_content"
        echo ""
        echo "---"
        echo ""
        echo "# INPUT: Feature Specifications"
        echo ""
        echo "$all_specs"
        echo ""
        echo "---"
        echo ""
        echo "# INPUT: Gap Analysis"
        echo ""
        echo "$gap_analysis"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Generate a complete implementation plan"
        echo "2. Organize tasks into milestones following Simple-Lovable-Complete (SLC) approach"
        echo "3. Include explicit task dependencies using 'Dependencies: T001, T002' format"
        echo "4. Derive test requirements from acceptance criteria in specs"
        echo "5. Format test requirements as '**Required tests**: - Test 1 - Test 2'"
        echo "6. Consider gap analysis to prioritize missing functionality"
        echo "7. Mark tasks that can run in parallel"
        echo "8. Include task state tracking format: \`status: pending\`"
        echo "9. Output ONLY the markdown implementation plan (no explanations)"
    } > "$temp_prompt"

    # Invoke Claude
    log_info "Invoking Claude for implementation plan generation..."
    local response
    if ! response=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Claude invocation failed. Check your API key and connection."
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write implementation plan
    local plan_file="$project_root/docs/IMPLEMENTATION_PLAN.md"
    echo "$response" > "$plan_file"

    log_info "Implementation plan generated: $plan_file"
}

# _plan_generate_milestone - Generate plan for specific milestone
# Arguments: project_root, model, milestone, spec_files...
_plan_generate_milestone() {
    local project_root="$1"
    local model="$2"
    local milestone="$3"
    shift 3
    local -a spec_files=("$@")

    # Check if full plan exists
    local plan_file="$project_root/docs/IMPLEMENTATION_PLAN.md"
    if [[ ! -f "$plan_file" ]]; then
        die "No implementation plan found. Generate full plan first with 'workflow plan'"
    fi

    # Load existing plan
    local existing_plan
    existing_plan="$(cat "$plan_file")"

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_plan.md" "$project_root")"; then
        die "Prompt template not found"
    fi

    # Create milestone-specific prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "${temp_prompt:-}"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# EXISTING PLAN"
        echo ""
        echo "$existing_plan"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Extract tasks for milestone: $milestone"
        echo "2. Provide detailed breakdown for this milestone only"
        echo "3. Include all task details: dependencies, tests, acceptance criteria"
        echo "4. Output ONLY the milestone section with tasks"
    } > "$temp_prompt"

    # Invoke Claude
    log_info "Generating detailed plan for milestone $milestone..."
    local response
    if ! response=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Claude invocation failed. Check your API key and connection."
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write milestone plan (append or update)
    local milestone_file="$project_root/docs/PLAN_${milestone}.md"
    echo "$response" > "$milestone_file"

    log_info "Milestone plan generated: $milestone_file"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_plan "$@"
fi
