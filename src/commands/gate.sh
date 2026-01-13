#!/usr/bin/env bash
# workflow gate - Validate milestone completion with acceptance criteria
set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=src/lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=src/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=src/lib/plan.sh
source "$LIB_DIR/plan.sh"

# cmd_gate - Validate milestone completion
cmd_gate() {
    local milestone=""
    local force=false

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --milestone)
                if [[ -z "${2:-}" ]]; then
                    die "Option --milestone requires an argument"
                fi
                milestone="$2"
                shift 2
                ;;
            --force)
                force=true
                shift
                ;;
            --help)
                _gate_help
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

    # Load implementation plan
    log_info "Loading implementation plan..."
    if ! plan_load; then
        die "Failed to load implementation plan. Run 'workflow plan' first."
    fi

    # Determine milestone to validate
    if [[ -z "$milestone" ]]; then
        # Auto-detect current milestone (last completed milestone)
        milestone=$(_gate_detect_current_milestone)
        if [[ -z "$milestone" ]]; then
            die "No milestone specified and unable to auto-detect. Use --milestone option."
        fi
        log_info "Auto-detected milestone: $milestone"
    fi

    log_info "Validating milestone: $milestone"
    echo ""

    # Check if milestone tasks are complete
    if ! _gate_check_milestone_complete "$milestone"; then
        log_error "Milestone $milestone has incomplete tasks"
        echo ""
        log_info "Complete all tasks before running gate validation:"
        log_info "  workflow build --milestone $milestone"
        return 1
    fi

    # Create gate reports directory
    local gates_dir="$project_root/docs/gates"
    ensure_dir "$gates_dir"

    # Run gate validation
    local gate_report="$gates_dir/${milestone}-gate-report.md"
    log_info "Running gate validation for $milestone..."
    echo ""

    local validation_result
    if validation_result=$(_gate_run_validation "$project_root" "$milestone" "$gate_report"); then
        echo ""
        log_info "${COLOR_GREEN}✓${COLOR_RESET} Gate validation PASSED for $milestone"
        log_info "Report: $gate_report"
        return 0
    else
        echo ""
        log_error "Gate validation FAILED for $milestone"
        log_info "Report: $gate_report"
        echo ""

        if [[ "$force" == "true" ]]; then
            log_warn "Proceeding despite gate failure (--force specified)"
            log_warn "Review failures and address them as soon as possible"
            return 2
        else
            log_info "Fix issues and re-run gate, or use --force to proceed anyway"
            return 1
        fi
    fi
}

# _gate_help - Show help for gate command
_gate_help() {
    cat <<'EOF'
USAGE:
    workflow gate [OPTIONS]

DESCRIPTION:
    Validate milestone completion with acceptance criteria checks.

    Verifies that:
    - All milestone tasks are complete
    - Tests pass
    - Acceptance criteria are met
    - Code quality checks pass

OPTIONS:
    --milestone MILESTONE    Validate specific milestone (auto-detected if not specified)
    --force                  Proceed even if validation fails (exit code 2)
    --help                   Show this help message

WORKFLOW:
    1. Complete milestone tasks with 'workflow build'
    2. Run 'workflow gate' to validate completion
    3. Address any failures before proceeding to next milestone

EXAMPLES:
    # Validate current milestone
    workflow gate

    # Validate specific milestone
    workflow gate --milestone M1

    # Proceed despite failures
    workflow gate --force

OUTPUTS:
    docs/gates/M{n}-gate-report.md    Validation report

CONFIGURATION:
    None

EXIT CODES:
    0    Validation passed
    1    Validation failed
    2    Validation failed but --force specified

NOTES:
    Gate validation is recommended between milestones to ensure quality.
    Failed gates block progression unless --force is used.
EOF
}

# _gate_detect_current_milestone - Detect the current milestone to validate
_gate_detect_current_milestone() {
    # Find the last completed milestone
    local last_milestone=""

    # Iterate through tasks to find milestones
    for task_id in $(echo "${!PLAN_TASKS[@]}" | tr ' ' '\n' | sort); do
        local status="${PLAN_TASK_STATUS[$task_id]}"
        local task_milestone="${PLAN_TASK_MILESTONE[$task_id]}"

        if [[ "$status" == "done" && -n "$task_milestone" ]]; then
            last_milestone="$task_milestone"
        elif [[ "$status" != "done" && -n "$task_milestone" && "$task_milestone" == "$last_milestone" ]]; then
            # Found incomplete task in current milestone, this milestone is not complete
            echo ""
            return 1
        fi
    done

    echo "$last_milestone"
}

