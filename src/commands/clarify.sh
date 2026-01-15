#!/usr/bin/env bash
# workflow clarify - Transform rough PRD into structured format

# Source libraries
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/config.sh
source "${LIB_DIR}/config.sh"
# shellcheck source=src/lib/provider.sh
source "${LIB_DIR}/provider.sh"
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

    # Emit phase start
    if tui_is_enabled 2>/dev/null; then
        tui_phase_start "clarify"
    else
        log_info "Starting clarify phase..."
    fi
    
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
    if ! prompt_file="$(resolve_prompt_template "PROMPT_clarify.md" "$project_root")"; then
        die "Prompt template not found"
    fi

    # Prepare structured PRD output file
    local structured_prd="${project_root}/docs/PRD_STRUCTURED.md"

    # Interactive or non-interactive mode
    if [[ "$interactive" == "true" ]]; then
        log_info "Running in interactive mode with smart clarification"
        _clarify_interactive_smart "$prompt_file" "$prd_content" "$structured_prd"
    else
        log_info "Running in non-interactive mode (best-effort with assumptions)"
        _clarify_noninteractive "$prompt_file" "$prd_content" "$structured_prd"
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
    local output_file="$3"

    # Create combined prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "${temp_prompt:-}"' EXIT

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
        echo "CRITICAL REQUIREMENTS:"
        echo "1. Output ONLY the markdown document - NO explanations, NO commentary, NO meta-descriptions"
        echo "2. Start directly with '# Structured Product Requirements Document'"
        echo "3. Do NOT write things like 'I've successfully transformed' or 'Here is the document'"
        echo "4. Do NOT explain what you did - just provide the raw markdown"
        echo ""
        echo "Instructions: Generate the structured PRD without asking questions."
        echo "Make reasonable assumptions where information is missing and document them"
        echo "in the 'Assumptions' section. Focus on extracting maximum value from the"
        echo "provided PRD even if some details are unclear."
    } > "$temp_prompt"

    log_info "Invoking Claude for clarification..."

    # Invoke provider for clarify phase
    local response
    if ! response=$(provider_invoke_for_phase "clarify" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Provider invocation failed. Check your configuration."
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write structured PRD
    echo "$response" > "$output_file"

    log_info "Generated structured PRD: $output_file"
}

