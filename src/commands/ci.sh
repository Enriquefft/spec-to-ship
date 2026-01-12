#!/usr/bin/env bash
# workflow ci - CI/CD integration commands
set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=src/lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=src/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=src/lib/cicd.sh
source "$LIB_DIR/cicd.sh"

# cmd_ci - CI/CD integration commands
cmd_ci() {
    local subcommand="${1:-help}"
    shift || true

    case "$subcommand" in
        validate|check)
            _ci_validate "$@"
            ;;
        gate)
            _ci_gate "$@"
            ;;
        report)
            _ci_report "$@"
            ;;
        hooks)
            _ci_hooks "$@"
            ;;
        pre-commit)
            _ci_pre_commit "$@"
            ;;
        pre-push)
            _ci_pre_push "$@"
            ;;
        help|--help|-h)
            _ci_help
            ;;
        *)
            die "Unknown subcommand: $subcommand. Use 'workflow ci help' for usage."
            ;;
    esac
}

# _ci_validate - Run all CI validations
_ci_validate() {
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root: $project_root"
    else
        project_root="$(pwd)"
    fi

    cicd_validate "$project_root"
}

# _ci_gate - Run specific quality gate
_ci_gate() {
    local gate_name="${1:-all}"
    local project_root

    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root: $project_root"
    else
        project_root="$(pwd)"
    fi

    case "$gate_name" in
        constitution|checklist|plan|architecture|all)
            cicd_gate "$project_root" "$gate_name"
            ;;
        *)
            die "Unknown gate: $gate_name (valid: constitution, checklist, plan, architecture, all)"
            ;;
    esac
}

# _ci_report - Generate CI report
_ci_report() {
    local format="${1:-markdown}"
    local project_root

    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root: $project_root"
    else
        project_root="$(pwd)"
    fi

    case "$format" in
        json)
            cicd_report_json "$project_root"
            ;;
        markdown|md)
            cicd_report_markdown "$project_root"
            ;;
        github)
            cicd_run_github_check "$project_root"
            ;;
        *)
            die "Unknown format: $format (valid: json, markdown, github)"
            ;;
    esac
}

# _ci_hooks - Install git hooks
_ci_hooks() {
    local action="${1:-install}"
    local project_root

    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root: $project_root"
    else
        die "Not in a git repository"
    fi

    case "$action" in
        install)
            cicd_install_hooks "$project_root"
            ;;
        *)
            die "Unknown action: $action (valid: install)"
            ;;
    esac
}

# _ci_pre_commit - Run pre-commit hook
_ci_pre_commit() {
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        cicd_pre_commit "$project_root"
    else
        die "Not in a git repository"
    fi
}

# _ci_pre_push - Run pre-push hook
_ci_pre_push() {
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        cicd_pre_push "$project_root"
    else
        die "Not in a git repository"
    fi
}

# _ci_help - Show help
_ci_help() {
    cat <<'EOF'
USAGE:
    workflow ci <SUBCOMMAND> [OPTIONS]

DESCRIPTION:
    CI/CD integration commands for quality gates and automated checks.

SUBCOMMANDS:
    validate        Run all CI/CD validations
    gate NAME       Run specific quality gate
    report FORMAT   Generate CI report (json, markdown, github)
    hooks install   Install git hooks (pre-commit, pre-push)
    pre-commit      Run pre-commit checks (called by git hook)
    pre-push        Run pre-push checks (called by git hook)
    help            Show this help message

QUALITY GATES:
    constitution    Validate project constitution
    checklist       Validate feature checklists
    plan            Check implementation plan exists
    architecture    Check architecture document exists
    all             Run all gates (default)

REPORT FORMATS:
    json            JSON format for CI systems
    markdown        Markdown format for PRs
    github          GitHub Actions format (sets outputs and summary)

EXAMPLES:
    # Run all validations
    workflow ci validate

    # Check specific gate
    workflow ci gate constitution

    # Generate JSON report for CI
    workflow ci report json

    # Generate markdown report for PR
    workflow ci report markdown

    # Install git hooks
    workflow ci hooks install

GITHUB ACTIONS USAGE:
    - name: Run workflow checks
      run: |
        ./src/workflow ci report github
      env:
        GITHUB_OUTPUT: ${{ github.output }}
        GITHUB_STEP_SUMMARY: ${{ github.step_summary }}

GITLAB CI USAGE:
    workflow-check:
      script:
        - ./src/workflow ci report json > workflow-report.json
      artifacts:
        reports:
          dotenv: workflow-report.json

EOF
}
