#!/usr/bin/env bash
# workflow init - Initialize project with Spec-to-Ship structure

# Source libraries
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/git.sh
source "${LIB_DIR}/git.sh"

# Show help for init command
show_init_help() {
    cat <<EOF
workflow init - Initialize project with Spec-to-Ship structure

USAGE:
    workflow init [options]

OPTIONS:
    --from PATH     Copy PRD from specified file
    --force         Overwrite existing files
    -h, --help      Show this help message

DESCRIPTION:
    Initializes a new Spec-to-Ship project by creating the required directory
    structure and configuration files. Optionally copies a PRD file to start
    the workflow.

DIRECTORY STRUCTURE CREATED:
    .workflow/          # Workflow state and logs
        config.sh       # Configuration file
        logs/           # Session logs
    docs/               # Documentation
        PRD.md          # Product Requirements Document
        gates/          # Gate reports
    specs/              # Feature specifications
    src/                # Source code (if not exists)
        lib/            # Library code
        commands/       # Command implementations

EXAMPLES:
    # Initialize in current directory
    workflow init

    # Initialize with existing PRD
    workflow init --from ~/my-project-prd.md

    # Force initialization (overwrite existing)
    workflow init --force

EXIT CODES:
    0   Success
    1   Error (permission denied, invalid path)

EOF
}

# Create default configuration
create_default_config() {
    local config_file="$1"

    cat > "$config_file" <<'EOF'
# Spec-to-Ship Workflow Configuration
# Edit this file to customize workflow behavior

# Model selection for each phase
MODEL_CLARIFY="opus"
MODEL_SPECS="sonnet"
MODEL_ARCH="opus"
MODEL_PLAN="opus"
MODEL_BUILD_PRIMARY="opus"
MODEL_BUILD_SECONDARY="sonnet"
MODEL_GATE="sonnet"
MODEL_FEEDBACK="haiku"

# Human-in-the-Loop (HITL) settings
HITL_ENABLED="false"
HITL_MODE="milestone"  # Options: task, milestone, uncertain, every:N
HITL_TIMEOUT=""        # Auto-continue timeout (e.g., 5m, 1h) - empty for no timeout

# Build loop settings
BUILD_MAX_ITERATIONS="0"  # 0 = unlimited
BUILD_BACKPRESSURE_TESTS="true"
BUILD_BACKPRESSURE_TYPECHECK="false"
BUILD_BACKPRESSURE_LINT="true"

# Retry settings
RETRY_MAX_ATTEMPTS="3"
RETRY_BASE_DELAY="2"  # seconds

EOF

    log_info "Created default configuration: $config_file"
}

# Create default PRD template
create_default_prd() {
    local prd_file="$1"

    cat > "$prd_file" <<'EOF'
# Product Requirements Document

## Project Title

[Project Name]

## Overview

[Brief description of what you want to build]

## Goals

- [Primary goal]
- [Secondary goal]

## User Stories

As a [user type], I want to [action] so that [benefit].

## Requirements

### Must Have

- [Critical requirement]

### Should Have

- [Important but not critical]

### Could Have

- [Nice to have]

## Out of Scope

- [What this project will NOT include]

## Success Criteria

- [How will we know this is successful?]

---

**Instructions**: Fill in the sections above with your project requirements.
Then run `workflow clarify` to transform this into a structured PRD.

EOF

    log_info "Created PRD template: $prd_file"
}

# Main init command
cmd_init() {
    local from_file=""
    local force=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --from)
                from_file="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            -h|--help)
                show_init_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_init_help
                exit 1
                ;;
        esac
    done

    log_info "Initializing Spec-to-Ship project..."

    # Check if in git repo
    if ! git_is_repo; then
        log_warn "Not in a git repository. Consider running 'git init' first."
    fi

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Create directory structure
    log_info "Creating directory structure..."

    local dirs=(
        ".workflow"
        ".workflow/logs"
        "docs"
        "docs/gates"
        "specs"
        "src"
        "src/lib"
        "src/commands"
    )

    for dir in "${dirs[@]}"; do
        local full_path="${project_root}/${dir}"
        if [[ -d "$full_path" ]] && [[ "$force" == "false" ]]; then
            log_debug "Directory already exists: $dir"
        else
            ensure_dir "$full_path"
            log_info "Created: $dir"
        fi
    done

    # Create configuration file
    local config_file="${project_root}/.workflow/config.sh"
    if [[ -f "$config_file" ]] && [[ "$force" == "false" ]]; then
        log_warn "Configuration file already exists: $config_file (use --force to overwrite)"
    else
        create_default_config "$config_file"
    fi

    # Create or copy PRD
    local prd_file="${project_root}/docs/PRD.md"
    if [[ -n "$from_file" ]]; then
        if [[ ! -f "$from_file" ]]; then
            die "PRD file not found: $from_file"
        fi

        if [[ -f "$prd_file" ]] && [[ "$force" == "false" ]]; then
            die "PRD already exists: $prd_file (use --force to overwrite)"
        fi

        cp "$from_file" "$prd_file"
        log_info "Copied PRD from: $from_file"
    else
        if [[ -f "$prd_file" ]] && [[ "$force" == "false" ]]; then
            log_warn "PRD already exists: $prd_file (use --force to overwrite)"
        else
            create_default_prd "$prd_file"
        fi
    fi

    # Create .gitignore if needed
    local gitignore_file="${project_root}/.gitignore"
    if [[ ! -f "$gitignore_file" ]] || ! grep -q ".workflow/logs" "$gitignore_file" 2>/dev/null; then
        cat >> "$gitignore_file" <<EOF

# Spec-to-Ship workflow
.workflow/logs/
*.log

EOF
        log_info "Updated .gitignore"
    fi

    # Success message
    echo ""
    log_info "✓ Project initialized successfully!"
    echo ""
    echo "Next steps:" >&2
    echo "  1. Edit docs/PRD.md with your project requirements" >&2
    echo "  2. Run 'workflow clarify' to create structured PRD" >&2
    echo "  3. Run 'workflow specs' to generate specifications" >&2
    echo ""
    echo "Configuration: .workflow/config.sh" >&2
    echo "Documentation: docs/" >&2
    echo ""
}
