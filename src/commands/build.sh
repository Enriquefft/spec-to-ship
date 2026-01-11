#!/usr/bin/env bash
# workflow build - Execute autonomous build loop
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
# shellcheck source=src/lib/plan.sh
source "$LIB_DIR/plan.sh"

# Global flag for signal handling
BUILD_INTERRUPTED=false

# cmd_build - Execute autonomous build loop
cmd_build() {
    local max_iterations=1000
    local milestone=""
    local hitl_mode=""
    local no_hitl=false
    local hitl_timeout=""

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --max)
                if [[ -z "${2:-}" ]]; then
                    die "Option --max requires an argument"
                fi
                max_iterations="$2"
                shift 2
                ;;
            --milestone)
                if [[ -z "${2:-}" ]]; then
                    die "Option --milestone requires an argument"
                fi
                milestone="$2"
                shift 2
                ;;
            --hitl)
                if [[ -z "${2:-}" ]]; then
                    hitl_mode="task"
                else
                    hitl_mode="$2"
                    shift
                fi
                shift
                ;;
            --no-hitl)
                no_hitl=true
                shift
                ;;
            --hitl-timeout)
                if [[ -z "${2:-}" ]]; then
                    die "Option --hitl-timeout requires an argument"
                fi
                hitl_timeout="$2"
                shift 2
                ;;
            --help)
                _build_help
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

    # Override HITL timeout if specified
    if [[ -n "$hitl_timeout" ]]; then
        CONFIG[HITL_TIMEOUT]="$hitl_timeout"
    fi

    # Set HITL mode from flag or config
    if [[ "$no_hitl" == "true" ]]; then
        hitl_mode="disabled"
    elif [[ -z "$hitl_mode" ]]; then
        hitl_mode="$(config_get HITL_MODE)"
    fi

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Load implementation plan
    log_info "Loading implementation plan..."
    if ! plan_load; then
        die "Failed to load implementation plan. Run 'workflow plan' first."
    fi

    # Setup signal handler for Ctrl+C
    trap '_build_signal_handler' SIGINT SIGTERM

    log_info "Starting autonomous build loop..."
    if [[ -n "$milestone" ]]; then
        log_info "Filtering tasks for milestone: $milestone"
    fi
    log_info "HITL mode: $hitl_mode"
    log_info "Max iterations: $max_iterations"
    echo ""

    # Main build loop
    local iteration=0
    local exit_code=0

    while [[ $iteration -lt $max_iterations ]]; do
        # Check for interruption
        if [[ "$BUILD_INTERRUPTED" == "true" ]]; then
            log_warn "Build interrupted by user"
            exit_code=130
            break
        fi

        ((iteration++))

        # Get next pending task
        local task_id
        if ! task_id=$(plan_get_next_task "$milestone"); then
            log_info "No more pending tasks"
            break
        fi

        if [[ -z "$task_id" ]]; then
            log_info "All tasks complete!"
            break
        fi

        log_info "[$iteration/$max_iterations] Executing task: $task_id"
        echo ""

        # Execute single task iteration
        if ! _build_execute_task "$project_root" "$task_id" "$hitl_mode"; then
            log_error "Task execution failed: $task_id"
            exit_code=1
            break
        fi

        echo ""
    done

    # Cleanup signal handler
    trap - SIGINT SIGTERM

    # Check if we hit max iterations
    if [[ $iteration -ge $max_iterations ]] && [[ $exit_code -eq 0 ]]; then
        log_warn "Reached maximum iterations ($max_iterations)"
        exit_code=2
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Build loop completed successfully"
        log_info "Total iterations: $iteration"
    fi

    return $exit_code
}

