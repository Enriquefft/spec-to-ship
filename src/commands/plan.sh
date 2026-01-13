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
# shellcheck source=src/lib/tempfiles.sh
source "$LIB_DIR/tempfiles.sh"
# shellcheck source=src/lib/context.sh
source "$LIB_DIR/context.sh"

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

    # Present planning approach alternatives (unless milestone-specific)
    local planning_approach="summary"
    if [[ -z "$milestone" ]]; then
        planning_approach=$(present_alternatives \
            "Implementation Planning Approach" \
            "Spec Summaries (Recommended)" "Brief summaries of all specs, fast and efficient" \
            "Low token use, fast planning, sufficient for most projects" \
            "May lose some implementation details" \
            "Full Specifications" "Complete spec content for maximum detail" \
            "Maximum implementation detail, better for complex projects" \
            "3x token use, slower planning, more comprehensive" \
            "Iterative Milestone Planning" "Plan one milestone at a time for better focus" \
            "More targeted planning, better for large projects, iterative refinement" \
            "Slower overall (multiple API calls), more interactive" \
            "A")

        case "$planning_approach" in
            A) planning_approach="summary" ;;
            B) planning_approach="full" ;;
            C) planning_approach="iterative" ;;
            *) log_error "Invalid choice"; return 1 ;;
        esac
    fi

    log_info "Using planning approach: $planning_approach"

    # Perform gap analysis on existing code (using cached context analysis)
    log_info "Scanning src/ directory for gap analysis..."
    local gap_analysis
    gap_analysis="$(context_analyze_code_gap "$project_root")"

    # Generate implementation plan
    if [[ -n "$milestone" ]]; then
        log_info "Generating plan for milestone: $milestone"
        _plan_generate_milestone "$project_root" "$milestone" "${spec_files[@]}"
    else
        log_info "Generating complete implementation plan..."
        _plan_generate "$project_root" "$gap_analysis" "${spec_files[@]}" "$planning_approach"
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

# Note: _analyze_code_gap moved to context.sh as context_analyze_code_gap()
# This provides caching and consistent format across commands

# _generate_spec_summaries - Create brief summaries of all specs
# Arguments: spec_files...
_generate_spec_summaries() {
    local -a spec_files=("$@")
    local summaries=""

    for spec_file in "${spec_files[@]}"; do
        local spec_name
        spec_name="$(basename "$spec_file" .md)"

        # Extract title and first paragraph only
        local title
        title=$(head -1 "$spec_file" | sed 's/^# //')

        local first_para
        first_para=$(sed -n '/^## /,/^## /p' "$spec_file" | head -10 | grep -v "^##" | tr '\n' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        summaries+="- **$spec_name**: $first_para"$'\n'
    done

    echo "$summaries"
}

# _plan_generate - Generate complete implementation plan
# Arguments: project_root, gap_analysis, spec_files..., planning_approach
_plan_generate() {
    local project_root="$1"
    local gap_analysis="$2"
    shift 2
    local planning_approach="${@: -1}"
    local -a spec_files=("${@:1:$#-1}")

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_plan.md" "$project_root")"; then
        die "Prompt template not found"
    fi

    # Load architecture summary (using context compression)
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    local arch_overview
    arch_overview=$(context_summarize_arch "$arch_file")

    # Create combined prompt using centralized temp file management
    local temp_prompt
    temp_prompt="$(tempfile_create)"

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# INPUT: System Architecture Overview"
        echo ""
        echo "$arch_overview"
        echo ""
        echo "---"
        echo ""

        # Add specs based on approach
        case "$planning_approach" in
            full)
                echo "# INPUT: Full Feature Specifications"
                echo ""
                for spec_file in "${spec_files[@]}"; do
                    local spec_name
                    spec_name="$(basename "$spec_file")"
                    echo "---"
                    echo "## Specification: $spec_name"
                    echo ""
                    cat "$spec_file"
                    echo ""
                done
                echo ""
                echo "---"
                echo ""
                ;;
            iterative)
                echo "# INPUT: Feature Specifications Summary (Iterative Mode)"
                echo ""
                log_info "Creating spec summaries (${#spec_files[@]} specs)..."
                local spec_summaries
                spec_summaries="$(_generate_spec_summaries "${spec_files[@]}")"
                echo "$spec_summaries"
                echo ""
                echo "---"
                echo ""
                echo "NOTE: This plan will be generated iteratively by milestone."
                echo "You can refine each milestone before moving to the next."
                echo ""
                echo "---"
                echo ""
                ;;
            summary|*)
                echo "# INPUT: Feature Specifications Summary"
                echo ""
                log_info "Creating spec summaries (${#spec_files[@]} specs)..."
                local spec_summaries
                spec_summaries="$(_generate_spec_summaries "${spec_files[@]}")"
                echo "Full specifications available:"
                echo ""
                echo "$spec_summaries"
                echo ""
                local spec_list=""
                for spec_file in "${spec_files[@]}"; do
                    spec_list+="- $(basename "$spec_file")"$'\n'
                done
                echo "---"
                echo ""
                echo "# Available Specification Files"
                echo ""
                echo "For detailed requirements, refer to these specs in docs/specs/:"
                echo ""
                echo "$spec_list"
                echo ""
                echo "---"
                echo ""
                ;;
        esac

        echo "# INPUT: Gap Analysis"
        echo ""
        echo "$gap_analysis"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Generate a complete implementation plan based on the input"
        echo "2. Organize tasks into milestones following Simple-Lovable-Complete (SLC) approach"
        echo "3. Include explicit task dependencies using 'Dependencies: T001, T002' format"
        echo "4. Derive test requirements from the feature specifications"
        echo "5. Format test requirements as '**Required tests**: - Test 1 - Test 2'"
        echo "6. Consider gap analysis to prioritize missing functionality"
        echo "7. Mark tasks that can run in parallel"
        echo "8. Include task state tracking format: \`status: pending\`"
        echo "9. Output ONLY the markdown implementation plan (no explanations)"
    } > "$temp_prompt"

    # Invoke provider for plan phase
    log_info "Invoking provider for implementation plan generation..."
    local response
    if ! response=$(provider_invoke_for_phase "plan" "$temp_prompt"); then
        tempfile_remove "$temp_prompt"
        die "Provider invocation failed. Check your configuration."
    fi

    tempfile_remove "$temp_prompt"

    # Write implementation plan
    local plan_file="$project_root/docs/IMPLEMENTATION_PLAN.md"
    echo "$response" > "$plan_file"

    log_info "Implementation plan generated: $plan_file"
}

# _plan_generate_milestone - Generate plan for specific milestone
# Arguments: project_root, milestone, spec_files...
_plan_generate_milestone() {
    local project_root="$1"
    local milestone="$2"
    shift 2
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

    # Create milestone-specific prompt using centralized temp file management
    local temp_prompt
    temp_prompt="$(tempfile_create)"

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

    # Invoke provider for plan phase
    log_info "Generating detailed plan for milestone $milestone..."
    local response
    if ! response=$(provider_invoke_for_phase "plan" "$temp_prompt"); then
        tempfile_remove "$temp_prompt"
        die "Provider invocation failed. Check your configuration."
    fi

    tempfile_remove "$temp_prompt"

    # Write milestone plan (append or update)
    local milestone_file="$project_root/docs/PLAN_${milestone}.md"
    echo "$response" > "$milestone_file"

    log_info "Milestone plan generated: $milestone_file"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_plan "$@"
fi
