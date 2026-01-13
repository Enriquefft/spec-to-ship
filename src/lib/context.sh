#!/usr/bin/env bash
# src/lib/context.sh - Context compression utilities for token optimization
# Provides intelligent context summarization to reduce API token usage

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/cache.sh
source "${LIB_DIR}/cache.sh"

# ==============================================================================
# PRD Context Compression
# ==============================================================================

# context_summarize_prd(prd_file) - Extract key sections from structured PRD
# Returns: Summarized PRD content (audiences, JTBDs, activity list only)
context_summarize_prd() {
    local prd_file="$1"
    local cache_key="prd_summary_$(md5sum "$prd_file" 2>/dev/null | cut -d' ' -f1 || echo "$prd_file")"

    # Check cache first (3600s = 1 hour for stable PRD context)
    if cache_is_valid "$cache_key"; then
        if cached=$(cache_get "$cache_key" 3600); then
            echo "$cached"
            return 0
        fi
    fi

    # Extract key sections only
    local summary=""

    # Extract title
    summary+="$(sed -n '1,/^##/p' "$prd_file" | head -10)"
    summary+=$'\n\n'

    # Extract Audiences section (just headers)
    summary+="## Target Audiences"$'\n'
    summary+="$(sed -n '/^## Target Audiences/,/^## /p' "$prd_file" | grep -E '^###|^-' | head -20)"
    summary+=$'\n\n'

    # Extract JTBDs (just the job statements)
    summary+="## Jobs-to-be-Done"$'\n'
    summary+="$(sed -n '/^## Jobs-to-be-Done/,/^## /p' "$prd_file" | grep -E '^###|^>|^\*\*Job' | head -30)"
    summary+=$'\n\n'

    # Extract Activities list (titles only)
    summary+="## Activities (Summary)"$'\n'
    summary+="$(sed -n '/^## Activities/,/^## /p' "$prd_file" | grep -E '^### ' | head -20)"

    # Cache result
    cache_set "$cache_key" "$summary" "$prd_file"

    echo "$summary"
}

# context_extract_activity(prd_file, activity_name) - Extract specific activity section
# Optimized: caches parsed activities for reuse across multiple extractions
context_extract_activity() {
    local prd_file="$1"
    local activity_name="$2"
    local cache_key="activity_${activity_name//[^a-zA-Z0-9]/_}"

    # Check cache (3600s = 1 hour for stable activity context)
    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        echo "$cached"
        return 0
    fi

    # Extract activity section using awk (faster than multiple sed calls)
    local activity_content
    activity_content=$(awk -v name="$activity_name" '
        BEGIN { found=0; depth=0 }
        /^### / {
            if (found) exit
            if (index($0, name) > 0) { found=1; depth=3 }
        }
        /^## / { if (found) exit }
        found { print }
    ' "$prd_file")

    # Cache result
    if [[ -n "$activity_content" ]]; then
        cache_set "$cache_key" "$activity_content" "$prd_file"
    fi

    echo "$activity_content"
}

# ==============================================================================
# Spec Context Compression
# ==============================================================================

# context_summarize_specs(spec_dir) - Generate spec summaries for context
# Returns: Title + first paragraph for each spec
context_summarize_specs() {
    local spec_dir="$1"
    local cache_key="specs_summary"
    local summary=""

    # Check cache (3600s = 1 hour for stable spec summaries)
    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        echo "$cached"
        return 0
    fi

    # Find all spec files
    local spec_files
    mapfile -t spec_files < <(find "$spec_dir" -name "*.md" -type f 2>/dev/null | sort)

    for spec_file in "${spec_files[@]}"; do
        local basename
        basename=$(basename "$spec_file" .md)

        # Extract title (first heading)
        local title
        title=$(grep -m1 '^#' "$spec_file" | sed 's/^#* //')

        # Extract first paragraph (after title, skip empty lines)
        local first_para
        first_para=$(awk 'NR>1 && /^[^#]/ && !/^[[:space:]]*$/ {p=1} p && /^$/ {exit} p' "$spec_file" | head -5)

        summary+="### $basename: $title"$'\n'
        summary+="$first_para"$'\n\n'
    done

    # Cache result
    cache_set "$cache_key" "$summary"

    echo "$summary"
}

