# Library Interface Contracts

**Date**: 2026-01-11 **Version**: 1.0.0

## Overview

Internal library contracts for `src/lib/*.sh` modules. All functions follow Bash
conventions: return 0 on success, non-zero on error, output to stdout, errors to
stderr.

---

## src/lib/common.sh

Shared utilities for logging, colors, and error handling.

### Functions

#### `log_debug(message)`

Log debug message (only if VERBOSE=true).

- **Params**: `message` - string to log
- **Stdout**: None
- **Stderr**: `[timestamp] [DEBUG] [component] message`
- **Returns**: 0

#### `log_info(message)`

Log info message.

- **Params**: `message` - string to log
- **Stdout**: None
- **Stderr**: `[timestamp] [INFO] [component] message`
- **Returns**: 0

#### `log_warn(message)`

Log warning message.

- **Params**: `message` - string to log
- **Stdout**: None
- **Stderr**: `[timestamp] [WARN] [component] message`
- **Returns**: 0

#### `log_error(message)`

Log error message.

- **Params**: `message` - string to log
- **Stdout**: None
- **Stderr**: `[timestamp] [ERROR] [component] message`
- **Returns**: 0

#### `die(message, exit_code)`

Log error and exit.

- **Params**:
  - `message` - error description
  - `exit_code` - exit code (default: 1)
- **Stdout**: None
- **Stderr**: Error message
- **Returns**: Never (exits)

#### `require_command(cmd)`

Check if command exists.

- **Params**: `cmd` - command name
- **Stdout**: None
- **Stderr**: Error if missing
- **Returns**: 0 if exists, 1 if missing

#### `require_file(path)`

Check if file exists.

- **Params**: `path` - file path
- **Stdout**: None
- **Stderr**: Error if missing
- **Returns**: 0 if exists, 1 if missing

#### `ensure_dir(path)`

Create directory if not exists.

- **Params**: `path` - directory path
- **Stdout**: None
- **Stderr**: Error on failure
- **Returns**: 0 on success, 1 on failure

---

## src/lib/config.sh

Configuration loading and validation.

### Functions

#### `config_load()`

Load configuration from default or specified path.

- **Params**: None (uses `$WORKFLOW_CONFIG` or default)
- **Stdout**: None
- **Stderr**: Warnings for missing config (uses defaults)
- **Returns**: 0
- **Side Effects**: Sets all `MODEL_*`, `HITL_*`, `BUILD_*` variables

#### `config_get(key)`

Get configuration value.

- **Params**: `key` - config key name
- **Stdout**: Value
- **Stderr**: None
- **Returns**: 0 if found, 1 if not found

#### `config_set(key, value)`

Set configuration value (runtime only, not persisted).

- **Params**:
  - `key` - config key name
  - `value` - new value
- **Stdout**: None
- **Stderr**: Error if invalid key
- **Returns**: 0 on success, 1 on invalid key

#### `config_validate()`

Validate all configuration values.

- **Params**: None
- **Stdout**: None
- **Stderr**: Validation errors
- **Returns**: 0 if valid, 1 if invalid

#### `config_model_for_phase(phase)`

Get model name for specific workflow phase.

- **Params**: `phase` - one of: `clarify`, `specs`, `arch`, `plan`, `build`,
  `gate`, `feedback`
- **Stdout**: Model name (e.g., `opus`, `sonnet`)
- **Stderr**: None
- **Returns**: 0

---

## src/lib/git.sh

Git operations with atomic commit support.

### Functions

#### `git_is_repo()`

Check if current directory is in a git repo.

- **Params**: None
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if repo, 1 if not

#### `git_root()`

Get git repository root path.

- **Params**: None
- **Stdout**: Absolute path
- **Stderr**: Error if not in repo
- **Returns**: 0 on success, 1 if not in repo

#### `git_branch()`

Get current branch name.

- **Params**: None
- **Stdout**: Branch name
- **Stderr**: None
- **Returns**: 0

#### `git_is_clean()`

Check if working directory is clean.

- **Params**: None
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if clean, 1 if dirty

#### `git_atomic_commit(message)`

Stage all changes and commit atomically.

- **Params**: `message` - commit message
- **Stdout**: Commit hash
- **Stderr**: Progress, errors
- **Returns**: 0 on success, 1 on backpressure failure
- **Side Effects**: Runs backpressure validation before commit

#### `git_push()`

Push current branch to origin.

- **Params**: None
- **Stdout**: None
- **Stderr**: Progress, errors
- **Returns**: 0 on success, 1 on failure

#### `git_reset_staged()`