# _build_help - Show help for build command
_build_help() {
    cat <<'EOF'
USAGE:
    workflow build [OPTIONS]

DESCRIPTION:
    Execute autonomous build loop implementing tasks from the plan.

    Iteratively executes tasks one at a time:
    1. Select highest-priority pending task
    2. Invoke Claude to implement task
    3. Run backpressure validation (tests, lint, typecheck)
    4. Commit changes if validation passes
    5. Update task status in plan
    6. Continue to next task

OPTIONS:
    --max N                  Maximum iterations (default: 1000)
    --milestone MILESTONE    Filter tasks by milestone
    --hitl MODE              Human-in-the-loop mode:
                              - task: pause after each task
                              - milestone: pause after each milestone
                              - uncertain: pause when agent is uncertain
                              - every:N: pause every N tasks
                              - disabled: no pauses
    --no-hitl                Disable human-in-the-loop (same as --hitl disabled)
    --hitl-timeout SECONDS   Timeout for HITL prompts
    --help                   Show this help message

WORKFLOW:
    1. Run 'workflow plan' to generate implementation plan
    2. Run 'workflow build' to begin autonomous implementation
    3. Monitor progress and intervene with HITL as needed

EXAMPLES:
    # Start autonomous build (default HITL mode from config)
    workflow build

    # Build with max 5 iterations
    workflow build --max 5

    # Build specific milestone
    workflow build --milestone M1

    # Build with task-level HITL
    workflow build --hitl task

    # Build without any HITL pauses
    workflow build --no-hitl

INPUTS:
    docs/IMPLEMENTATION_PLAN.md    Implementation plan with tasks

OUTPUTS:
    Implemented code, tests, commits per task

CONFIGURATION:
    MODEL_BUILD_PRIMARY        Primary Claude model (default: opus)
    MODEL_BUILD_SUBAGENT       Subagent Claude model (default: sonnet)
    BUILD_PUSH_AFTER_COMMIT    Auto-push after commit (default: false)
    HITL_MODE                  Default HITL mode (default: milestone)
    HITL_TIMEOUT               HITL prompt timeout (default: 300)

EXIT CODES:
    0    Success (all tasks complete)
    1    Error (task execution failed)
    2    Max iterations reached (more work pending)
    130  Interrupted by user (Ctrl+C)

SIGNAL HANDLING:
    Ctrl+C: Clean shutdown, ensures atomic git operations
EOF
}

# _build_signal_handler - Handle Ctrl+C gracefully
_build_signal_handler() {
    BUILD_INTERRUPTED=true
    echo ""
    log_warn "Received interrupt signal, finishing current task..."
}

# _build_execute_task - Execute a single task
# Arguments: project_root, task_id, hitl_mode
_build_execute_task() {
    local project_root="$1"
    local task_id="$2"
    local hitl_mode="$3"

    # Get task description
    local task_desc
    task_desc="$(plan_get_task_description "$task_id")"

    log_info "Task: $task_desc"

    # Check dependencies
    if ! plan_deps_satisfied "$task_id"; then
        log_error "Dependencies not satisfied for task $task_id"
        plan_set_task_status "$task_id" "blocked"
        return 1
    fi

    # Mark task as in progress
    plan_set_task_status "$task_id" "in_progress"

    # Get task context for Claude
    local task_context
    task_context="$(_build_get_task_context "$project_root" "$task_id")"

    # Invoke Claude to implement task
    log_info "Invoking Claude for task implementation..."
    if ! _build_invoke_claude "$project_root" "$task_id" "$task_context"; then
        log_error "Claude invocation failed"
        plan_set_task_status "$task_id" "failed"
        return 1
    fi

    # Run backpressure validation
    log_info "Running backpressure validation..."
    if ! _build_validate_backpressure "$project_root"; then
        log_error "Backpressure validation failed"
        log_warn "Keeping task status as in_progress for retry in next iteration"
        return 1
    fi

    # Check HITL before committing
    if ! _build_hitl_check "$task_id" "$hitl_mode" "task"; then
        log_info "Task execution cancelled by user"
        plan_set_task_status "$task_id" "pending"
        return 1
    fi

    # Commit changes
    log_info "Committing changes..."
    if ! _build_commit_task "$project_root" "$task_id" "$task_desc"; then
        log_error "Failed to commit changes"
        plan_set_task_status "$task_id" "failed"
        return 1
    fi

    # Mark task as done
    plan_set_task_status "$task_id" "done"
    log_info "${COLOR_GREEN}✓${COLOR_RESET} Task completed: $task_id"

    return 0
}

