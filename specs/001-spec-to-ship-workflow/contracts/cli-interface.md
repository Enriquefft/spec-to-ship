# CLI Interface Contract: workflow

**Date**: 2026-01-11
**Version**: 1.0.0

## Overview

The `workflow` command is the single entry point for all Spec-to-Ship operations. It follows standard CLI conventions with subcommands, flags, and exit codes.

---

## Command Structure

```
workflow <subcommand> [options] [arguments]
```

## Global Options

| Option | Short | Type | Description |
|--------|-------|------|-------------|
| `--help` | `-h` | flag | Show help for command |
| `--version` | `-v` | flag | Show version |
| `--verbose` | | flag | Enable debug output to stderr |
| `--config` | `-c` | path | Override config file path |

---

## Subcommands

### workflow init

Initialize project with Spec-to-Ship structure.

**Usage**: `workflow init [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--from` | path | none | Copy PRD from specified file |
| `--force` | flag | false | Overwrite existing files |

**Exit Codes**:
- `0`: Success
- `1`: Error (permission denied, invalid path)

**Stdout**: Progress messages
**Stderr**: Errors only

---

### workflow clarify

Transform rough PRD into structured format.

**Usage**: `workflow clarify [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--no-interactive` | flag | false | Best-effort without questions |

**Exit Codes**:
- `0`: Success
- `1`: Error (PRD not found, Claude API failure)

**Stdout**: Clarification questions (interactive mode)
**Stdin**: User responses (interactive mode)
**Stderr**: Progress, errors

---

### workflow specs

Generate spec files from structured PRD.

**Usage**: `workflow specs [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--force` | flag | false | Overwrite existing specs |

**Exit Codes**:
- `0`: Success
- `1`: Error (structured PRD not found)

**Stdout**: Generated spec filenames
**Stderr**: Progress, warnings, errors

---

### workflow arch

Generate architecture document from specs.

**Usage**: `workflow arch [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--review` | flag | false | Open interactive refinement |

**Exit Codes**:
- `0`: Success
- `1`: Error (no specs found)

**Stdout**: Architecture summary (non-interactive)
**Stdin**: Refinement input (interactive mode)
**Stderr**: Progress, errors

---

### workflow plan

Generate implementation plan.

**Usage**: `workflow plan [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--regen` | flag | false | Regenerate from scratch |
| `--milestone` | string | all | Focus on specific milestone (e.g., `M1`) |

**Exit Codes**:
- `0`: Success
- `1`: Error (specs/arch not found)

**Stdout**: Plan summary, milestone list
**Stderr**: Progress, warnings, errors

---

### workflow build

Execute autonomous build loop.

**Usage**: `workflow build [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--max` | integer | 0 | Max iterations (0 = unlimited) |
| `--milestone` | string | all | Execute specific milestone only |
| `--hitl` | enum | none | Enable HITL: `task`, `milestone`, `uncertain`, `every:N` |
| `--no-hitl` | flag | false | Explicitly disable HITL |
| `--hitl-timeout` | duration | none | Auto-continue timeout (e.g., `5m`, `1h`) |

**Exit Codes**:
- `0`: All tasks complete
- `1`: Error (plan not found, unrecoverable failure)
- `2`: Max iterations reached

**Stdout**: Task progress, HITL prompts
**Stdin**: HITL responses
**Stderr**: Debug info, errors

**Signals**:
- `SIGINT` (Ctrl+C): Clean exit, no partial commits

---

### workflow gate

Run milestone validation.

**Usage**: `workflow gate [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--milestone` | string | latest | Validate specific milestone |
| `--force` | flag | false | Proceed despite failures |

**Exit Codes**:
- `0`: Gate passed
- `1`: Gate failed
- `2`: Gate failed but --force used

**Stdout**: Gate report summary
**Stderr**: Test output, errors

---

### workflow status

Show current workflow state.

**Usage**: `workflow status`

**Exit Codes**:
- `0`: Success

**Stdout**:
```
Phase: [Requirements|Architecture|Planning|Execution|Validation]
Status: [description]
Milestone: [current] ([N/M] tasks complete)
HITL: [enabled/disabled] ([waiting/not waiting])
```

---

### workflow diff

Show changes since last milestone.

**Usage**: `workflow diff [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--milestone` | string | latest | Compare against specific milestone |

**Exit Codes**:
- `0`: Success

**Stdout**: Git diff output

---

### workflow config

Manage configuration.

**Usage**: `workflow config [options]`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `--edit` | flag | false | Open config in $EDITOR |
| `--get` | string | none | Get specific config value |
| `--set` | string | none | Set config value (`key=value`) |

**Exit Codes**:
- `0`: Success
- `1`: Error (invalid key, permission denied)

**Stdout**: Config values (--get) or full config (no options)

---

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `CLAUDE_API_KEY` | Claude API authentication | Yes (if not in claude CLI config) |
| `WORKFLOW_CONFIG` | Override config file path | No |
| `WORKFLOW_LOG_LEVEL` | Log verbosity: `DEBUG`, `INFO`, `WARN`, `ERROR` | No (default: `INFO`) |

---

## Exit Code Summary

| Code | Meaning |
|------|---------|
| `0` | Success / Complete |
| `1` | Error (see stderr for details) |
| `2` | Partial success (max iterations, gate failed with --force) |

---

## Output Formats

### Standard Output
- Human-readable by default
- Progress indicators for long operations
- Structured data when piped (detect TTY)

### Standard Error
- Error messages with context
- Debug info when `--verbose` enabled
- Never contains secrets

### Log Files
- Session logs to `.workflow/logs/`
- HITL interactions to `docs/hitl-log.md`
- Gate reports to `docs/gates/`
