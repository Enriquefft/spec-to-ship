#!/usr/bin/env bash
# workflow specs - Generate individual spec files from structured PRD
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

# cmd_specs - Generate specification files from structured PRD
cmd_specs() {
    local force=false
    local context_mode="minimal"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force)
                force=true
                shift
                ;;
            --context-mode)
                context_mode="$2"
                shift 2
                ;;
            --help)
                _specs_help
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

    # Present alternatives for spec generation approach
    if [[ "$context_mode" == "minimal" ]]; then
        local choice
        choice=$(present_alternatives \
            "Specification Generation Approach" \
            "Minimal Context" "Activity section only, fast and efficient" \
            "Low token use, fast generation, best for experienced teams" \
            "May require more Claude reasoning" \
            "Full Context" "Activity + full PRD included for maximum clarity" \
            "Maximum clarity, better for complex specs, more complete output" \
            "Uses 3x more tokens per spec" \
            "With Architecture" "Activity + PRD + architecture overview for integration clarity" \
            "Better integration planning, moderate token use, good for arch-heavy projects" \
            "Slower generation, moderate token cost" \
            "A")

        case "$choice" in
            A) context_mode="minimal" ;;
            B) context_mode="full" ;;
            C) context_mode="with_arch" ;;
            *) log_error "Invalid choice"; return 1 ;;
        esac
    fi

    log_info "Using context mode: $context_mode"

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Check for structured PRD
    local prd_structured="$project_root/docs/PRD_STRUCTURED.md"
    if [[ ! -f "$prd_structured" ]]; then
        die "Structured PRD not found: $prd_structured