# context_get_spec_list(spec_dir) - Get list of spec files with titles
# Returns: Formatted list of "filename: title" entries
context_get_spec_list() {
    local spec_dir="$1"
    local cache_key="spec_list"

    # Check cache (3600s = 1 hour for stable spec list)
    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        echo "$cached"
        return 0
    fi

    local list=""
    local spec_files
    mapfile -t spec_files < <(find "$spec_dir" -name "*.md" -type f 2>/dev/null | sort)

    for spec_file in "${spec_files[@]}"; do
        local basename title
        basename=$(basename "$spec_file" .md)
        title=$(grep -m1 '^#' "$spec_file" | sed 's/^#* //')
        list+="- $basename: $title"$'\n'
    done

    cache_set "$cache_key" "$list"
    echo "$list"
}

# ==============================================================================
# Architecture Context Compression
# ==============================================================================

# context_get_arch_section(arch_file, section_name) - Extract specific arch section
# section_name: "overview", "components", "data_flow", "tech_stack", etc.
context_get_arch_section() {
    local arch_file="$1"
    local section_name="$2"
    local cache_key="arch_section_${section_name}"

    # Check cache (3600s = 1 hour for stable architecture sections)
    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        echo "$cached"
        return 0
    fi

    # Map section names to heading patterns
    local pattern
    case "$section_name" in
        overview)     pattern="Overview|Introduction|Summary" ;;
        components)   pattern="Components|Modules|Architecture" ;;
        data_flow)    pattern="Data Flow|Data Model|Schema" ;;
        tech_stack)   pattern="Technology|Tech Stack|Stack|Technologies" ;;
        api)          pattern="API|Endpoints|Interface" ;;
        security)     pattern="Security|Authentication|Authorization" ;;
        *)            pattern="$section_name" ;;
    esac

    # Extract section using awk
    local section
    section=$(awk -v pat="$pattern" '
        BEGIN { IGNORECASE=1; found=0 }
        /^## / {
            if (found) exit
            if (match($0, pat)) found=1
        }
        found { print }
    ' "$arch_file" | head -100)

    if [[ -n "$section" ]]; then
        cache_set "$cache_key" "$section" "$arch_file"
    fi

    echo "$section"
}

