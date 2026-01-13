#!/usr/bin/env bash
# workflow constitution - Generate project constitution with governance principles
set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=src/lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=src/lib/provider.sh
source "$LIB_DIR/provider.sh"
# shellcheck source=src/lib/hitl.sh
source "$LIB_DIR/hitl.sh"
# shellcheck source=src/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=src/lib/brownfield.sh
source "$LIB_DIR/brownfield.sh"
# shellcheck source=src/lib/constitution.sh
source "$LIB_DIR/constitution.sh"
# shellcheck source=src/lib/tempfiles.sh
source "$LIB_DIR/tempfiles.sh"

# Show help for constitution command
_constitution_help() {
    cat <<'EOF'
USAGE:
    workflow constitution [OPTIONS]

DESCRIPTION:
    Generate a project constitution - a governance document defining core
    principles, constraints, and quality standards that guide all development.

    The constitution is generated in three phases:
    1. AI Generation: Claude analyzes PRD and codebase to propose principles
    2. Interactive Q&A: Refine principles through user feedback
    3. User Review: Final review and approval before saving

OPTIONS:
    --force         Regenerate existing constitution (overwrites)
    --skip-qa       Skip Q&A phase (AI generation + review only)
    --from FILE     Use existing file as base instead of AI generation
    --help          Show this help message

WORKFLOW:
    1. Run 'workflow clarify' to generate docs/PRD_STRUCTURED.md
    2. Run 'workflow constitution' to generate .workflow/constitution.md
    3. Run 'workflow specs' to generate specification files

INPUT:
    docs/PRD_STRUCTURED.md - Structured requirements document (required)
    Existing codebase      - Analyzed for brownfield patterns (optional)

OUTPUT:
    .workflow/constitution.md - Project governance document

EXAMPLES:
    # Generate constitution interactively
    workflow constitution

    # Regenerate existing constitution
    workflow constitution --force

    # Skip Q&A phase for faster generation
    workflow constitution --skip-qa

    # Use existing constitution as starting point
    workflow constitution --from docs/OLD_CONSTITUTION.md

CONFIGURATION:
    MODEL_CONSTITUTION       Claude model for constitution generation (default: opus)

EXIT CODES:
    0    Success
    1    Error (PRD not found, Claude API failure, user cancelled)
EOF
}

# cmd_constitution - Main constitution generation command
cmd_constitution() {
    local force=false
    local skip_qa=false
    local from_file=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --skip-qa)
                skip_qa=true
                shift
                ;;
            --from)
                from_file="$2"
                shift 2
                ;;
            --help)
                _constitution_help
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

    log_info "Starting constitution generation..."

    # Load configuration
    config_load

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Phase 0: Prerequisites
    _constitution_check_prerequisites "$project_root" "$force" "$from_file"

    # Determine output file location
    local output_file="$project_root/.workflow/constitution.md"
    ensure_dir "$(dirname "$output_file")"

    # Choose generation path
    if [[ -n "$from_file" ]]; then
        log_info "Using existing file as base: $from_file"
        _constitution_from_file "$from_file" "$output_file" "$project_root" "$skip_qa"
    else
        _constitution_generate "$project_root" "$output_file" "$skip_qa"
    fi

    # Validate generated constitution
    log_info "Validating generated constitution..."
    if ! constitution_load "$project_root"; then
        log_warn "Constitution validation found issues - please review"
    else
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Constitution validated (${#CONSTITUTION_PRINCIPLES[@]} principles)"
    fi

    log_info "${COLOR_GREEN}✓${COLOR_RESET} Constitution generation complete"
    echo ""
    echo "Output: $output_file" >&2
    echo ""
    echo "Next steps:" >&2
    echo "  1. Review the constitution principles" >&2
    echo "  2. Run 'workflow specs' to generate specifications" >&2
    echo ""
}

# _constitution_check_prerequisites - Verify requirements before generation
_constitution_check_prerequisites() {
    local project_root="$1"
    local force="$2"
    local from_file="$3"

    # Check for structured PRD (output of clarify phase)
    local prd_structured="$project_root/docs/PRD_STRUCTURED.md"
    if [[ ! -f "$prd_structured" ]]; then
        die "Structured PRD not found: $prd_structured

Run 'workflow clarify' first to generate the structured PRD."
    fi

    log_info "Found structured PRD: $prd_structured"

    # Check if constitution already exists
    local existing_constitution
    if existing_constitution=$(constitution_find "$project_root" 2>/dev/null); then
        if [[ "$force" != "true" ]]; then
            die "Constitution already exists: $existing_constitution

Use --force to regenerate, or edit the existing file directly."
        fi
        log_warn "Regenerating existing constitution (--force specified)"
    fi

    # If --from specified, verify file exists
    if [[ -n "$from_file" ]] && [[ ! -f "$from_file" ]]; then
        die "Source file not found: $from_file"
    fi
}

# _constitution_generate - Generate constitution using AI
_constitution_generate() {
    local project_root="$1"
    local output_file="$2"
    local skip_qa="$3"

    # Load PRD content
    local prd_file="$project_root/docs/PRD_STRUCTURED.md"
    local prd_content
    prd_content="$(cat "$prd_file")"

    # Detect brownfield patterns
    local brownfield_context=""
    if brownfield_detect "$project_root"; then
        log_info "Brownfield project detected - analyzing patterns..."
        brownfield_context=$(brownfield_protect_patterns "$project_root")
        log_debug "Brownfield patterns:\n$brownfield_context"
    else
        log_info "Greenfield project - no existing patterns to preserve"
    fi

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_constitution.md" "$project_root")"; then
        die "Prompt template not found: PROMPT_constitution.md"
    fi

    # Phase 1: AI Generation
    log_info "Phase 1: Generating draft constitution with AI..."
    local draft_constitution
    draft_constitution=$(_constitution_ai_generate "$prompt_file" "$prd_content" "$brownfield_context")

    if [[ -z "$draft_constitution" ]]; then
        die "Failed to generate constitution draft"
    fi

    # Phase 2: Interactive Q&A (unless skipped)
    local refined_constitution="$draft_constitution"
    if [[ "$skip_qa" != "true" ]]; then
        log_info "Phase 2: Refining constitution with Q&A..."
        refined_constitution=$(_constitution_interactive_qa "$draft_constitution" "$prd_content" "$prompt_file")
    else
        log_info "Phase 2: Skipping Q&A (--skip-qa specified)"
    fi

    # Phase 3: User Review
    log_info "Phase 3: User review..."
    _constitution_user_review "$refined_constitution" "$output_file"
}

# _constitution_ai_generate - Generate draft constitution using AI
_constitution_ai_generate() {
    local prompt_file="$1"
    local prd_content="$2"
    local brownfield_context="$3"

    # Create combined prompt
    local temp_prompt
    temp_prompt="$(tempfile_create)"

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# Input: Structured PRD"
        echo ""
        echo "$prd_content"
        echo ""

        if [[ -n "$brownfield_context" ]]; then
            echo "---"
            echo ""
            echo "# Input: Detected Brownfield Patterns"
            echo ""
            echo "$brownfield_context"
            echo ""
        fi

        echo "---"
        echo ""
        echo "# Task"
        echo ""
        echo "Generate a project constitution based on the PRD above."
        if [[ -n "$brownfield_context" ]]; then
            echo "Incorporate the detected brownfield patterns to preserve existing conventions."
        fi
        echo ""
        echo "Today's date: $(date +%Y-%m-%d)"
    } > "$temp_prompt"

    # Invoke provider for constitution phase
    local response
    if ! response=$(provider_invoke_for_phase "constitution" "$temp_prompt"); then
        tempfile_remove "$temp_prompt"
        die "Provider invocation failed. Check your configuration."
    fi

    tempfile_remove "$temp_prompt"

    echo "$response"
}

