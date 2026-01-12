#!/usr/bin/env bash
# workflow arch - Generate architecture document from specifications
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
# shellcheck source=src/lib/hitl.sh
source "$LIB_DIR/hitl.sh"

# cmd_arch - Generate architecture document from specifications
cmd_arch() {
    local review=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --review)
                review=true
                shift
                ;;
            --help)
                _arch_help
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

    log_info "Found ${#spec_files[@]} specification files"

    # Check if architecture already exists
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    local arch_exists=false
    if [[ -f "$arch_file" ]]; then
        arch_exists=true
        log_warn "Architecture document already exists: $arch_file"

        # Check if implementation plan exists
        if [[ -f "$project_root/docs/IMPLEMENTATION_PLAN.md" ]]; then
            echo ""
            log_warn "${COLOR_YELLOW}⚠ WARNING${COLOR_RESET}: Regenerating architecture after implementation plan exists"
            log_warn "This may invalidate the current plan. Consider:"
            log_warn "  1. Review the new architecture carefully"
            log_warn "  2. Run 'workflow plan --regen' to update the implementation plan"
            echo ""
        fi
    fi

    # Get model from config
    local model
    model="$(config_get MODEL_ARCH)"

    # Generate or review architecture
    if [[ "$review" == "true" ]]; then
        log_info "Starting interactive architecture review session..."

        # Present review approach alternatives
        local review_approach
        review_approach=$(present_alternatives \
            "Architecture Review Approach" \
            "AI-Guided Refinement" "Claude identifies improvement areas, you provide feedback" \
            "Structured refinement, clear improvement suggestions, efficient token use" \
            "Requires AI analysis first, may miss user-specific concerns" \
            "Free-Form Feedback" "You provide feedback directly on current architecture" \
            "Direct user control, immediate refinement on specific areas" \
            "Requires knowledge of architecture patterns, less structured" \
            "Guided Templates" "Step-by-step refinement through specific architecture concerns" \
            "Very thorough, systematic coverage of all architecture aspects" \
            "Takes more time, more interactive back-and-forth" \
            "A")

        case "$review_approach" in
            A) _arch_review "$project_root" "${spec_files[@]}" ;;
            B) _arch_review_freeform "$project_root" ;;
            C) _arch_review_guided "$project_root" ;;
            *) log_error "Invalid choice"; return 1 ;;
        esac
    else
        log_info "Generating architecture document..."
        _arch_generate "$project_root" "$model" "${spec_files[@]}"
    fi

    if [[ -f "$arch_file" ]]; then
        echo ""
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Architecture document created: $arch_file"

        if [[ "$arch_exists" == "true" ]]; then
            log_info "Architecture document was updated (overwrote existing version)"
        fi

        echo ""
        log_info "Next step: Run 'workflow plan' to generate implementation plan"
    else
        die "Failed to generate architecture document"
    fi
}