Run 'workflow clarify' first to generate the structured PRD."
    fi

    log_info "Loading structured PRD: $prd_structured"

    # Read structured PRD content
    local prd_content
    prd_content="$(cat "$prd_structured")"

    # Parse activities from structured PRD
    local -a activities=()
    _parse_activities "$prd_content" activities

    if [[ ${#activities[@]} -eq 0 ]]; then
        die "No activities found in structured PRD"
    fi

    log_info "Found ${#activities[@]} activities to process"

    # Create specs directory if it doesn't exist
    mkdir -p "$project_root/specs"

    # Build activity-to-filename mapping for cross-references
    local -A activity_filenames
    for activity_name in "${activities[@]}"; do
        local spec_file
        spec_file="$(_activity_to_filename "$activity_name")"
        activity_filenames["$activity_name"]="$spec_file"
    done

    # Create list of all spec filenames for context
    local all_spec_files=""
    for activity_name in "${activities[@]}"; do
        all_spec_files+="- ${activity_filenames[$activity_name]} (for \"$activity_name\")"$'\n'
    done

    # Process each activity
    local activity_count=0
    local skipped_count=0
    local generated_count=0

    for activity_name in "${activities[@]}"; do
        activity_count=$((activity_count + 1))

        # Get filename for this activity
        local spec_file="${activity_filenames[$activity_name]}"
        local spec_path="$project_root/specs/$spec_file"

        log_info "[$activity_count/${#activities[@]}] Processing: $activity_name"

        # Check if spec already exists
        if [[ -f "$spec_path" ]] && [[ "$force" != "true" ]]; then
            log_info "  Skipping (already exists): $spec_file"
            log_info "  Use --force to regenerate"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        # Extract activity section from structured PRD
        local activity_section
        activity_section="$(_extract_activity_section "$prd_content" "$activity_name")"

        # Generate spec file
        log_info "  Generating spec: $spec_file"
        if _generate_spec "$activity_name" "$activity_section" "$spec_path" "$all_spec_files" "$project_root" "$context_mode" "$prd_content"; then
            log_info "  ${COLOR_GREEN}✓${COLOR_RESET} Generated: $spec_file"
            generated_count=$((generated_count + 1))
        else
            log_error "  ${COLOR_RED}✗${COLOR_RESET} Failed to generate: $spec_file"
        fi
    done

    # Summary
    echo ""
    log_info "Summary:"
    log_info "  Total activities: $activity_count"
    log_info "  Generated: $generated_count"
    log_info "  Skipped: $skipped_count"

    if [[ $generated_count -gt 0 ]]; then
        echo ""
        log_info "Spec files created in: $project_root/specs/"
        log_info "Next step: Run 'workflow arch' to generate architecture document"
    fi
}

# _specs_help - Show help for specs command
_specs_help() {
    cat <<'EOF'
USAGE:
    workflow specs [OPTIONS]

DESCRIPTION:
    Generate individual specification files from structured PRD.

    Creates one spec file per activity in docs/PRD_STRUCTURED.md, with
    detailed requirements, user stories, and acceptance criteria.

OPTIONS:
    --force         Regenerate all spec files, overwriting existing ones
    --help          Show this help message

WORKFLOW:
    1. Run 'workflow clarify' to generate docs/PRD_STRUCTURED.md
    2. Run 'workflow specs' to generate specs/*.md files
    3. Run 'workflow arch' to create architecture document

EXAMPLES:
    # Generate spec files from structured PRD
    workflow specs

    # Regenerate all spec files
    workflow specs --force

OUTPUTS:
    specs/{activity-name}.md     One spec file per activity (kebab-case)

CONFIGURATION:
    MODEL_SPECS                  Claude model for spec generation (default: sonnet)

EXIT CODES:
    0    Success
    1    Error (missing PRD, Claude API failure, invalid options)
EOF
}

# _parse_activities - Extract activity names from structured PRD
# Arguments: prd_content, activities_array_name
_parse_activities() {
    local content="$1"
    local -n activities_ref="$2"

    # Parse activity headers: "### Activity N: Activity Name"
    local activity_pattern='^### Activity [0-9]+: (.+)$'

    while IFS= read -r line; do
        if [[ "$line" =~ $activity_pattern ]]; then
            local activity_name="${BASH_REMATCH[1]}"
            activities_ref+=("$activity_name")
        fi
    done <<< "$content"
}

# _activity_to_filename - Convert activity name to kebab-case filename
# Arguments: activity_name
_activity_to_filename() {
    local activity_name="$1"

    # Convert to lowercase and replace spaces/special chars with hyphens
    local filename
    filename="$(echo "$activity_name" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-//; s/-$//')"

    echo "${filename}.md"
}

# _extract_activity_section - Extract full activity section from PRD
# Arguments: prd_content, activity_name
_extract_activity_section() {
    local content="$1"
    local activity_name="$2"

    # Find the activity section and extract until next activity or end of Activities section
    local in_activity=false
    local activity_section=""
    local activity_header_pattern="^### Activity [0-9]+: $activity_name\$"
    local next_activity_pattern="^### Activity [0-9]+:"
    local section_end_pattern="^## "

    while IFS= read -r line; do
        if [[ "$line" =~ $activity_header_pattern ]]; then
            in_activity=true
            activity_section="$line"$'\n'
            continue
        fi

        if [[ "$in_activity" == "true" ]]; then
            # Stop at next activity or next major section
            if [[ "$line" =~ $next_activity_pattern ]] || [[ "$line" =~ $section_end_pattern ]]; then
                break
            fi
            activity_section+="$line"$'\n'
        fi
    done <<< "$content"

    echo "$activity_section"
}

# _generate_spec - Generate specification file for an activity
# Arguments: activity_name, activity_section, output_file, all_spec_files, project_root, context_mode, prd_file
# Optimized: Uses tempfile_create for automatic cleanup and context compression
_generate_spec() {
    local activity_name="$1"
    local activity_section="$2"
    local output_file="$3"
    local all_spec_files="$4"
    local project_root="$5"
    local context_mode="$6"
    local prd_file="$7"

    # Get prompt template
    local prompt_file
    if ! prompt_file="$(resolve_prompt_template "PROMPT_specs.md" "$project_root")"; then
        return 1
    fi

    # Create combined prompt using centralized temp file management
    local temp_prompt
    temp_prompt="$(tempfile_create)"

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""

        # Add context based on selected mode (optimized with compression)
        case "$context_mode" in
            full)
                echo "# CONTEXT: Full Structured PRD"
                echo ""
                cat "$prd_file"
                echo ""
                echo "---"
                echo ""
                ;;
            with_arch)
                # Use summarized PRD instead of full for token savings
                echo "# CONTEXT: Structured PRD (Key Sections)"
                echo ""
                context_summarize_prd "$prd_file"
                echo ""
                echo "---"
                echo ""
                if [[ -f "$project_root/docs/ARCHITECTURE.md" ]]; then
                    echo "# CONTEXT: Architecture Overview"
                    echo ""
                    context_summarize_arch "$project_root/docs/ARCHITECTURE.md"
                    echo ""
                    echo "---"
                    echo ""
                fi
                ;;
            minimal|*)
                # Minimal context - just spec references (most token-efficient)
                echo "# CONTEXT: Other Specs in This Project"
                echo ""
                echo "For cross-referencing dependencies, other specs include:"
                echo ""
                echo "$all_spec_files"
                echo ""
                echo "---"
                echo ""
                ;;
        esac

        echo "# TASK: Generate Specification for This Activity"
        echo ""
        echo "$activity_section"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Generate a complete specification for the activity: \"$activity_name\""
        echo "2. Use the template structure from the prompt above"
        echo "3. Expand the acceptance criteria into detailed user stories and requirements"
        echo "4. Include functional requirements, edge cases, and success criteria"
        echo "5. If this activity depends on other activities, reference them using filenames from the list above"
        echo "6. Output ONLY the markdown specification content (no explanations)"
        echo "7. Use the filename: $(basename "$output_file" .md)"
    } > "$temp_prompt"

    # Invoke provider for specs phase
    local response
    if ! response=$(provider_invoke_for_phase "specs" "$temp_prompt"); then
        tempfile_remove "$temp_prompt"
        return 1
    fi

    tempfile_remove "$temp_prompt"

    # Write spec file
    echo "$response" > "$output_file"

    return 0
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_specs "$@"
fi