# _clarify_interactive_smart - Run clarify with smart question generation (single API call + user interaction)
_clarify_interactive_smart() {
    local prompt_file="$1"
    local prd_content="$2"
    local output_file="$3"

    # Source interaction library for smart questions
    # shellcheck source=src/lib/interaction.sh
    source "${LIB_DIR}/interaction.sh"

    log_info "Analyzing PRD to identify clarification questions..."

    # Create prompt for question generation
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "${temp_prompt:-}"' EXIT

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
        echo "**Mode**: Question Generation"
        echo ""
        echo "Instructions: Analyze this PRD for ambiguities and gaps. Identify up to 5 key"
        echo "clarification questions needed to produce a high-quality structured document."
        echo ""
        echo "For each question, provide options with a recommended choice. Return in this JSON format:"
        echo '```json'
        echo "{"
        echo '  "questions": ['
        echo "    {"
        echo '      "id": 1,'
        echo '      "text": "What is the primary user persona?",'
        echo '      "options": ['
        echo '        {"id": "A", "desc": "Technical developers"},'
        echo '        {"id": "B", "desc": "Business analysts"},'
        echo '        {"id": "C", "desc": "End users/consumers"}'
        echo "      ],"
        echo '      "recommended": "A",'
        echo '      "reasoning": "Technical focus evident from requirements"'
        echo "    }"
        echo "  ],"
        echo '  "count": 1'
        echo "}"
        echo '```'
        echo ""
        echo "For each question:"
        echo "- Analyze all options and determine the most suitable based on best practices"
        echo "- Provide 2-4 clear options (A, B, C, D)"
        echo "- Recommend ONE option with 1-2 sentence reasoning"
        echo "- Keep option descriptions concise (under 60 chars)"
        echo ""
        echo "Then after the JSON, provide the complete structured PRD based on what you know."
    } > "$temp_prompt"

    # First API call: Generate questions and structured output
    log_info "Invoking Claude to generate questions..."
    local response
    if ! response=$(provider_invoke_for_phase "clarify" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Provider invocation failed"
    fi

    # Parse JSON questions from response
    # Extract JSON block (handles both raw and markdown-wrapped JSON)
    local questions_json=""

    log_debug "Response length: ${#response} characters"

    # Try to extract from markdown code fences first - specifically look for JSON with "questions"
    if echo "$response" | grep -q '```json'; then
        # Extract the JSON block that contains "questions"
        local temp_json
        temp_json=$(echo "$response" | sed -n '/```json/,/```/p' | sed '1d;$d')
        if echo "$temp_json" | grep -q '"questions"'; then
            questions_json="$temp_json"
            log_debug "Found questions JSON in code fence"
        fi
    fi

    # If not found in json fence, try any code fence containing questions
    if [[ -z "$questions_json" ]] && echo "$response" | grep -q '```'; then
        local temp_json
        temp_json=$(echo "$response" | sed -n '/```/,/```/p' | sed '1d;$d')
        if echo "$temp_json" | grep -q '"questions"'; then
            questions_json="$temp_json"
            log_debug "Found questions JSON in generic code fence"
        fi
    fi

    # Fall back to finding raw JSON block
    if [[ -z "$questions_json" ]]; then
        if command -v jq &>/dev/null; then
            questions_json=$(echo "$response" | jq -s '.[] | select(has("questions"))' 2>/dev/null)
        fi

        # If jq didn't work, try basic sed extraction
        if [[ -z "$questions_json" ]]; then
            questions_json=$(echo "$response" | sed -n '/{/,/}/p' | grep -m1 '"questions"' -A100)
        fi
    fi

    # Validate extracted JSON
    if [[ -n "$questions_json" ]] && command -v jq &>/dev/null; then
        if ! echo "$questions_json" | jq empty 2>/dev/null; then
            log_debug "Extracted JSON is invalid, clearing"
            questions_json=""
        fi
    fi

    if [[ -z "$questions_json" ]]; then
        log_warn "No questions JSON found in Claude response, using best-effort output"
        log_debug "Response preview: ${response:0:500}..."
        echo "$response" > "$output_file"
        rm -f "$temp_prompt"
        trap - EXIT
        log_info "Generated structured PRD: $output_file"
        return 0
    fi

    log_debug "Extracted questions JSON: ${questions_json:0:200}..."

    # Extract question count using jq if available, otherwise grep
    local question_count=0
    if command -v jq &>/dev/null; then
        # Use jq's // operator to default to 0 when count is null/missing
        question_count=$(echo "$questions_json" | jq -r '.count // 0' 2>/dev/null)
    else
        question_count=$(echo "$questions_json" | grep -o '"count"[[:space:]]*:[[:space:]]*[0-9]*' | tail -1 | grep -o '[0-9]*$' || echo "0")
    fi

    # Ensure question_count is a valid number (handle null, empty, or non-numeric)
    if ! [[ "$question_count" =~ ^[0-9]+$ ]]; then
        log_debug "Invalid question count '$question_count', defaulting to 0"
        question_count=0
    fi

    log_info "Found $question_count clarification question(s)"

    # If no questions, use response as-is
    if [[ "$question_count" -eq 0 ]]; then
        log_info "No clarifications needed, using Claude's output"
        echo "$response" > "$output_file"
        rm -f "$temp_prompt"
        trap - EXIT
        log_info "Generated structured PRD: $output_file"
        return 0
    fi

    # Ask user the questions using smart question UI
    log_info "Gathering clarifications from user..."
    local clarifications=""

    for i in $(seq 1 "$question_count"); do
        local question_text=""
        local options_list=""
        local recommended=""
        local reasoning=""

        if command -v jq &>/dev/null; then
            # Extract question details using jq
            question_text=$(echo "$questions_json" | jq -r ".questions[] | select(.id == $i) | .text" 2>/dev/null)
            recommended=$(echo "$questions_json" | jq -r ".questions[] | select(.id == $i) | .recommended" 2>/dev/null)
            reasoning=$(echo "$questions_json" | jq -r ".questions[] | select(.id == $i) | .reasoning" 2>/dev/null)

            # Build options list in "ID|Description" format
            options_list=$(echo "$questions_json" | jq -r ".questions[] | select(.id == $i) | .options[] | \"\(.id)|\(.desc)\"" 2>/dev/null)
        else
            # Fallback: basic text extraction
            question_text=$(echo "$questions_json" | grep -o "\"id\"[[:space:]]*:[[:space:]]*${i}[^}]*\"text\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed 's/.*"text"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        fi

        if [[ -z "$question_text" ]]; then
            continue
        fi

        log_info "Question $i/$question_count"

        # Use smart question UI if we have options, otherwise fall back to basic prompt
        local answer
        if [[ -n "$options_list" ]]; then
            answer=$(interaction_present_smart_question "$question_text" "$recommended" "$reasoning" "$options_list" "true")
        else
            # Fallback to basic hitl_prompt for simple questions
            if answer=$(hitl_prompt "$question_text" "clarification" ""); then
                :
            else
                log_warn "User skipped question $i"
                continue
            fi
        fi

        if [[ -n "$answer" ]]; then
            clarifications+="Q: $question_text\nA: $answer\n\n"
            log_debug "User answered: $answer"
        fi
    done

    # Second API call: Generate final PRD with clarifications
    log_info "Generating final structured PRD with clarifications..."

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
            echo "# User Clarifications"
            echo ""
            echo -e "$clarifications"
            echo ""
            echo "---"
            echo ""
        fi
        echo "**Mode**: Final Generation with Clarifications"
        echo ""
        echo "Instructions: Using the clarifications above, generate the final structured PRD."
        echo ""
        echo "CRITICAL REQUIREMENTS:"
        echo "1. Output ONLY the markdown document - NO explanations, NO commentary, NO meta-descriptions"
        echo "2. Start directly with '# Structured Product Requirements Document'"
        echo "3. Do NOT write things like 'I've successfully transformed' or 'Here is the document'"
        echo "4. Do NOT explain what you did - just provide the raw markdown"
        echo ""
        echo "The document must include these sections:"
        echo "- Audiences"
        echo "- Jobs To Be Done"
        echo "- Activities (with acceptance criteria)"
        echo "- Assumptions (if any)"
        echo "- Out of Scope"
    } > "$temp_prompt"

    local final_response
    if ! final_response=$(provider_invoke_for_phase "clarify" "$temp_prompt"); then
        rm -f "$temp_prompt"
        trap - EXIT
        die "Failed to generate final structured PRD"
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    # Write structured PRD
    echo "$final_response" > "$output_file"

    log_info "Generated structured PRD: $output_file"
    log_info "✓ Clarification complete with $question_count clarification(s)"
}