Unstage all staged files.

- **Params**: None
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0

---

## src/lib/claude.sh

Claude CLI wrapper with retry logic.

### Functions

#### `claude_invoke(model, prompt_file)`

Invoke Claude with specified model and prompt.

- **Params**:
  - `model` - model name (`opus`, `sonnet`, `haiku`)
  - `prompt_file` - path to prompt file
- **Stdout**: Claude response
- **Stderr**: Progress, errors
- **Returns**: 0 on success, 1 on failure (after retries)
- **Side Effects**: Logs to session log

#### `claude_invoke_with_input(model, prompt_file, input)`

Invoke Claude with prompt and stdin input.

- **Params**:
  - `model` - model name
  - `prompt_file` - path to prompt file
  - `input` - additional context via stdin
- **Stdout**: Claude response
- **Stderr**: Progress, errors
- **Returns**: 0 on success, 1 on failure

#### `claude_stream(model, prompt_file)`

Invoke Claude with streaming output.

- **Params**:
  - `model` - model name
  - `prompt_file` - path to prompt file
- **Stdout**: Streamed response
- **Stderr**: Progress, errors
- **Returns**: 0 on success, 1 on failure

---

## src/lib/hitl.sh

Human-in-the-loop interaction handling.

### Functions

#### `hitl_is_enabled()`

Check if HITL is enabled.

- **Params**: None
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if enabled, 1 if disabled

#### `hitl_mode()`

Get current HITL mode.

- **Params**: None
- **Stdout**: Mode string (`task`, `milestone`, `uncertain`, `every:N`)
- **Stderr**: None
- **Returns**: 0

#### `hitl_should_pause(trigger_type, iteration)`

Check if HITL should pause at this point.

- **Params**:
  - `trigger_type` - one of: `task`, `milestone`, `uncertain`, `iteration`
  - `iteration` - current iteration number
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if should pause, 1 if continue

#### `hitl_prompt(question, type, options)`

Prompt user for input.

- **Params**:
  - `question` - question to display
  - `type` - question type: `clarification`, `decision`, `validation`, `scope`
  - `options` - optional array of valid responses
- **Stdout**: User response
- **Stderr**: Question display
- **Returns**: 0 on response, 1 on timeout
- **Side Effects**: Logs to `docs/hitl-log.md`

#### `hitl_prompt_yn(question)`

Prompt for yes/no response.

- **Params**: `question` - question to display
- **Stdout**: `y` or `n`
- **Stderr**: Question display
- **Returns**: 0 on yes, 1 on no

#### `hitl_log(question, response, action)`

Log HITL interaction.

- **Params**:
  - `question` - what was asked
  - `response` - user's answer
  - `action` - what system did
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0
- **Side Effects**: Appends to `docs/hitl-log.md`

---

## src/lib/plan.sh

Implementation plan parsing and manipulation.

### Functions

#### `plan_load()`

Load implementation plan into memory.

- **Params**: None
- **Stdout**: None
- **Stderr**: Errors
- **Returns**: 0 on success, 1 if not found

#### `plan_get_next_task(milestone)`

Get next pending task for milestone.

- **Params**: `milestone` - milestone ID or empty for any
- **Stdout**: Task ID (e.g., `T1.1`)
- **Stderr**: None
- **Returns**: 0 if found, 1 if none pending

#### `plan_get_task_status(task_id)`

Get status of specific task.

- **Params**: `task_id` - task identifier
- **Stdout**: Status (`pending`, `in_progress`, `done`, `failed`, `blocked`)
- **Stderr**: None
- **Returns**: 0 if found, 1 if not found

#### `plan_set_task_status(task_id, status)`

Update task status.

- **Params**:
  - `task_id` - task identifier
  - `status` - new status
- **Stdout**: None
- **Stderr**: Errors
- **Returns**: 0 on success, 1 on failure
- **Side Effects**: Updates `IMPLEMENTATION_PLAN.md`

#### `plan_get_task_deps(task_id)`

Get dependencies for task.

- **Params**: `task_id` - task identifier
- **Stdout**: Space-separated list of dependency task IDs
- **Stderr**: None
- **Returns**: 0

#### `plan_deps_satisfied(task_id)`

Check if all dependencies are satisfied.

- **Params**: `task_id` - task identifier
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if all deps done, 1 if any pending/failed

#### `plan_milestone_complete(milestone)`

Check if all tasks in milestone are done.

- **Params**: `milestone` - milestone ID
- **Stdout**: None
- **Stderr**: None
- **Returns**: 0 if complete, 1 if incomplete
