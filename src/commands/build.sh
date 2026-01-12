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
# shellcheck source=src/lib/interaction.sh
source "$LIB_DIR/interaction.sh"
# shellcheck source=src/lib/tempfiles.sh
source "$LIB_DIR/tempfiles.sh"
# shellcheck source=src/lib/context.sh
source "$LIB_DIR/context.sh"
# shellcheck source=src/lib/plan.sh
source "$LIB_DIR/plan.sh"
# shellcheck source=src/lib/agent.sh
source "$LIB_DIR/agent.sh"

# Global flag for signal handling
BUILD_INTERRUPTED=false

# cmd_build - Execute autonomous build loop
cmd_build() {
    local max_iterations=1000
    local milestone=""
    local hitl_mode=""
    local no_hitl=false
    local hitl_timeout=""
    local no_git=false

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
            --no-git)
                no_git=true
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

    # Validate HITL mode
    case "$hitl_mode" in
        task|milestone|uncertain|disabled)
            # Valid modes
            ;; 
        every:*)
            # Validate every:N format
            if ! [[ "$hitl_mode" =~ ^every:[0-9]+$ ]]; then
                die "Invalid HITL mode format: $hitl_mode (expected every:N where N is a number)"
            fi
            ;; 
        *)
            die "Invalid HITL mode: $hitl_mode (must be: task, milestone, uncertain, disabled, or every:N)"
            ;; 
    esac

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Validate git repository (unless --no-git specified)
    local use_git=true
    if ! git_is_repo; then
        if [[ "$no_git" == "true" ]]; then
            use_git=false
            log_warn "Running without git integration (--no-git specified)"
        else
            die "Not in a git repository. Use --no-git to run without git integration."
        fi
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
    local tasks_executed=0
    local current_milestone=""
    local prev_milestone=""

    while [[ $iteration -lt $max_iterations ]]; do
        # Check for interruption
        if [[ "$BUILD_INTERRUPTED" == "true" ]]; then
            log_warn "Build interrupted by user"
            exit_code=130
            break
        fi

        ((iteration++)) || true

        # Get next pending task
        local task_id
        set +e  # Temporarily disable exit on error for plan_get_next_task
        task_id=$(plan_get_next_task "$milestone")
        local get_task_result=$?
        set -e  # Re-enable exit on error

        if [[ $get_task_result -ne 0 ]] || [[ -z "$task_id" ]]; then
            if [[ $tasks_executed -eq 0 ]]; then
                log_info "No pending tasks found"
            else
                log_info "All pending tasks complete"
                # Check for milestone completion HITL
                if [[ -n "$prev_milestone" ]]; then
                    _build_hitl_milestone_check "$prev_milestone" "$hitl_mode"
                fi
            fi
            break
        fi

        log_info "[$iteration/$max_iterations] Executing task: $task_id"
        echo ""

        # Detect milestone change
        if command -v plan_get_task_milestone &> /dev/null; then
            current_milestone="${PLAN_TASK_MILESTONE[$task_id]:-""}"
        fi

        # Check for milestone transition
        if [[ -n "$prev_milestone" && "$prev_milestone" != "$current_milestone" ]]; then
            # Milestone complete - check for HITL
            if ! _build_hitl_milestone_check "$prev_milestone" "$hitl_mode"; then
                log_warn "Milestone continuation rejected by user"
                exit_code=1
                break
            fi
        fi

        # Execute single task iteration
        if ! _build_execute_task "$project_root" "$task_id" "$hitl_mode" "$use_git"; then
            log_error "Task execution failed: $task_id"
            exit_code=1
            break
        fi

        ((tasks_executed++)) || true
        prev_milestone="$current_milestone"

        # Check for every:N HITL
        if [[ "$hitl_mode" =~ ^every:([0-9]+)$ ]]; then
            local interval="${BASH_REMATCH[1]}"
            if [[ $((tasks_executed % interval)) -eq 0 ]]; then
                if ! _build_hitl_iteration_check "$tasks_executed" "$hitl_mode" "$use_git"; then
                    log_warn "Iteration review rejected by user"
                    exit_code=1
                    break
                fi
            fi
        fi

        echo ""
    done

    # Cleanup signal handler
    trap - SIGINT SIGTERM

    # Check if we hit max iterations with pending work remaining
    if [[ $iteration -ge $max_iterations ]] && [[ $exit_code -eq 0 ]]; then
        # Check if there are still pending tasks
        local remaining_task
        set +e  # Temporarily disable exit on error for plan_get_next_task
        remaining_task=$(plan_get_next_task "$milestone")
        set -e  # Re-enable exit on error
        if [[ -n "$remaining_task" ]]; then
            log_warn "Reached maximum iterations ($max_iterations) with pending tasks remaining"
            exit_code=2
        fi
    fi

    if [[ $exit_code -eq 0 ]]; then
        echo ""
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Build loop completed successfully"
        log_info "Iterations: $iteration, Tasks executed: $tasks_executed"
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
    2. Invoke Agent to implement task (reading/writing files)
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
    --no-git                 Run without git integration (no commits)
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

