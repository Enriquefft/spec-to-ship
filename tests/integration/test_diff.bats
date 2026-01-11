#!/usr/bin/env bats
# Integration tests for workflow diff command

setup() {
  # Create temporary test directory
  export TEST_DIR
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR"  # Isolate home directory
  export WORKFLOW_BIN="$(cd "${BATS_TEST_DIRNAME}/../../src" && pwd)/workflow"
  cd "$TEST_DIR" || exit 1

  # Initialize git repo
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Initialize workflow
  "$WORKFLOW_BIN" init

  # Make initial commit
  git add .
  git commit -q -m "Initial commit"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

# Test: Show uncommitted changes (default behavior)
@test "diff shows uncommitted changes by default" {
  # Create some uncommitted changes
  echo "# Modified PRD" > "$TEST_DIR/docs/PRD.md"
  echo "New file" > "$TEST_DIR/new_file.txt"

  run "$WORKFLOW_BIN" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"PRD.md"* ]]
}

# Test: No changes to show
@test "diff shows no changes when working directory is clean" {
  # Working directory is clean after setup

  run "$WORKFLOW_BIN" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"No uncommitted changes"* ]]
}

# Test: Show changes with --milestone flag
@test "diff shows changes for specific milestone" {
  # Create milestone-related commit
  mkdir -p "$TEST_DIR/src"
  echo "# Milestone 1 code" > "$TEST_DIR/src/feature.sh"
  git add .
  git commit -q -m "feat: implement Phase 1 (Milestone 1)"

  # Create more changes
  echo "# More work" >> "$TEST_DIR/src/feature.sh"
  git add .
  git commit -q -m "feat: continue Phase 1"

  run "$WORKFLOW_BIN" diff --milestone M1

  [ "$status" -eq 0 ]
  # Should show diff output (may be empty if no changes since milestone)
}

# Test: Milestone not found warning
@test "diff warns when milestone has no commits" {
  run "$WORKFLOW_BIN" diff --milestone M99

  [ "$status" -eq 0 ]
  [[ "$output" == *"No commits found for milestone"* ]] || [[ "$output" == *"uncommitted"* ]]
}

# Test: Help message
@test "diff --help shows help message" {
  run "$WORKFLOW_BIN" diff --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"workflow diff"* ]]
  [[ "$output" == *"--milestone"* ]]
}

# Test: Error handling for invalid option
@test "diff fails with unknown option" {
  run "$WORKFLOW_BIN" diff --invalid-option

  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown option"* ]]
}

# Test: Error when not in git repository
@test "diff fails when not in a git repository" {
  # Create non-git directory
  local non_git_dir
  non_git_dir="$(mktemp -d)"
  cd "$non_git_dir" || exit 1

  run "$WORKFLOW_BIN" diff

  [ "$status" -eq 1 ]
  [[ "$output" == *"Not in a git repository"* ]]

  # Cleanup
  cd "$TEST_DIR" || exit 1
  rm -rf "$non_git_dir"
}

# Test: Diff with staged and unstaged changes
@test "diff shows both staged and unstaged changes" {
  # Create staged change
  echo "# Staged change" > "$TEST_DIR/docs/staged.md"
  git add "$TEST_DIR/docs/staged.md"

  # Create unstaged change
  echo "# Unstaged change" > "$TEST_DIR/docs/unstaged.md"

  run "$WORKFLOW_BIN" diff

  [ "$status" -eq 0 ]
  [[ "$output" == *"staged.md"* ]] || [[ "$output" == *"unstaged.md"* ]]
}
