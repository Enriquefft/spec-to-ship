# Research: Spec-to-Ship Automated Development Workflow

**Date**: 2026-01-11 **Branch**: `001-spec-to-ship-workflow`

## Overview

This document captures research findings and technical decisions for
implementing the Spec-to-Ship CLI tool. All unknowns from Technical Context have
been resolved.

---

## Decision 1: Bash Script Architecture

**Decision**: Use POSIX-compatible Bash with modular script organization

**Rationale**:

- Spec requires POSIX-compatible Bash for cross-platform support (FR
  dependencies)
- Modular organization (`src/lib/`, `src/commands/`) enables isolated testing
- `source` mechanism allows shared libraries without package management
  complexity
- Claude Code CLI is invoked via subprocess, making Bash a natural orchestrator

**Alternatives Considered**:

- **Node.js/TypeScript**: Rejected - adds npm dependency, spec explicitly lists
  Bash
- **Python**: Rejected - additional runtime dependency, Bash sufficient for
  orchestration
- **Go/Rust compiled binary**: Rejected - spec emphasizes editable prompt
  templates, Bash is transparent

---

## Decision 2: Testing Framework (BATS)

**Decision**: Use BATS (Bash Automated Testing System) for all shell script
testing

**Rationale**:

- Purpose-built for testing Bash scripts with TAP output format
- Supports setup/teardown, assertions, and test isolation
- Integrates with CI systems via standard exit codes
- Active community, well-documented

**Alternatives Considered**:

- **shunit2**: Less active maintenance, BATS has broader adoption
- **Custom test harness**: Rejected - unnecessary complexity, BATS is mature
- **shellspec**: Good alternative, but BATS has simpler syntax for this use case

**Best Practices Applied**:

- Unit tests for library functions (`src/lib/*.sh`)
- Integration tests for commands with fixtures
- Test isolation via temp directories created in setup

---

## Decision 3: Configuration Format

**Decision**: Bash sourceable config file (`.workflow/config.sh`) with env var
overrides

**Rationale**:

- Native to Bash - no parsing library needed
- Environment variables take precedence (per FR-026 secrets requirement)
- Human-readable and editable
- Simple syntax: `KEY=value` or `KEY="${OVERRIDE:-default}"`

**Alternatives Considered**:

- **YAML/JSON**: Requires `jq`/`yq` for parsing, adds complexity
- **TOML**: Requires external parser, not standard
- **INI**: Would need custom parser in Bash

**Config File Structure**:

```bash
# Model selection per phase
MODEL_CLARIFY="${MODEL_CLARIFY:-opus}"
MODEL_BUILD_PRIMARY="${MODEL_BUILD_PRIMARY:-opus}"
# ... etc

# HITL defaults
HITL_ENABLED="${HITL_ENABLED:-false}"
HITL_MODE="${HITL_MODE:-milestone}"
```

---

## Decision 4: Claude CLI Integration Pattern

**Decision**: Wrapper library (`src/lib/claude.sh`) with model selection, retry
logic, and JSON output parsing

**Rationale**:

- Centralizes Claude invocation for consistent behavior
- Implements exponential backoff for rate limits (per edge case spec)
- Uses `--output-format=stream-json` for structured logging
- Model selection via `--model` flag based on phase config

**Alternatives Considered**:

- **Direct invocation in each command**: Rejected - code duplication,
  inconsistent error handling
- **Python wrapper**: Rejected - spec is Bash-only

**Implementation Pattern**:

```bash
# src/lib/claude.sh
claude_invoke() {
    local model="$1" prompt_file="$2"
    local retry_count=0 max_retries=3
    while [ $retry_count -lt $max_retries ]; do
        if claude --model "$model" -p "$(cat "$prompt_file")" \
           --output-format=stream-json 2>>"$LOG_FILE"; then
            return 0
        fi
        ((retry_count++))
        sleep $((2 ** retry_count))  # exponential backoff
    done
    return 1
}
```