INPUTS:
    docs/IMPLEMENTATION_PLAN.md    Implementation plan with tasks

OUTPUTS:
    Implemented code, tests, commits per task

CONFIGURATION:
    MODEL_BUILD_PRIMARY        Primary model for agent loop
    HITL_MODE                  Default HITL mode (default: milestone)

EXIT CODES:
    0    Success (all tasks complete)
    1    Error (task execution failed)
    2    Max iterations reached (more work pending)
    130  Interrupted by user (Ctrl+C)
EOF
}

# _build_signal_handler - Handle Ctrl+C gracefully
_build_signal_handler() {
    BUILD_INTERRUPTED=true
    echo ""
    log_warn "Received interrupt signal, finishing current task..."
}

# _build_execute_task - Execute a single task
# Arguments: project_root, task_id, hitl_mode, use_git
_build_execute_task() {
    local project_root="$1"
    local task_id="$2"
    local hitl_mode="$3"
    local use_git="${4:-true}"

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

    # Invoke Agent to implement task using minimal context
    local plan_file="$project_root/docs/IMPLEMENTATION_PLAN.md"

    # Create a compressed task context (minimal plan context + task-specific info)
    local context_file
    context_file="$(tempfile_create)"
    {
        echo "# TARGET TASK: $task_id"
        echo "$task_desc"
        echo ""
        # Use compressed plan context instead of full plan (token optimization)
        context_compress_plan "$plan_file" "$task_id"
    } > "$context_file"

    log_info "Invoking Agent for task implementation..."

    # Call the AGENT LOOP with minimal context
    if ! agent_run_task "Implement task $task_id: $task_desc" "$context_file"; then
        log_error "Agent failed to implement task"
        plan_set_task_status "$task_id" "failed"
        tempfile_remove "$context_file"
        return 1
    fi
    tempfile_remove "$context_file"

    # Run backpressure validation
    log_info "Running backpressure validation..."
    if ! _build_validate_backpressure "$project_root"; then
        log_error "Backpressure validation failed"
        log_warn "Keeping task status as in_progress for retry in next iteration"
        return 1
    fi

    # Check HITL before committing
    if ! _build_hitl_check "$task_id" "$hitl_mode" "task" "$use_git"; then
        log_info "Task execution cancelled by user"
        plan_set_task_status "$task_id" "pending"
        return 1
    fi

    # Commit changes
    log_info "Committing changes..."
    if ! _build_commit_task "$project_root" "$task_id" "$task_desc" "$use_git"; then
        log_error "Failed to commit changes"
        plan_set_task_status "$task_id" "failed"
        return 1
    fi

    # Mark task as done
    plan_set_task_status "$task_id" "done"
    log_info "${COLOR_GREEN}✓${COLOR_RESET} Task completed: $task_id"

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
# Arguments: task_id, hitl_mode, checkpoint_type, use_git
_build_hitl_check() {
    local task_id="$1"
    local hitl_mode="$2"
    local checkpoint_type="$3"
    local use_git="${4:-true}"

    # Disabled mode
    if [[ "$hitl_mode" == "disabled" ]]; then
        return 0
    fi

    # Task mode - pause after every task
    if [[ "$hitl_mode" == "task" ]] && [[ "$checkpoint_type" == "task" ]]; then
        return _build_hitl_prompt "$task_id" "$use_git"
    fi

    # Milestone mode - only pause at milestones
    if [[ "$hitl_mode" == "milestone" ]] && [[ "$checkpoint_type" == "milestone" ]]; then
        return _build_hitl_prompt "$task_id" "$use_git"
    fi

    # Default: no intervention needed
    return 0
}

# _build_hitl_prompt - Prompt user for HITL approval
# Arguments: task_id, use_git
_build_hitl_prompt() {
    local task_id="$1"
    local use_git="${2:-true}"

    echo ""
    log_info "${COLOR_YELLOW}HITL Checkpoint${COLOR_RESET}: Task $task_id ready to commit"

    # Show git status only if in a git repo
    if [[ "$use_git" == "true" ]]; then
        echo ""
        git status --short
        echo ""

        # Show diff summary
        echo -e "${COLOR_BLUE}Changes summary:${COLOR_RESET}"
        git diff --stat --cached 2>/dev/null || git diff --stat 2>/dev/null || echo "No changes"
        echo ""
    else
        echo ""
        echo -e "${COLOR_BLUE}Note:${COLOR_RESET} Not in a git repository, commit step will be skipped"
        echo ""
    fi

    local response
    if ! response=$(hitl_prompt "Approve commit? [y/n/edit/skip]" "decision" "y) Yes - approve and commit\nn) No - rollback and retry\nedit) Edit - open in editor\nskip) Skip - skip this task"); then
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
            if [[ "$use_git" == "true" ]]; then
                git reset --hard HEAD 2>/dev/null || true
                git clean -fd 2>/dev/null || true
            fi
            return 1
            ;; 
        edit|e)
            log_info "Opening editor for manual changes..."
            # Launch editor if available
            if [[ -n "${EDITOR:-}" ]]; then
                $EDITOR .
            elif command -v code &> /dev/null; then
                code .
            elif command -v vi &> /dev/null; then
                vi .
            else
                log_warn "No editor found, use EDITOR environment variable"
            fi
            # Ask again after editing
            return _build_hitl_prompt "$task_id" "$use_git"
            ;; 
        skip|s)
            log_info "Skipped by user"
            if [[ "$use_git" == "true" ]]; then
                git reset --hard HEAD 2>/dev/null || true
            fi
            return 1
            ;; 
        *)
            log_warn "Invalid response: $response, treating as rejection"
            return 1
            ;; 
    esac
}

