#!/usr/bin/env bash
# src/lib/git.sh - Git operations with atomic commit support

# Source common utilities
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# git_is_repo() - Check if current directory is in a git repo
git_is_repo() {
    git rev-parse --is-inside-work-tree &> /dev/null
}

# git_root() - Get git repository root path
git_root() {
    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    git rev-parse --show-toplevel
}

# git_branch() - Get current branch name
git_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null
}

# git_is_clean() - Check if working directory is clean
git_is_clean() {
    if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
        return 1
    fi
    return 0
}

# git_has_staged() - Check if there are staged changes
git_has_staged() {
    if [[ -n "$(git diff --cached --name-only 2>/dev/null)" ]]; then
        return 0
    fi
    return 1
}

# git_reset_staged() - Unstage all staged files
git_reset_staged() {
    git reset HEAD -- . &> /dev/null || true
    log_debug "Unstaged all files"
    return 0
}

# _run_backpressure() - Internal: Run backpressure validation
_run_backpressure() {
    local git_root
    git_root="$(git_root)" || return 1

    log_info "Running backpressure validation..."

    # Source config to check what validations are enabled
    # shellcheck source=src/lib/config.sh
    source "${LIB_DIR}/config.sh"
    config_load

    local tests_enabled
    local typecheck_enabled
    local lint_enabled
    tests_enabled="$(config_get BUILD_BACKPRESSURE_TESTS)"
    typecheck_enabled="$(config_get BUILD_BACKPRESSURE_TYPECHECK)"
    lint_enabled="$(config_get BUILD_BACKPRESSURE_LINT)"

    local failed=false

    # Run tests if enabled
    if [[ "$tests_enabled" == "true" ]]; then
        if [[ -f "${git_root}/tests/run_tests.sh" ]]; then
            log_info "Running tests..."
            if ! bash "${git_root}/tests/run_tests.sh"; then
                log_error "Tests failed"
                failed=true
            fi
        elif command -v bats &> /dev/null && [[ -d "${git_root}/tests" ]]; then
            log_info "Running BATS tests..."
            if ! bats "${git_root}/tests/"*.bats 2>&1 | tee -a "$LOG_FILE"; then
                log_error "BATS tests failed"
                failed=true
            fi
        else
            log_warn "No test framework found, skipping tests"
        fi
    fi

    # Run type checking if enabled
    if [[ "$typecheck_enabled" == "true" ]]; then
        if command -v tsc &> /dev/null && [[ -f "${git_root}/tsconfig.json" ]]; then
            log_info "Running TypeScript type checking..."
            if ! tsc --noEmit; then
                log_error "Type checking failed"
                failed=true
            fi
        else
            log_debug "TypeScript not configured, skipping type check"
        fi
    fi

    # Run linting if enabled
    if [[ "$lint_enabled" == "true" ]]; then
        if command -v shellcheck &> /dev/null; then
            log_info "Running shellcheck..."
            local shell_files
            shell_files=$(find "${git_root}/src" -name "*.sh" -o -name "workflow" 2>/dev/null)

            if [[ -n "$shell_files" ]]; then
                if ! echo "$shell_files" | xargs shellcheck; then
                    log_error "Shellcheck failed"
                    failed=true
                fi
            fi
        else
            log_debug "Shellcheck not found, skipping lint"
        fi
    fi

    if [[ "$failed" == "true" ]]; then
        log_error "Backpressure validation failed"
        return 1
    fi

    log_info "Backpressure validation passed"
    return 0
}

# git_atomic_commit(message) - Stage all changes and commit atomically
git_atomic_commit() {
    local message="$1"

    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    # Check if there are changes to commit
    if git_is_clean; then
        log_warn "No changes to commit"
        return 0
    fi

    log_debug "Starting atomic commit: $message"

    # Set up trap to unstage on failure
    trap 'git_reset_staged' EXIT ERR

    # Stage all changes
    log_debug "Staging all changes..."
    if ! git add -A; then
        log_error "Failed to stage changes"
        return 1
    fi

    # Run backpressure validation
    if ! _run_backpressure; then
        log_error "Backpressure validation failed, rolling back staged changes"
        git_reset_staged
        trap - EXIT ERR
        return 1
    fi

    # Commit
    log_debug "Creating commit..."
    if ! git commit -m "$message"; then
        log_error "Failed to create commit"
        git_reset_staged
        trap - EXIT ERR
        return 1
    fi

    # Get commit hash
    local commit_hash
    commit_hash="$(git rev-parse HEAD)"
    log_info "Created commit: $commit_hash"

    # Clear trap
    trap - EXIT ERR

    echo "$commit_hash"
    return 0
}

# git_push() - Push current branch to origin
git_push() {
    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    local branch
    branch="$(git_branch)"

    log_info "Pushing branch: $branch"

    if ! git push origin "$branch"; then
        log_error "Failed to push branch: $branch"
        return 1
    fi

    log_info "Successfully pushed branch: $branch"
    return 0
}

# git_create_branch(branch_name) - Create and switch to new branch
git_create_branch() {
    local branch_name="$1"

    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    log_info "Creating branch: $branch_name"

    if ! git checkout -b "$branch_name"; then
        log_error "Failed to create branch: $branch_name"
        return 1
    fi

    log_info "Switched to new branch: $branch_name"
    return 0
}

# git_switch_branch(branch_name) - Switch to existing branch
git_switch_branch() {
    local branch_name="$1"

    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    if ! git_is_clean; then
        log_error "Working directory has uncommitted changes"
        return 1
    fi

    log_info "Switching to branch: $branch_name"

    if ! git checkout "$branch_name"; then
        log_error "Failed to switch to branch: $branch_name"
        return 1
    fi

    log_info "Switched to branch: $branch_name"
    return 0
}

# git_commit_files(files, message) - Commit specific files
git_commit_files() {
    local message="$1"
    shift
    local files=("$@")

    if ! git_is_repo; then
        log_error "Not in a git repository"
        return 1
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "No files specified"
        return 1
    fi

    log_debug "Committing specific files: ${files[*]}"

    # Set up trap
    trap 'git_reset_staged' EXIT ERR

    # Stage specific files
    if ! git add "${files[@]}"; then
        log_error "Failed to stage files"
        return 1
    fi

    # Run backpressure validation
    if ! _run_backpressure; then
        log_error "Backpressure validation failed"
        git_reset_staged
        trap - EXIT ERR
        return 1
    fi

    # Commit
    if ! git commit -m "$message"; then
        log_error "Failed to create commit"
        git_reset_staged
        trap - EXIT ERR
        return 1
    fi

    local commit_hash
    commit_hash="$(git rev-parse HEAD)"
    log_info "Created commit: $commit_hash"

    trap - EXIT ERR
    echo "$commit_hash"
    return 0
}