# _constitution_interactive_qa - Refine constitution through Q&A
_constitution_interactive_qa() {
    local draft_constitution="$1"
    local prd_content="$2"
    local prompt_file="$3"

    # Source interaction library
    # shellcheck source=src/lib/interaction.sh
    source "${LIB_DIR}/interaction.sh"

    # Present draft to user and ask refinement questions (redirect to stderr)
    {
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════"
        echo "DRAFT CONSTITUTION"
        echo "═══════════════════════════════════════════════════════════════════════"
        echo ""
        echo "$draft_constitution" | head -100
        if [[ $(echo "$draft_constitution" | wc -l) -gt 100 ]]; then
            echo ""
            echo "... (truncated for display, full version will be saved)"
        fi
        echo ""
        echo "═══════════════════════════════════════════════════════════════════════"
        echo ""
    } >&2

    # Ask refinement questions using present_alternatives
    local refinements=""

    # Question 1: Principle count
    local principle_choice
    principle_choice=$(present_alternatives \
        "Number of Core Principles" \
        "5 Principles" "Focused governance with essential rules only" \
        "Easier to remember and enforce, less comprehensive" \
        "Good for small teams" \
        "7 Principles" "Comprehensive coverage of major concerns" \
        "Balanced coverage, standard recommendation" \
        "Requires more enforcement effort" \
        "Custom" "Specify exact number based on project needs" \
        "Full control, may need additional prompting" \
        "Requires follow-up input" \
        "B")

    case "$principle_choice" in
        A) refinements+="Keep exactly 5 core principles, removing least critical ones.\n" ;;
        B) refinements+="Ensure exactly 7 core principles are included.\n" ;;
        C)
            local custom_count
            read -r -p "Enter number of principles (3-10): " custom_count
            refinements+="Adjust to exactly $custom_count core principles.\n"
            ;;
    esac

    # Question 2: Testing emphasis
    local testing_choice
    testing_choice=$(present_alternatives \
        "Testing Requirements" \
        "Strict TDD" "Require tests before code, high coverage mandates" \
        "Best quality, slower initial development" \
        "Recommended for critical systems" \
        "Balanced" "Reasonable coverage requirements, tests with PRs" \
        "Good balance of quality and velocity" \
        "Standard for most projects" \
        "Minimal" "Basic smoke tests, coverage not enforced" \
        "Fastest development, higher risk" \
        "Only for prototypes or experiments" \
        "B")

    case "$testing_choice" in
        A) refinements+="Emphasize strict TDD with 90%+ coverage requirements.\n" ;;
        B) refinements+="Keep balanced testing with 80% coverage target.\n" ;;
        C) refinements+="Reduce testing requirements to essential smoke tests only.\n" ;;
    esac

    # Question 3: Security emphasis
    local security_choice
    security_choice=$(present_alternatives \
        "Security Level" \
        "High Security" "Strict input validation, encryption, audit logging" \
        "Best for handling sensitive data or compliance" \
        "More development overhead" \
        "Standard" "Basic security hygiene, no secrets in code" \
        "Appropriate for most applications" \
        "Balance of security and simplicity" \
        "Minimal" "Basic authentication only" \
        "Only for internal tools or prototypes" \
        "Higher risk exposure" \
        "B")

    case "$security_choice" in
        A) refinements+="Strengthen security principles: mandatory encryption, strict input validation, audit logging.\n" ;;
        B) refinements+="Keep standard security: no secrets in code, basic input validation.\n" ;;
        C) refinements+="Reduce security requirements to basic authentication only.\n" ;;
    esac

    # If user provided refinements, regenerate
    if [[ -n "$refinements" ]]; then
        log_info "Applying refinements..."

        local temp_prompt
        temp_prompt="$(tempfile_create)"

        {
            cat "$prompt_file"
            echo ""
            echo "---"
            echo ""
            echo "# Current Draft"
            echo ""
            echo "$draft_constitution"
            echo ""
            echo "---"
            echo ""
            echo "# User Refinements"
            echo ""
            echo -e "$refinements"
            echo ""
            echo "---"
            echo ""
            echo "# Task"
            echo ""
            echo "Refine the constitution based on the user's preferences above."
            echo "Maintain the same structure but adjust content accordingly."
            echo ""
            echo "CRITICAL: Output ONLY the refined markdown document."
        } > "$temp_prompt"

        local refined_response
        if refined_response=$(provider_invoke_for_phase "constitution" "$temp_prompt"); then
            tempfile_remove "$temp_prompt"
            echo "$refined_response"
            return 0
        fi

        tempfile_remove "$temp_prompt"
        log_warn "Refinement failed, using original draft"
    fi

    echo "$draft_constitution"
}