# context_summarize_arch(arch_file) - Get architecture overview (first 100 lines or key sections)
context_summarize_arch() {
    local arch_file="$1"
    local cache_key="arch_summary"

    # Check cache (3600s = 1 hour for stable architecture summary)
    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        echo "$cached"
        return 0
    fi

    # Get overview + components sections
    local summary=""
    summary+=$(context_get_arch_section "$arch_file" "overview")
    summary+=$'\n\n'
    summary+=$(context_get_arch_section "$arch_file" "components")

    # Fallback to first 100 lines if sections not found
    if [[ ${#summary} -lt 100 ]]; then
        summary=$(head -100 "$arch_file")
    fi

    cache_set "$cache_key" "$summary" "$arch_file"
    echo "$summary"
}

# ==============================================================================
# Plan Context Compression
# ==============================================================================

# context_compress_plan(plan_file, current_task_id) - Get relevant plan context for task
# Returns: Current milestone + adjacent tasks only (not full plan)
context_compress_plan() {
    local plan_file="$1"
    local current_task_id="${2:-}"
    local cache_key="plan_context_${current_task_id:-all}"

    # Check cache (1800s = 30 min for task context - may change during build)
    if [[ -n "$current_task_id" ]]; then
        if cached=$(cache_get "$cache_key" 1800 2>/dev/null); then
            echo "$cached"
            return 0
        fi
    fi

    local context=""

    # Add plan header/overview
    context+="# Implementation Plan Summary"$'\n\n'
    context+=$(sed -n '1,/^## /p' "$plan_file" | head -20)
    context+=$'\n\n'

    if [[ -n "$current_task_id" ]]; then
        # Find current milestone
        local milestone_section
        milestone_section=$(awk -v task="$current_task_id" '
            /^## / { milestone=$0; in_milestone=1 }
            in_milestone && index($0, task) { found=1 }
            found && /^## / && !first_found { first_found=1; next }
            found && first_found && /^## / { exit }
            found { print }
        ' "$plan_file")

        if [[ -n "$milestone_section" ]]; then
            context+="## Current Milestone"$'\n'
            context+="$milestone_section"$'\n\n'
        fi

        # Add task dependencies (tasks that current task depends on)
        context+="## Task Dependencies"$'\n'
        context+=$(grep -B2 -A2 "$current_task_id" "$plan_file" | head -20)
    else
        # No specific task - provide milestone overview
        context+="## Milestones Overview"$'\n'
        context+=$(grep -E '^##|^\- \[' "$plan_file" | head -50)
    fi

    if [[ -n "$current_task_id" ]]; then
        cache_set "$cache_key" "$context" "$plan_file"
    fi

    echo "$context"
}

# context_get_task_history(plan_file, limit) - Get recent task completions
# Returns: Last N completed tasks for context
context_get_task_history() {
    local plan_file="$1"
    local limit="${2:-3}"

    # Get completed tasks
    grep -E '^\- \[x\]|\- \[X\]' "$plan_file" | tail -"$limit"
}

# ==============================================================================
# Gap Analysis (Cached)
# ==============================================================================

# context_analyze_code_gap(project_root) - Analyze existing code structure
# Cached to avoid repeated file system scans
context_analyze_code_gap() {
    local project_root="$1"
    local src_dir="${project_root}/src"
    local cache_key="gap_analysis"

    # Check if src directory changed (use find to get latest mtime)
    local latest_mtime
    latest_mtime=$(find "$src_dir" -type f -name "*.sh" -printf '%T@\n' 2>/dev/null | sort -rn | head -1)

    if cached=$(cache_get "$cache_key" 3600 2>/dev/null); then
        # Verify cache is still valid
        local cached_mtime
        cached_mtime="${_CACHE_FILE_MTIMES[$cache_key]:-0}"
        if [[ "$cached_mtime" == *"$latest_mtime"* ]] || [[ -z "$latest_mtime" ]]; then
            echo "$cached"
            return 0
        fi
    fi

    local gap_analysis=""
    gap_analysis+="## Existing Code Structure"$'\n\n'

    # Directory structure (limited depth)
    if command -v tree &>/dev/null; then
        gap_analysis+="### Directory Tree"$'\n'
        gap_analysis+="\`\`\`"$'\n'
        gap_analysis+=$(tree -L 2 -I 'node_modules|.git|__pycache__|*.pyc' "$src_dir" 2>/dev/null || echo "No src directory")
        gap_analysis+="\`\`\`"$'\n\n'
    else
        gap_analysis+="### Files"$'\n'
        gap_analysis+=$(find "$src_dir" -type f -name "*.sh" 2>/dev/null | sort | head -30)
        gap_analysis+=$'\n\n'
    fi

    # Key files summary
    gap_analysis+="### Key Files"$'\n'
    for file in "$src_dir"/{lib,commands}/*.sh; do
        if [[ -f "$file" ]]; then
            local basename functions
            basename=$(basename "$file")
            functions=$(grep -E '^[a-z_]+\(\)' "$file" 2>/dev/null | head -5 | sed 's/().*/()/' | tr '\n' ', ')
            gap_analysis+="- $basename: $functions"$'\n'
        fi
    done 2>/dev/null

    # Cache with file dependency
    cache_set "$cache_key" "$gap_analysis" "$src_dir"

    echo "$gap_analysis"
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# context_estimate_tokens(text) - Rough token count estimate
# Approximation: ~4 characters per token for English
context_estimate_tokens() {
    local text="$1"
    local chars=${#text}
    echo $((chars / 4))
}

# context_truncate_to_tokens(text, max_tokens) - Truncate text to approximate token limit
context_truncate_to_tokens() {
    local text="$1"
    local max_tokens="$2"
    local max_chars=$((max_tokens * 4))

    if [[ ${#text} -le $max_chars ]]; then
        echo "$text"
    else
        echo "${text:0:$max_chars}..."$'\n[Truncated for token limit]'
    fi
}

# context_combine(files...) - Combine multiple context files with headers
context_combine() {
    local combined=""

    for file in "$@"; do
        if [[ -f "$file" ]]; then
            combined+="## File: $(basename "$file")"$'\n\n'
            combined+=$(cat "$file")
            combined+=$'\n\n---\n\n'
        fi
    done

    echo "$combined"
}
