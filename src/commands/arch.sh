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
        _arch_review "$project_root" "${spec_files[@]}"
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
    local prompt_file="$project_root/src/prompts/PROMPT_arch.md"
    if [[ ! -f "$prompt_file" ]]; then
        die "Prompt template not found: $prompt_file"
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

# _arch_review - Interactive architecture review and refinement
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
    log_info "Current architecture loaded. You can now refine it interactively."
    echo ""

    # Get HITL timeout from config
    local hitl_timeout
    hitl_timeout="$(config_get HITL_TIMEOUT)"

    # Interactive refinement loop (max 5 rounds)
    local max_rounds=5
    local current_round=0
    local refinements=""

    while [[ $current_round -lt $max_rounds ]]; do
        ((current_round++))

        echo ""
        log_info "Review round $current_round/$max_rounds"
        echo ""

        # Ask for feedback
        local feedback
        if ! feedback=$(hitl_prompt "Review the architecture and provide feedback (or press Enter to finish):" "$hitl_timeout"); then
            log_info "Timeout or empty response, finalizing architecture..."
            break
        fi

        # Empty response means user is done
        if [[ -z "$feedback" ]]; then
            log_info "No feedback provided, architecture review complete"
            break
        fi

        log_info "Processing feedback..."

        # Accumulate refinements
        refinements+="### Round $current_round Feedback:"$'\n'
        refinements+="$feedback"$'\n'
        refinements+=""$'\n'

        # Get prompt template
        local prompt_file="$project_root/src/prompts/PROMPT_arch.md"

        # Create refinement prompt
        local temp_prompt
        temp_prompt="$(mktemp)"
        trap 'rm -f "$temp_prompt"' EXIT

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
            echo "$refinements"
            echo ""
            echo "---"
            echo ""
            echo "**Instructions**:"
            echo "1. Refine the architecture based on the user feedback"
            echo "2. Maintain the template structure"
            echo "3. Keep all good elements from the current architecture"
            echo "4. Address the specific concerns raised in feedback"
            echo "5. Output ONLY the updated markdown architecture document"
        } > "$temp_prompt"

        # Invoke Claude for refinement
        local response
        if ! response=$(claude_invoke "$model" "$temp_prompt"); then
            rm -f "$temp_prompt"
            trap - EXIT
            log_error "Claude invocation failed, keeping current architecture"
            break
        fi

        rm -f "$temp_prompt"
        trap - EXIT

        # Update architecture
        current_arch="$response"
        echo "$current_arch" > "$arch_file"

        log_info "${COLOR_GREEN}✓${COLOR_RESET} Architecture updated based on feedback"
    done

    if [[ $current_round -ge $max_rounds ]]; then
        log_info "Reached maximum review rounds ($max_rounds)"
    fi

    echo ""
    log_info "Interactive review complete"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_arch "$@"
fi
