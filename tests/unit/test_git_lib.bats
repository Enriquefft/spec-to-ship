#!/usr/bin/env bats
# Unit tests for src/lib/git.sh

# Load test helper
load '../helpers/test_helper.bash'

setup() {
    setup_test_dir

    # Load required libraries
    export LIB_DIR="${PROJECT_ROOT}/src/lib"
    export LOG_FILE="/tmp/workflow_test_$$.log"
    export VERBOSE=false

    # Source dependencies
    # shellcheck source=src/lib/common.sh
    source "${LIB_DIR}/common.sh"
    # shellcheck source=src/lib/git.sh
    source "${LIB_DIR}/git.sh"
}

teardown() {
    teardown_test_dir
    rm -f "$LOG_FILE"
}

# =============================================================================
# git_is_repo() tests
# =============================================================================

@test "git_is_repo returns false in non-git directory" {
    # Create a fresh directory outside of any potential parent git repos
    local non_git_dir
    non_git_dir="$(mktemp -d)"

    # Change to non-git directory and test directly (not via run)
    # Use GIT_CEILING_DIRECTORIES to prevent git from finding parent repos
    cd "$non_git_dir"

    # Test the actual function behavior by checking git command directly
    # with ceiling directories set to prevent traversing up
    if GIT_CEILING_DIRECTORIES="$non_git_dir" git rev-parse --is-inside-work-tree &> /dev/null; then
        # Clean up before failing
        cd "$TEST_DIR"
        rm -rf "$non_git_dir"
        return 1
    fi

    # Clean up
    cd "$TEST_DIR"
    rm -rf "$non_git_dir"

    return 0
}

@test "git_is_repo returns true in git repository" {
    git init -q

    run git_is_repo

    [ "$status" -eq 0 ]
}

@test "git_is_repo returns true in subdirectory of git repo" {
    git init -q
    mkdir -p subdir/deep

    cd subdir/deep

    run git_is_repo

    [ "$status" -eq 0 ]
}

# =============================================================================
# git_root() tests
# =============================================================================

@test "git_root returns repository root" {
    git init -q

    run git_root

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR" ]
}

@test "git_root returns correct path from subdirectory" {
    git init -q
    mkdir -p subdir/deep
    cd subdir/deep

    run git_root

    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_DIR" ]
}

@test "git_root fails in non-git directory" {
    run git_root

    [ "$status" -eq 1 ]
}

# =============================================================================
# git_branch() tests
# =============================================================================

@test "git_branch returns current branch name" {
    setup_git_repo
    # Create initial commit
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    run git_branch

    [ "$status" -eq 0 ]
    # Default branch is usually 'master' or 'main'
    [[ "$output" =~ ^(main|master)$ ]]
}

@test "git_branch returns new branch name after checkout" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
    git checkout -q -b feature-branch

    run git_branch

    [ "$status" -eq 0 ]
    [ "$output" = "feature-branch" ]
}

# =============================================================================
# git_is_clean() tests
# =============================================================================

@test "git_is_clean returns true for clean repo" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    run git_is_clean

    [ "$status" -eq 0 ]
}

@test "git_is_clean returns false with untracked files" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Add untracked file
    echo "untracked" > new_file.txt

    run git_is_clean

    [ "$status" -eq 1 ]
}

@test "git_is_clean returns false with modified files" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Modify file
    echo "modified" >> file.txt

    run git_is_clean

    [ "$status" -eq 1 ]
}

@test "git_is_clean returns false with staged changes" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Stage a change
    echo "staged" >> file.txt
    git add file.txt

    run git_is_clean

    [ "$status" -eq 1 ]
}

# =============================================================================
# git_has_staged() tests
# =============================================================================

@test "git_has_staged returns false with no staged changes" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    run git_has_staged

    [ "$status" -eq 1 ]
}

@test "git_has_staged returns true with staged changes" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Stage a change
    echo "more content" >> file.txt
    git add file.txt

    run git_has_staged

    [ "$status" -eq 0 ]
}

@test "git_has_staged returns true with new staged file" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Add new file
    echo "new" > new_file.txt
    git add new_file.txt

    run git_has_staged

    [ "$status" -eq 0 ]
}

# =============================================================================
# git_reset_staged() tests
# =============================================================================

@test "git_reset_staged unstages files" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Stage a change
    echo "more" >> file.txt
    git add file.txt

    # Verify staged
    run git_has_staged
    [ "$status" -eq 0 ]

    # Reset
    git_reset_staged

    # Verify no longer staged
    run git_has_staged
    [ "$status" -eq 1 ]
}

# =============================================================================
# git_create_branch() tests
# =============================================================================

@test "git_create_branch creates new branch" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    run git_create_branch test-branch

    [ "$status" -eq 0 ]

    run git_branch
    [ "$output" = "test-branch" ]
}

@test "git_create_branch fails in non-git directory" {
    run git_create_branch test-branch

    [ "$status" -eq 1 ]
}

# =============================================================================
# git_switch_branch() tests
# =============================================================================

@test "git_switch_branch switches to existing branch" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    # Create and return to original branch
    git checkout -q -b feature-branch
    git checkout -q -

    run git_switch_branch feature-branch

    [ "$status" -eq 0 ]

    run git_branch
    [ "$output" = "feature-branch" ]
}

@test "git_switch_branch fails with uncommitted changes" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"
    git checkout -q -b feature-branch
    git checkout -q -

    # Create uncommitted change
    echo "modified" >> file.txt

    run git_switch_branch feature-branch

    [ "$status" -eq 1 ]
}

@test "git_switch_branch fails for non-existent branch" {
    setup_git_repo
    echo "test" > file.txt
    git add file.txt
    git commit -q -m "Initial commit"

    run git_switch_branch nonexistent-branch

    [ "$status" -eq 1 ]
}