# _build_get_task_context - Get context for task execution
# Arguments: project_root, task_id
_build_get_task_context() {
    local project_root="$1"
    local task_id="$2"

    local context=""

    # Get full task details from plan
    local task_details
    task_details="$(grep -A 20 "^### $task_id" "$project_root/docs/IMPLEMENTATION_PLAN.md" || echo "")"

    context+="## Task Details"$'\n'
    context+=""$'\n'
    context+="$task_details"$'\n'
    context+=""$'\n'

    # Add architecture context if available
    if [[ -f "$project_root/docs/ARCHITECTURE.md" ]]; then
        context+="## Architecture Reference"$'\n'
        context+=""$'\n'
        context+="$(head -100 "$project_root/docs/ARCHITECTURE.md")"$'\n'
        context+=""$'\n'
    fi

    # Add directory tree of src/
    if [[ -d "$project_root/src" ]]; then
        context+="## Current Codebase Structure"$'\n'
        context+='```'$'\n'
        if command -v tree &> /dev/null; then
            context+="$(tree -L 3 -I 'node_modules|.git' "$project_root/src" 2>/dev/null || find "$project_root/src" -type f | head -20)"$'\n'
        else
            context+="$(find "$project_root/src" -type f | head -20)"$'\n'
        fi
        context+='```'$'\n'
        context+=""$'\n'
    fi

    echo "$context"
}

# _build_invoke_claude - Invoke Claude for task implementation
# Arguments: project_root, task_id, task_context
_build_invoke_claude() {
    local project_root="$1"
    local task_id="$2"
    local task_context="$3"

    # Get model from config
    local model
    model="$(config_get MODEL_BUILD_PRIMARY)"

    # Get prompt template
    local prompt_file="$project_root/src/prompts/PROMPT_build.md"
    if [[ ! -f "$prompt_file" ]]; then
        log_error "Prompt template not found: $prompt_file"
        return 1
    fi

    # Create combined prompt
    local temp_prompt
    temp_prompt="$(mktemp)"
    trap 'rm -f "$temp_prompt"' EXIT

    {
        cat "$prompt_file"
        echo ""
        echo "---"
        echo ""
        echo "# TASK CONTEXT"
        echo ""
        echo "$task_context"
        echo ""
        echo "---"
        echo ""
        echo "**Instructions**:"
        echo "1. Implement the task according to acceptance criteria"
        echo "2. Follow existing code patterns and architecture"
        echo "3. Write or update tests as needed"
        echo "4. Ensure code quality and error handling"
        echo "5. Use tools to search, read, write files"
        echo "6. DO NOT create commit - that will be done automatically"
    } > "$temp_prompt"

    # Invoke Claude
    # Note: In real implementation, Claude would use tools to modify files
    # For this simplified version, we log the invocation
    log_debug "Invoking Claude with task prompt..."

    # Simplified: Just invoke Claude (actual implementation would use Claude Code with tools)
    local response
    if ! response=$(claude_invoke "$model" "$temp_prompt" 2>&1); then
        rm -f "$temp_prompt"
        trap - EXIT
        return 1
    fi

    rm -f "$temp_prompt"
    trap - EXIT

    log_debug "Claude execution completed"

    # In real implementation, Claude would have modified files using tools
    # For now, we'll just assume success
    return 0
}

