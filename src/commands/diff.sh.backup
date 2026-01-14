#!/usr/bin/env bash
# src/commands/diff.sh - Show changes since last milestone
# Usage: workflow diff [options]

set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/git.sh
source "${LIB_DIR}/git.sh"
# shellcheck source=src/lib/plan.sh
source "${LIB_DIR}/plan.sh"

# cmd_diff() - Main diff command handler
cmd_diff() {
    local milestone=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --milestone)
                if [[ -z "${2:-}" ]]; then
                    die "Option --milestone requires an argument"
                fi
                milestone="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    log_debug "Starting diff command"

    # Check if we're in a git repo
    if ! git_is_repo; then
        die "Not in a git repository"
    fi

    # Get git root
    local git_root
    git_root=$(git_root)

    if [[ -n "$milestone" ]]; then
        # Show changes for specific milestone
        show_milestone_diff "$git_root" "$milestone"
    else
        # Show all uncommitted changes by default
        show_current_diff "$git_root"
    fi

    return 0
}

# show_current_diff() - Show uncommitted changes
show_current_diff() {
    local git_root="$1"

    log_debug "Showing uncommitted changes"

    # Change to git root for consistent paths
    cd "$git_root" || die "Failed to change to git root: $git_root"

    # Check if there are any changes
    if git_is_clean; then
        log_info "No uncommitted changes"
        return 0
    fi

    # Show git diff (both staged and unstaged)
    log_debug "Running: git diff HEAD"
    git diff HEAD

    return 0
}

# show_milestone_diff() - Show changes for specific milestone
show_milestone_diff() {
    local git_root="$1"
    local milestone="$2"

    log_debug "Showing changes for milestone: $milestone"

    # Change to git root for consistent paths
    cd "$git_root" || die "Failed to change to git root: $git_root"

    # Find the first commit that mentions this milestone
    local milestone_start_commit
    milestone_start_commit=$(git log --oneline --all --grep="milestone.*${milestone}" --grep="Milestone.*${milestone}" --grep="Phase.*${milestone#M}" -i | tail -1 | cut -d' ' -f1)

    if [[ -z "$milestone_start_commit" ]]; then
        # Try to find commits that mention the milestone in any way
        milestone_start_commit=$(git log --oneline --all | grep -i "$milestone" | tail -1 | cut -d' ' -f1 || echo "")
    fi

    if [[ -z "$milestone_start_commit" ]]; then
        log_warn "No commits found for milestone: $milestone"
        log_info "Showing all uncommitted changes instead"
        git diff HEAD
        return 0
    fi

    log_info "Showing changes since milestone $milestone started (commit: $milestone_start_commit)"

    # Show diff from that commit to current state
    git diff "${milestone_start_commit}^..HEAD"

    return 0
}

# show_help() - Display help message
show_help() {
    cat <<EOF
workflow diff - Show changes since last milestone

USAGE:
    workflow diff [options]

DESCRIPTION:
    Display git diff output showing changes in the current milestone.

    By default, shows all uncommitted changes in the working directory.
    With --milestone, shows changes since the specified milestone began.

OPTIONS:
    --milestone MILESTONE    Show changes for specific milestone (e.g., M1, M2)
    --help, -h              Show this help message

EXAMPLES:
    # Show all uncommitted changes
    workflow diff

    # Show changes since milestone M1 started
    workflow diff --milestone M1

    # Show changes for Phase 2
    workflow diff --milestone M2

EXIT CODES:
    0    Success

NOTES:
    - Changes include both staged and unstaged modifications
    - Output follows standard git diff format
    - Pipe to 'less' for better viewing: workflow diff | less
EOF
}

# Main execution
main() {
    cmd_diff "$@"
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