# _gate_check_milestone_complete - Check if all milestone tasks are done
# Arguments: milestone
_gate_check_milestone_complete() {
    local milestone="$1"

    local total=0
    local complete=0

    for task_id in $(echo "${!PLAN_TASKS[@]}" | tr ' ' '\n' | sort); do
        local status="${PLAN_TASK_STATUS[$task_id]}"
        local task_milestone="${PLAN_TASK_MILESTONE[$task_id]}"

        if [[ "$task_milestone" == "$milestone" ]]; then
            ((total++))
            if [[ "$status" == "done" ]]; then
                ((complete++))
            else
                log_debug "Incomplete task: $task_id (status: $status)"
            fi
        fi
    done

    log_debug "Milestone $milestone: $complete/$total tasks complete"

    if [[ $complete -eq $total && $total -gt 0 ]]; then
        return 0
    else
        log_warn "Milestone $milestone: $complete/$total tasks complete"
        return 1
    fi
}

# _gate_run_validation - Run gate validation checks
# Arguments: project_root, milestone, report_file
_gate_run_validation() {
    local project_root="$1"
    local milestone="$2"
    local report_file="$3"

    local tests_passed=0
    local tests_failed=0
    local validation_passed=true
    local details=""

    # Initialize report
    cat > "$report_file" <<EOF
# Gate Validation Report: $milestone

**Date**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Milestone**: $milestone
**Project**: $(basename "$project_root")

---

## Validation Results

EOF

    # Detect test command: config > run_tests.sh > package.json > Makefile
    log_info "Running test suite..."
    local test_output=""
    local test_cmd=""
    test_cmd=$(config_get "TEST_COMMAND" 2>/dev/null || echo "")

    if [[ -z "$test_cmd" ]]; then
        if [[ -f "$project_root/tests/run_tests.sh" ]]; then
            test_cmd="bash tests/run_tests.sh"
        elif [[ -f "$project_root/package.json" ]] && grep -q '"test"' "$project_root/package.json"; then
            # Works with npm, yarn, pnpm, bun, deno
            test_cmd="npm test"
        elif [[ -f "$project_root/Makefile" ]] && grep -q "^test:" "$project_root/Makefile"; then
            test_cmd="make test"
        fi
    fi

    if [[ -n "$test_cmd" ]]; then
        if test_output=$(cd "$project_root" && eval "$test_cmd" 2>&1); then
            log_info "${COLOR_GREEN}✓${COLOR_RESET} Tests passed"
            details+="### Test Suite"$'\n\n'
            details+="**Status**: ✓ PASSED"$'\n\n'
            details+="**Command**: \`$test_cmd\`"$'\n\n'
        else
            local test_exit_code=$?
            log_warn "Tests failed (exit code: $test_exit_code)"
            validation_passed=false
            details+="### Test Suite"$'\n\n'
            details+="**Status**: ✗ FAILED"$'\n\n'
            details+="**Command**: \`$test_cmd\`"$'\n\n'
            details+="<details>"$'\n'"<summary>Test Output</summary>"$'\n\n'"$'```\n'"$test_output"$'\n```\n'"</details>"$'\n\n'
        fi
    else
        log_warn "No test command configured, skipping test validation"
        details+="### Test Suite"
        details+=$'\n\n'
        details+="**Status**: ⊘ SKIPPED - no test command configured"
        details+=$'\n\n'
    fi

    # Check shellcheck if bash project
    if [[ -d "$project_root/src" ]] && find "$project_root/src" -name "*.sh" -type f | head -1 | grep -q "."; then
        log_info "Running shellcheck validation..."
        local shellcheck_output
        local shellcheck_exit_code=0

        if shellcheck_output=$(find "$project_root/src" -name "*.sh" -type f -exec shellcheck {} + 2>&1); then
            log_info "${COLOR_GREEN}✓${COLOR_RESET} Shellcheck passed"
            details+="### Shellcheck"$'\n\n'
            details+="**Status**: ✓ PASSED"$'\n\n'
        else
            shellcheck_exit_code=$?
            log_warn "Shellcheck found issues"
            validation_passed=false
            details+="### Shellcheck"$'\n\n'
            details+="**Status**: ✗ FAILED"$'\n\n'
            details+="<details>"$'\n'"<summary>Shellcheck Output</summary>"$'\n\n'"$'```\n'"$shellcheck_output"$'\n```\n'"</details>"$'\n\n'
        fi
    fi

    # Write results to report
    if [[ "$validation_passed" == "true" ]]; then
        cat >> "$report_file" <<EOF
**Overall Status**: ✓ PASSED

**Summary**:
- Tests Passed: $tests_passed
- Tests Failed: $tests_failed

---

## Details

$details

---

## Recommendation

✓ **PROCEED** - All validation checks passed. Safe to continue to next milestone.

EOF
        return 0
    else
        cat >> "$report_file" <<EOF
**Overall Status**: ✗ FAILED

**Summary**:
- Tests Passed: $tests_passed
- Tests Failed: $tests_failed

---

## Details

$details

---

## Recommendation

✗ **REWORK** - Address validation failures before proceeding to next milestone.

**Next Steps**:
1. Review test failures and fix issues
2. Re-run: \`workflow gate --milestone $milestone\`
3. Use \`--force\` only if failures are acceptable for now

EOF
        return 1
    fi
}

# Only run if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_gate "$@"
fi