---

## Decision 5: Task State Persistence

**Decision**: Inline YAML-style markers in `IMPLEMENTATION_PLAN.md` for task
states

**Rationale**:

- Single source of truth - plan is both human-readable and machine-parseable
- States: `pending`, `in_progress`, `done`, `failed`, `blocked` (per
  clarification)
- No separate database or state file to sync
- `grep`/`sed` sufficient for state transitions

**Alternatives Considered**:

- **Separate JSON state file**: Rejected - creates sync issues, duplicates info
- **SQLite**: Rejected - overkill for single-user CLI, adds dependency
- **Git-based state (tags/refs)**: Rejected - complex, poor visibility

**Task Format in Plan**:

```markdown
- [ ] **Task T1.1**: Implement init command `status: pending`
- [x] **Task T1.2**: Create directory structure `status: done`
- [ ] **Task T1.3**: Generate AGENTS.md `status: blocked` `depends: T1.1`
```

---

## Decision 6: HITL Interaction Mechanism

**Decision**: Simple stdin/stdout prompting with timeout support via `read`
command

**Rationale**:

- Native Bash `read -t` provides timeout functionality
- No external dependencies for basic interaction
- Responses logged to `docs/hitl-log.md` per FR-019
- Supports short answers (y/n) and free-form text

**Alternatives Considered**:

- **Dialog/whiptail TUI**: Rejected - not available on all systems
- **Web-based dashboard**: Rejected - out of scope per spec
- **External notification (Slack/email)**: Rejected - adds complexity, out of
  scope

**Implementation Pattern**:

```bash
# src/lib/hitl.sh
hitl_prompt() {
    local question="$1" timeout="${2:-0}"  # 0 = no timeout
    echo "$question" >&2
    if [ "$timeout" -gt 0 ]; then
        read -t "$timeout" -r response || response="timeout"
    else
        read -r response
    fi
    echo "$(date -Iseconds) | Q: $question | A: $response" >> docs/hitl-log.md
    echo "$response"
}
```

---

## Decision 7: Logging Strategy

**Decision**: Append-only session logs to
`.workflow/logs/YYYY-MM-DD_HH-MM-SS.log`

**Rationale**:

- Per-session files enable easy debugging of specific runs
- Timestamp-based naming prevents conflicts
- Append-only prevents data loss on crash
- `--verbose` flag echoes to stderr for real-time visibility

**Log Format**:

```
[2026-01-11T14:30:00] [INFO] [build] Starting task T1.1
[2026-01-11T14:30:01] [DEBUG] [claude] Invoking model=opus prompt=PROMPT_build.md
[2026-01-11T14:30:15] [INFO] [git] Committed: abc123 "Implement init command"
[2026-01-11T14:30:16] [ERROR] [build] Backpressure failed: 2 test failures
```

---

## Decision 8: Git Operation Safety

**Decision**: Atomic commit pattern with pre-commit validation and trap-based
cleanup

**Rationale**:

- Per edge case: "System uses atomic git operations to ensure partial commits
  don't occur"
- Stage files, validate, commit in single transaction
- `trap` handlers ensure cleanup on Ctrl+C (FR-022)
- No `--force` operations on shared branches

**Implementation Pattern**:

```bash
# src/lib/git.sh
git_atomic_commit() {
    local message="$1"
    trap 'git reset HEAD -- . 2>/dev/null' EXIT
    git add -A
    if ! run_backpressure; then
        git reset HEAD -- .
        return 1
    fi
    git commit -m "$message"
    trap - EXIT
    return 0
}
```

---

## Summary

All technical decisions align with:

- Spec requirements (FR-001 through FR-029)
- Clarifications (logging, secrets, task states)
- Success criteria (performance targets, recovery, error messages)

No unresolved NEEDS CLARIFICATION items remain. Ready to proceed to Phase 1:
Design & Contracts.