# _arch_help - Show help for arch command
_arch_help() {
    cat <<'EOF'
USAGE:
    workflow arch [OPTIONS]

DESCRIPTION:
    Generate system architecture document from feature specifications.

    Analyzes all spec files to create a unified architecture defining:
    - Component boundaries and responsibilities
    - Data models and relationships
    - API contracts and interfaces
    - Technology decisions and conventions
    - Non-functional requirements

OPTIONS:
    --review        Interactive refinement session with Claude
    --help          Show this help message

WORKFLOW:
    1. Run 'workflow specs' to generate specification files
    2. Run 'workflow arch' to create architecture document
    3. Run 'workflow plan' to generate implementation plan

EXAMPLES:
    # Generate architecture document
    workflow arch

    # Interactive review and refinement
    workflow arch --review

INPUTS:
    specs/*.md                   Feature specification files

OUTPUTS:
    docs/ARCHITECTURE.md         System architecture document

CONFIGURATION:
    MODEL_ARCH                   Claude model for architecture (default: opus)

EXIT CODES:
    0    Success
    1    Error (no specs found, Claude API failure, invalid options)

NOTES:
    If regenerating architecture after implementation plan exists, you should
    run 'workflow plan --regen' to update the plan with new architecture.
EOF
}

# _arch_generate - Generate architecture document
# Arguments: project_root, model, spec_files...
_arch_generate() {
    local project_root="$1"
    local model="$2"
    shift 2
    local -a spec_files=("$@")

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_arch.md" "$project_root")"; then
        die "Prompt template not found"
    fi

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
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# INPUT: Feature Specifications"
        echo ""
        echo "Below are all the feature specifications for this system."
        echo "Analyze them to understand:"
        echo "- Common patterns and shared concerns"
        echo "- Data relationships and dependencies"
        echo "- Integration points between features"
        echo "- Technology requirements"
        echo ""
        echo "$all_specs"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Generate a comprehensive architecture document"
        echo "2. Follow the template structure provided above"
        echo "3. Ensure all features from the specs are architecturally supported"
        echo "4. Define clear component boundaries and interfaces"
        echo "5. Include code examples in Conventions section"
        echo "6. Address security, performance, and scalability"
        echo "7. Output ONLY the markdown architecture document (no explanations)"
    } > "$temp_prompt"

    # Invoke Claude
    log_info "Invoking Claude for architecture generation..."
    local response
    if ! response=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Claude invocation failed. Check your API key and connection."
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write architecture document
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    echo "$response" > "$arch_file"

    log_info "Architecture document generated: $arch_file"
}

# _arch_review_freeform - Free-form architecture refinement (Option B)
# Arguments: project_root
_arch_review_freeform() {
    local project_root="$1"
    local model
    model="$(config_get MODEL_ARCH)"

    local arch_file="$project_root/docs/ARCHITECTURE.md"
    local current_arch
    current_arch="$(cat "$arch_file")"

    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_arch.md" "$project_root")"; then
        log_error "Prompt template not found"
        return 1
    fi

    log_info "Starting free-form architecture refinement..."
    local max_rounds=3
    local current_round=0
    local all_feedback=""

    while [[ $current_round -lt $max_rounds ]]; do
        ((current_round++))

        local feedback
        if ! feedback=$(hitl_prompt "Provide feedback on the architecture (or press Enter to finish):" "clarification" ""); then
            log_info "Finishing refinement..."
            break
        fi

        if [[ -z "$feedback" ]]; then
            log_info "Refinement complete"
            break
        fi

        all_feedback+="**Round $current_round:** $feedback"$'\n\n'

        local refine_prompt
        refine_prompt="$(mktemp)"
        trap 'rm -f "$refine_prompt"' EXIT

        {
            cat "$prompt_file"
            echo ""
            echo "---"
            echo ""
            echo "# CURRENT ARCHITECTURE"
            echo ""
            echo "$current_arch"
            echo ""
            echo "---"
            echo ""
            echo "# USER FEEDBACK"
            echo ""
            echo "$all_feedback"
            echo ""
            echo "---"
            echo ""
            echo "**Instructions**: Refine the architecture based on the feedback. Output ONLY the updated architecture document."
        } > "$refine_prompt"

        local refined_arch
        if ! refined_arch=$(claude_invoke "$model" "$refine_prompt"); then
            rm -f "$refine_prompt"
            trap - EXIT
            log_error "Refinement failed"
            break
        fi

        rm -f "$refine_prompt"
        trap - EXIT

        current_arch="$refined_arch"
        echo "$current_arch" > "$arch_file"
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Architecture updated (round $current_round)"
    done

    echo ""
    log_info "Free-form refinement complete"
}

# _arch_review_guided - Guided template-based architecture refinement (Option C)
# Arguments: project_root
_arch_review_guided() {
    local project_root="$1"
    local model
    model="$(config_get MODEL_ARCH)"

    local arch_file="$project_root/docs/ARCHITECTURE.md"
    local current_arch
    current_arch="$(cat "$arch_file")"

    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_arch.md" "$project_root")"; then
        log_error "Prompt template not found"
        return 1
    fi

    log_info "Starting guided architecture refinement..."

    # Pre-defined refinement areas for guided review
    local areas=(
        "Components & Services: Are the component boundaries and responsibilities clear?"
        "Data Flow: How data moves between components - is it well-documented?"
        "API Design: Are API contracts clear and consistent?"
        "Error Handling: How are errors propagated and handled?"
        "Scalability: What are the scaling limits and how are they addressed?"
    )

    local all_feedback=""
    local max_rounds=${#areas[@]}
    local current_round=0

    for area in "${areas[@]}"; do
        ((current_round++))

        log_info "Review area $current_round/$max_rounds: $area"

        local feedback
        if ! feedback=$(hitl_prompt "$area" "clarification" ""); then
            log_info "Skipping this area..."
            continue
        fi

        if [[ -z "$feedback" ]]; then
            continue
        fi

        all_feedback+="**Area: $area**"$'\n'
        all_feedback+="Feedback: $feedback"$'\n\n'
    done

    if [[ -z "$all_feedback" ]]; then
        log_info "No feedback provided"
        return 0
    fi

    # Generate refined architecture with all collected feedback
    local refine_prompt
    refine_prompt="$(mktemp)"
    trap 'rm -f "$refine_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# CURRENT ARCHITECTURE"
        echo ""
        echo "$current_arch"
        echo ""
        echo "---"
        echo ""
        echo "# STRUCTURED FEEDBACK"
        echo ""
        echo "$all_feedback"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**: Refine the architecture addressing all feedback areas. Output ONLY the updated architecture document."
    } > "$refine_prompt"

    local refined_arch
    if ! refined_arch=$(claude_invoke "$model" "$refine_prompt"); then
        rm -f "$refine_prompt"
        trap - EXIT
        log_error "Refinement failed"
        return 1
    fi

    rm -f "$refine_prompt"
    trap - EXIT

    echo "$refined_arch" > "$arch_file"
    log_info "${COLOR_GREEN}✓${COLOR_RESET} Architecture refined with guided feedback"
    echo ""
    log_info "Guided refinement complete"
}

# _arch_review - Interactive architecture review and refinement (Option A - AI-Guided)
# Arguments: project_root, spec_files...
_arch_review() {
    local project_root="$1"
    shift
    local -a spec_files=("$@")

    # Get model from config
    local model
    model="$(config_get MODEL_ARCH)"

    # First generate initial architecture if it doesn't exist
    local arch_file="$project_root/docs/ARCHITECTURE.md"
    if [[ ! -f "$arch_file" ]]; then
        log_info "No existing architecture found, generating initial version..."
        _arch_generate "$project_root" "$model" "${spec_files[@]}"
        echo ""
    fi

    # Read current architecture
    local current_arch
    current_arch="$(cat "$arch_file")"

    log_info "Starting interactive review session..."
    echo ""

    # Get HITL timeout from config
    local hitl_timeout
    hitl_timeout="$(config_get HITL_TIMEOUT)"

    # First, identify specific areas needing refinement (single API call)
    log_info "Analyzing architecture for refinement opportunities..."

    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_arch.md" "$project_root")"; then
        log_error "Prompt template not found"
        return 1
    fi

    local refinement_analysis_prompt
    refinement_analysis_prompt="$(mktemp)"
    trap 'rm -f "$refinement_analysis_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# CURRENT ARCHITECTURE"
        echo ""
        echo "$current_arch"
        echo ""
        echo "---"
        echo ""
        echo "**Task: Architecture Review Analysis**"
        echo ""
        echo "Suggest 3-5 specific areas in the architecture that could be improved."
        echo "Format as JSON:"
        echo "{"
        echo "  \"areas\": ["
        echo "    {\"id\": 1, \"title\": \"Area\", \"description\": \"What could be improved\"},"
        echo "    {\"id\": 2, \"title\": \"...\", \"description\": \"...\"}"
        echo "  ]"
        echo "}"
        echo ""
        echo "Then provide the complete current architecture unchanged."
    } > "$refinement_analysis_prompt"

    log_info "Invoking Claude to identify refinement areas..."
    local analysis_response
    if ! analysis_response=$(claude_invoke "$model" "$refinement_analysis_prompt"); then
        rm -f "$refinement_analysis_prompt"
        trap - EXIT
        log_error "Analysis failed, proceeding to manual review"
        return 1
    fi

    rm -f "$refinement_analysis_prompt"
    trap - EXIT

    # Extract refinement areas from response
    local refinement_areas
    refinement_areas=$(echo "$analysis_response" | sed -n '/```json/,/```/p' | sed '1d;$d')
    if [[ -z "$refinement_areas" ]]; then
        refinement_areas=$(echo "$analysis_response" | sed -n '/{/,/}/p' | head -1)
    fi

    # Display suggested areas if found
    if [[ -n "$refinement_areas" ]] && echo "$refinement_areas" | jq . >/dev/null 2>&1; then
        log_info "Suggested refinement areas:"
        echo "$refinement_areas" | jq -r '.areas[]? | "\(.id). \(.title): \(.description)"' | sed 's/^/  - /'
        echo ""
    fi

    # Interactive refinement loop (max 3 rounds)
    local max_rounds=3
    local current_round=0
    local all_feedback=""

    while [[ $current_round -lt $max_rounds ]]; do
        ((current_round++))

        # Ask for user feedback
        local feedback
        if ! feedback=$(hitl_prompt "Provide architecture feedback (or press Enter to finish):" "clarification" ""); then
            log_info "Timeout or empty response, finalizing architecture..."
            break
        fi

        if [[ -z "$feedback" ]]; then
            log_info "Review complete"
            break
        fi

        log_info "Processing feedback (round $current_round/$max_rounds)..."

        # Accumulate all feedback
        all_feedback+="**Round $current_round:** $feedback"$'\n\n'

        # Create targeted refinement prompt (only sends architecture + feedback, not specs)
        local refine_prompt
        refine_prompt="$(mktemp)"
        trap 'rm -f "$refine_prompt"' EXIT

        {
            cat "$prompt_file"
            echo ""
            echo "---"
            echo ""
            echo "# CURRENT ARCHITECTURE"
            echo ""
            echo "$current_arch"
            echo ""
            echo "---"
            echo ""
            echo "# USER FEEDBACK"
            echo ""
            echo "$all_feedback"
            echo ""
            echo "---"
            echo ""
            echo "**Instructions**:"
            echo "1. Refine the architecture based on the user feedback"
            echo "2. Maintain the template structure"
            echo "3. Keep all good elements from the current architecture"
            echo "4. Address the specific concerns raised in feedback"
            echo "5. Output ONLY the updated markdown architecture document"
        } > "$refine_prompt"

        # Single API call per refinement
        local refined_arch
        if ! refined_arch=$(claude_invoke "$model" "$refine_prompt"); then
            rm -f "$refine_prompt"
            trap - EXIT
            log_error "Refinement failed, keeping current architecture"
            break
        fi

        rm -f "$refine_prompt"
        trap - EXIT

        # Update architecture
        current_arch="$refined_arch"
        echo "$current_arch" > "$arch_file"

        log_info "${COLOR_GREEN}✓${COLOR_RESET} Architecture updated (round $current_round)"
    done

    if [[ $current_round -ge $max_rounds ]]; then
        log_info "Reached maximum refinement rounds ($max_rounds)"
    fi

    echo ""
    log_info "Interactive review complete"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_arch "$@"
fi
