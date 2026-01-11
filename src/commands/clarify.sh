#!/usr/bin/env bash
# workflow clarify - Transform rough PRD into structured format

# Source libraries
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=src/lib/claude.sh
source "${LIB_DIR}/claude.sh"
# shellcheck source=src/lib/hitl.sh
source "${LIB_DIR}/hitl.sh"
# shellcheck source=src/lib/git.sh
source "${LIB_DIR}/git.sh"

# Show help for clarify command
show_clarify_help() {
    cat <<EOF
workflow clarify - Transform rough PRD into structured format

USAGE:
    workflow clarify [options]

OPTIONS:
    --no-interactive    Best-effort without questions (makes reasonable assumptions)
    -h, --help         Show this help message

DESCRIPTION:
    Transforms a rough PRD into a structured document with:
    - Audiences (who will use the system)
    - Jobs To Be Done (user goals and motivations)
    - Activities (key workflows and features)
    - Acceptance Criteria (measurable success criteria)

    In interactive mode, Claude may ask up to 10 clarification questions
    to resolve ambiguities and fill gaps. In non-interactive mode, Claude
    will make reasonable assumptions and note them in the output.

INPUT:
    docs/PRD.md - Rough product requirements document

OUTPUT:
    docs/PRD_STRUCTURED.md - Structured requirements document

EXAMPLES:
    # Interactive mode (default)
    workflow clarify

    # Non-interactive mode (no questions)
    workflow clarify --no-interactive

EXIT CODES:
    0   Success
    1   Error (PRD not found, Claude API failure)

EOF
}

# Main clarify command
cmd_clarify() {
    local interactive=true

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --no-interactive)
                interactive=false
                shift
                ;;
            -h|--help)
                show_clarify_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_clarify_help
                exit 1
                ;;
        esac
    done

    log_info "Starting clarify phase..."

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

    # Check for PRD file
    local prd_file="${project_root}/docs/PRD.md"
    if [[ ! -f "$prd_file" ]]; then
        die "PRD not found: $prd_file. Run 'workflow init' first."
    fi

    log_info "Found PRD: $prd_file"

    # Load PRD content
    local prd_content
    prd_content="$(cat "$prd_file")"

    # Get prompt template
    local prompt_file
    if [[ -f "${project_root}/src/prompts/PROMPT_clarify.md" ]]; then
        prompt_file="${project_root}/src/prompts/PROMPT_clarify.md"
    elif [[ -f "$(dirname "$WORKFLOW_BIN")/../prompts/PROMPT_clarify.md" ]]; then
        prompt_file="$(dirname "$WORKFLOW_BIN")/../prompts/PROMPT_clarify.md"
    else
        # Use prompts from this installation
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        prompt_file="${script_dir}/prompts/PROMPT_clarify.md"
    fi

    if [[ ! -f "$prompt_file" ]]; then
        die "Prompt template not found: $prompt_file"
    fi

    log_debug "Using prompt template: $prompt_file"

    # Get model for clarify phase
    local model
    model="$(config_model_for_phase clarify)"
    log_info "Using model: $model"

    # Prepare structured PRD output file
    local structured_prd="${project_root}/docs/PRD_STRUCTURED.md"

    # Interactive or non-interactive mode
    if [[ "$interactive" == "true" ]]; then
        log_info "Running in interactive mode (up to 10 clarification rounds)"
        _clarify_interactive "$prompt_file" "$prd_content" "$model" "$structured_prd"
    else
        log_info "Running in non-interactive mode (best-effort with assumptions)"
        _clarify_noninteractive "$prompt_file" "$prd_content" "$model" "$structured_prd"
    fi

    # Verify original PRD unchanged
    if [[ ! -f "$prd_file" ]]; then
        die "Original PRD file was unexpectedly removed"
    fi

    log_info "✓ Clarification complete"
    echo ""
    echo "Output: $structured_prd" >&2
    echo ""
    echo "Next steps:" >&2
    echo "  1. Review the structured PRD" >&2
    echo "  2. Run 'workflow specs' to generate individual specifications" >&2
    echo ""
}

# _clarify_noninteractive - Run clarify without user interaction
_clarify_noninteractive() {
    local prompt_file="$1"
    local prd_content="$2"
    local model="$3"
    local output_file="$4"

    # Create combined prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# Input PRD"
        echo ""
        echo "$prd_content"
        echo ""
        echo "---"
        echo ""
        echo "**Mode**: Non-interactive"
        echo ""
        echo "Instructions: Generate the structured PRD without asking questions."
        echo "Make reasonable assumptions where information is missing and document them"
        echo "in the 'Assumptions' section. Focus on extracting maximum value from the"
        echo "provided PRD even if some details are unclear."
    } > "$temp_prompt"

    log_info "Invoking Claude for clarification..."

    # Invoke Claude
    local response
    if ! response=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Claude invocation failed. Check your API key and connection."
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write structured PRD
    echo "$response" > "$output_file"

    log_info "Generated structured PRD: $output_file"
}

