# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Spec-to-Ship** is a Bash-based workflow system (POSIX-compatible, shellcheck-compliant) that orchestrates AI models to transform PRDs into working software through phases: clarify → specs → arch → plan → build → gate.

## Development Commands

```bash
# Run tests
bats tests/                      # All tests
bats tests/unit/                 # Unit tests only
bats tests/integration/          # Integration tests only

# Lint
shellcheck src/**/*.sh           # Lint all shell scripts
./check-shellcheck.sh            # Project-wide with filtering

# Test your changes
workflow --verbose build --max 5 # Debug mode with iteration limit
```

## Architecture

### Directory Structure

```
src/
  workflow              # Main entry point (dispatcher to subcommands)
  commands/            # Subcommand implementations (build.sh, plan.sh, etc.)
  lib/
    common.sh          # Logging, colors, error handling (source this first)
    config.sh          # Configuration management
    provider.sh        # Multi-provider abstraction layer
    plan.sh            # Task state management
  prompts/             # AI prompt templates
tests/
  unit/                # Pure function tests
  integration/         # Full workflow tests
  fixtures/            # Test data (sample PRDs, plans)
```

### Key Design Patterns

**Provider Abstraction** (`src/lib/provider.sh`)
- Multi-provider support with automatic fallback chains
- Use: `provider_invoke_for_phase "build" "$prompt_file"`
- Config: `PROVIDER_DEFAULT`, `PROVIDER_<PHASE>`, `PROVIDER_<PROVIDER>_MODEL_<CAPABILITY>`

**Plan-as-State** (`src/lib/plan.sh`)
- Implementation plan in `docs/IMPLEMENTATION_PLAN.md` is source of truth
- Tasks have states: pending/in_progress/done/blocked
- Update via: `plan_update_task_state`

**Agent Polyfill** (`src/lib/agent.sh`)
- Wraps text models to simulate tool-calling with XML tags: `<tool_code>`, `<ask_user>`, `<final_answer>`

### Per project configuration

Lives in `.workflow/config.sh`. Override with env vars: `WORKFLOW_<KEY>=value`

## Code Style

1. **Strict mode:** `set -euo pipefail` at top of every script
2. **Shellcheck:** Must pass with no warnings
3. **Function naming:**
   - Public: `verb_noun` (e.g., `config_get`, `provider_invoke`)
   - Internal: `_verb_noun` (e.g., `_log_to_file`)
4. **Quoting:** Always quote variables: `"$var"` not `$var`
5. **Error handling:** Use `die` for fatal, return non-zero for recoverable
6. **Constants:** Use `readonly VERSION="1.0.0"`
7. **Budget:** Tests should NEVER run claude or any other llm.

## Common Pitfalls

1. **Paths:** Use `get_git_root` for absolute paths, avoid relative paths
2. **Sourcing:** Check files exist before sourcing
3. **Test fixtures:** Don't modify `tests/fixtures/` directly - use temp copies
4. **Shellcheck:** CI blocks on violations - run before committing

## Important Files

- `src/lib/common.sh` - Core utilities, source this first in all scripts
- `src/lib/provider.sh` - Provider abstraction for AI invocations
- `src/lib/plan.sh` - Plan state management
- `src/workflow` - Main dispatcher
- `docs/COMMANDS.md` - Full command reference