# _constitution_user_review - Final review before saving
_constitution_user_review() {
    local constitution="$1"
    local output_file="$2"

    echo ""
    echo "═══════════════════════════════════════════════════════════════════════"
    echo "FINAL CONSTITUTION REVIEW"
    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""

    # Show principle summary
    local principle_count
    principle_count=$(echo "$constitution" | grep -c "^### [0-9]" || echo "0")
    echo "Principles detected: $principle_count"
    echo ""

    # Extract and show principle names
    echo "Principles:"
    echo "$constitution" | grep "^### [0-9]" | sed 's/^### [0-9]*\. /  - /'
    echo ""

    echo "═══════════════════════════════════════════════════════════════════════"
    echo ""

    # Ask for confirmation
    local confirm_choice
    confirm_choice=$(present_alternatives \
        "Save Constitution?" \
        "Save" "Save the constitution and proceed" \
        "Constitution will be saved to .workflow/constitution.md" \
        "Ready to continue to specs phase" \
        "Edit" "Open in editor before saving" \
        "Make manual adjustments to the constitution" \
        "Requires EDITOR environment variable" \
        "Cancel" "Discard and exit without saving" \
        "No changes will be made" \
        "Run command again to restart" \
        "A")

    case "$confirm_choice" in
        A)
            # Save directly
            echo "$constitution" > "$output_file"
            log_info "Constitution saved to: $output_file"
            ;;
        B)
            # Save to temp file and open in editor
            echo "$constitution" > "$output_file"
            if [[ -n "${EDITOR:-}" ]]; then
                "$EDITOR" "$output_file"
                log_info "Constitution saved after editing: $output_file"
            else
                log_warn "EDITOR not set, opening with nano"
                nano "$output_file" || vi "$output_file" || {
                    log_info "Constitution saved to: $output_file"
                    log_info "Edit manually: $output_file"
                }
            fi
            ;;
        C)
            die "Constitution generation cancelled by user"
            ;;
    esac
}

# _constitution_from_file - Use existing file as base
_constitution_from_file() {
    local source_file="$1"
    local output_file="$2"
    local project_root="$3"
    local skip_qa="$4"

    # Read source file
    local source_content
    source_content="$(cat "$source_file")"

    # If not skipping Q&A, allow refinement
    if [[ "$skip_qa" != "true" ]]; then
        local prd_file="$project_root/docs/PRD_STRUCTURED.md"
        local prd_content=""
        if [[ -f "$prd_file" ]]; then
            prd_content="$(cat "$prd_file")"
        fi

        local prompt_file
        prompt_file="$(resolve_prompt_template "PROMPT_constitution.md" "$project_root")"

        source_content=$(_constitution_interactive_qa "$source_content" "$prd_content" "$prompt_file")
    fi

    # User review
    _constitution_user_review "$source_content" "$output_file"
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_constitution "$@"
fi