# _clarify_interactive - Run clarify with interactive Q&A
_clarify_interactive() {
    local prompt_file="$1"
    local prd_content="$2"
    local model="$3"
    local output_file="$4"

    local max_rounds=10
    local current_round=0
    local clarifications=""

    log_info "Starting interactive clarification session..."

    # Initial invocation
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# Input PRD"
        echo ""
        echo "$prd_content"
        echo ""
        echo "---"
        echo ""
        echo "**Mode**: Interactive"
        echo ""
        echo "Instructions: Analyze the PRD and identify gaps or ambiguities."
        echo "Ask ONE clarifying question to resolve the most important ambiguity."
        echo "Format your response as:"
        echo ""
        echo "QUESTION: [Your question here]"
        echo ""
        echo "If no questions are needed, respond with:"
        echo ""
        echo "NO_QUESTIONS_NEEDED"
        echo ""
        echo "Then provide the complete structured PRD."
    } > "$temp_prompt"

    while [[ $current_round -lt $max_rounds ]]; do
        ((current_round++))
        log_info "Clarification round $current_round/$max_rounds"

        # Invoke Claude
        local response
        if ! response=$(claude_invoke "$model" "$temp_prompt"); then
            rm -f "$temp_prompt"
            trap - EXIT
            die "Claude invocation failed"
        fi

        # Check if Claude has questions
        if echo "$response" | grep -q "^QUESTION:"; then
            # Extract question
            local question
            question=$(echo "$response" | grep "^QUESTION:" | head -1 | sed 's/^QUESTION:[[:space:]]*//')

            if [[ -z "$question" ]]; then
                log_warn "Claude provided empty question, ending clarification"
                break
            fi

            # Ask user via HITL
            log_info "Claude asks: $question"
            local answer
            if answer=$(hitl_prompt "$question" "clarification" ""); then
                log_debug "User answered: $answer"

                # Store clarification
                clarifications+="Q: $question\nA: $answer\n\n"

                # Update prompt with answer
                {
                    cat "$prompt_file"
                    echo ""
                    echo "---"
                    echo ""
                    echo "# Input PRD"
                    echo ""
                    echo "$prd_content"
                    echo ""
                    echo "---"
                    echo ""
                    echo "# Clarifications So Far"
                    echo ""
                    echo -e "$clarifications"
                    echo ""
                    echo "---"
                    echo ""
                    echo "**Mode**: Interactive (Round $((current_round + 1))/$max_rounds)"
                    echo ""
                    echo "Instructions: Given the clarifications above, ask ONE more question"
                    echo "if needed, or provide the complete structured PRD if you have enough"
                    echo "information."
                    echo ""
                    echo "Format: QUESTION: [question] OR NO_QUESTIONS_NEEDED"
                } > "$temp_prompt"
            else
                log_warn "HITL timeout or user skipped, ending clarification"
                break
            fi
        else
            # No more questions, Claude provided structured PRD
            log_info "No more clarification questions"
            break
        fi
    done

    # Final invocation to get structured PRD
    log_info "Generating final structured PRD..."

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# Input PRD"
        echo ""
        echo "$prd_content"
        echo ""
        echo "---"
        echo ""
        if [[ -n "$clarifications" ]]; then
            echo "# Clarifications"
            echo ""
            echo -e "$clarifications"
            echo ""
            echo "---"
            echo ""
        fi
        echo "**Mode**: Final Generation"
        echo ""
        echo "Instructions: Generate the complete structured PRD now."
        echo "Do NOT ask more questions. Provide the full structured document with:"
        echo "- Audiences"
        echo "- Jobs To Be Done"
        echo "- Activities (with acceptance criteria)"
        echo "- Assumptions (if any)"
        echo "- Out of Scope"
    } > "$temp_prompt"

    local final_response
    if ! final_response=$(claude_invoke "$model" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Failed to generate final structured PRD"
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write structured PRD
    echo "$final_response" > "$output_file"

    log_info "Generated structured PRD: $output_file"

    # Show summary
    if [[ $current_round -gt 0 ]]; then
        log_info "Completed $current_round clarification round(s)"
    fi
}