# _build_hitl_milestone_check - Check for milestone completion HITL
# Arguments: milestone, hitl_mode
_build_hitl_milestone_check() {
    local milestone="$1"
    local hitl_mode="$2"

    # Only trigger for milestone mode
    if [[ "$hitl_mode" != "milestone" ]]; then
        return 0
    fi

    echo ""
    log_info "${COLOR_YELLOW}HITL Milestone Checkpoint${COLOR_RESET}: Milestone $milestone complete"
    echo ""

    local response
    if ! response=$(hitl_prompt "Proceed to next milestone? [y/n/rework/replan]" "milestone" "y) Yes - continue to next milestone\nn) No - stop execution\nrework) Rework - return to planning\nreplan) Replan - regenerate plan"); then
        log_warn "HITL timeout, auto-continuing..."
        return 0
    fi

    case "${response,,}" in
        y|yes|proceed)
            log_info "Proceeding to next milestone"
            return 0
            ;; 
        n|no|stop)
            log_info "Stopping at milestone boundary"
            return 1
            ;; 
        rework)
            log_info "User requested rework - stopping for manual intervention"
            echo ""
            log_info "To continue, review and update the plan, then run: workflow build"
            return 1
            ;; 
        replan)
            log_info "User requested replan - stopping for plan regeneration"
            echo ""
            log_info "To continue, run: workflow plan --regen && workflow build"
            return 1
            ;; 
        *)
            log_warn "Invalid response: $response, stopping"
            return 1
            ;; 
    esac
}

# _build_hitl_iteration_check - Check for every:N iteration HITL
# Arguments: iteration_count, hitl_mode, use_git
_build_hitl_iteration_check() {
    local iteration_count="$1"
    local hitl_mode="$2"
    local use_git="${3:-true}"

    echo ""
    log_info "${COLOR_YELLOW}HITL Iteration Checkpoint${COLOR_RESET}: $iteration_count tasks executed"
    echo ""

    # Show recent commits only if in a git repo
    if [[ "$use_git" == "true" ]]; then
        echo -e "${COLOR_BLUE}Recent commits:${COLOR_RESET}"
        git log --oneline -5 2>/dev/null || echo "No commits yet"
        echo ""
    fi

    local response
    if ! response=$(hitl_prompt "Continue execution? [y/n/pause]" "iteration" "y) Yes - continue\nn) No - stop\npause) Pause - review and resume manually"); then
        log_warn "HITL timeout, auto-continuing..."
        return 0
    fi

    case "${response,,}" in
        y|yes|continue)
            log_info "Continuing execution"
            return 0
            ;; 
        n|no|stop)
            log_info "Stopping execution at iteration checkpoint"
            return 1
            ;; 
        pause|p)
            log_info "Pausing for manual review"
            echo ""
            log_info "To resume, run: workflow build"
            return 1
            ;; 
        *)
            log_warn "Invalid response: $response, continuing"
            return 0
            ;; 
    esac
}

# _build_commit_task - Commit task changes
# Arguments: project_root, task_id, task_desc, use_git
_build_commit_task() {
    local project_root="$1"
    local task_id="$2"
    local task_desc="$3"
    local use_git="${4:-true}"

    # Skip commit if not in a git repository
    if [[ "$use_git" != "true" ]]; then
        log_debug "Git disabled, skipping commit"
        return 0
    fi

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