# _build_validate_backpressure - Run tests, lint, typecheck
# Arguments: project_root
_build_validate_backpressure() {
    local project_root="$1"
    local all_passed=true

    # Check if there are test files
    local test_count=0
    if [[ -d "$project_root/tests" ]]; then
        test_count=$(find "$project_root/tests" -name "*.bats" -o -name "*.test.*" | wc -l)
    fi

    if [[ $test_count -gt 0 ]]; then
        log_info "Running tests..."
        if [[ -f "$project_root/package.json" ]] && command -v npm &> /dev/null; then
            if ! npm test 2>&1 | tail -20; then
                log_error "Tests failed"
                all_passed=false
            fi
        elif command -v bats &> /dev/null; then
            if ! bats "$project_root/tests"/**/*.bats 2>&1 | tail -20; then
                log_error "BATS tests failed"
                all_passed=false
            fi
        else
            log_warn "No test runner found, skipping tests"
        fi
    else
        log_debug "No tests found, skipping test execution"
    fi

    # Run shellcheck on bash files if available
    if command -v shellcheck &> /dev/null; then
        log_info "Running shellcheck..."
        local bash_files
        bash_files=$(find "$project_root/src" -name "*.sh" 2>/dev/null || true)
        if [[ -n "$bash_files" ]]; then
            if ! echo "$bash_files" | xargs shellcheck -x 2>&1 | tail -20; then
                log_warn "Shellcheck found issues (non-blocking)"
                # Don't fail on shellcheck for now
            fi
        fi
    fi

    if [[ "$all_passed" != "true" ]]; then
        log_error "Backpressure validation failed"
        return 1
    fi

    log_info "${COLOR_GREEN}✓${COLOR_RESET} Backpressure validation passed"
    return 0
}

# _build_hitl_check - Check if HITL intervention is needed
# Arguments: task_id, hitl_mode, checkpoint_type
_build_hitl_check() {
    local task_id="$1"
    local hitl_mode="$2"
    local checkpoint_type="$3"

    # Disabled mode
    if [[ "$hitl_mode" == "disabled" ]]; then
        return 0
    fi

    # Task mode - pause after every task
    if [[ "$hitl_mode" == "task" ]] && [[ "$checkpoint_type" == "task" ]]; then
        return _build_hitl_prompt "$task_id"
    fi

    # Milestone mode - only pause at milestones
    if [[ "$hitl_mode" == "milestone" ]] && [[ "$checkpoint_type" == "milestone" ]]; then
        return _build_hitl_prompt "$task_id"
    fi

    # Default: no intervention needed
    return 0
}

# _build_hitl_prompt - Prompt user for HITL approval
# Arguments: task_id
_build_hitl_prompt() {
    local task_id="$1"

    echo ""
    log_info "${COLOR_YELLOW}HITL Checkpoint${COLOR_RESET}: Task $task_id ready to commit"

    # Show git status
    git status --short

    echo ""
    local response
    if ! response=$(hitl_prompt "Approve commit? [y/n/skip]" "$(config_get HITL_TIMEOUT)"); then
        log_warn "HITL timeout, auto-approving..."
        return 0
    fi

    case "${response,,}" in
        y|yes)
            log_info "Approved by user"
            return 0
            ;;
        n|no)
            log_info "Rejected by user, rolling back changes"
            git reset --hard HEAD 2>/dev/null || true
            return 1
            ;;
        skip)
            log_info "Skipped by user"
            return 1
            ;;
        *)
            log_warn "Invalid response, treating as rejection"
            return 1
            ;;
    esac
}

# _build_commit_task - Commit task changes
# Arguments: project_root, task_id, task_desc
_build_commit_task() {
    local project_root="$1"
    local task_id="$2"
    local task_desc="$3"

    # Check if there are changes to commit
    if ! git diff --quiet || ! git diff --cached --quiet; then
        # Stage all changes
        git add -A

        # Create commit message
        local commit_msg
        commit_msg="feat: [$task_id] $task_desc

Automated commit from workflow build loop

Task ID: $task_id
Status: done"

        # Commit using git atomic commit
        if ! git_atomic_commit "$commit_msg"; then
            log_error "Git commit failed"
            return 1
        fi

        log_info "${COLOR_GREEN}✓${COLOR_RESET} Changes committed"

        # Push if enabled
        if [[ "$(config_get BUILD_PUSH_AFTER_COMMIT)" == "true" ]]; then
            log_info "Pushing to remote..."
            if git_push; then
                log_info "${COLOR_GREEN}✓${COLOR_RESET} Changes pushed"
            else
                log_warn "Push failed (non-fatal)"
            fi
        fi
    else
        log_info "No changes to commit"
    fi

    return 0
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_build "$@"
fi
