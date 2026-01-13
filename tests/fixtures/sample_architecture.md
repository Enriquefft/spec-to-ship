# System Architecture Document

## Overview

Task Management CLI is a bash-based command-line tool for local task tracking
with git integration.

## Component Map

### CLI Layer (`src/task`)

- Main entry point
- Argument parsing and routing
- User-facing output formatting

### Storage Layer (`src/lib/storage.sh`)

- JSON file read/write
- Task serialization/deserialization
- Data validation

### Task Manager (`src/lib/tasks.sh`)

- Business logic for task operations
- Task lifecycle management
- ID generation

### Git Integration (`src/lib/git.sh`)

- Auto-commit on task changes
- Commit message formatting
- Repository detection

## Interface Contracts

### POST /task (CLI: task add)

**Input**:

- `title` (string, required): Task description
- `priority` (enum: high|medium|low, default: medium)

**Output**:

- `id` (UUID): Generated task ID
- `status` (string): "created"

### GET /tasks (CLI: task list)

**Input**:

- `status` (enum: pending|in-progress|done, optional)
- `priority` (enum: high|medium|low, optional)

**Output**:

- Array of task objects

### PUT /task/:id/complete (CLI: task complete)

**Input**:

- `id` (UUID): Task to complete

**Output**:

- `status` (string): "completed"
- `completed_at` (ISO timestamp)

## Data Models

### Task

```
- id (UUID): Unique identifier
- title (string): Task description
- status (enum): pending | in-progress | done
- priority (enum): high | medium | low
- created_at (ISO timestamp): When task was created
- completed_at (ISO timestamp | null): When task was completed
```

### TaskStore

```
- tasks (array<Task>): All tasks
- version (string): Schema version
- updated_at (ISO timestamp): Last modification time
```

## Conventions

### File Naming

- Commands: `verb.sh` (e.g., `add.sh`, `list.sh`)
- Libraries: `noun.sh` (e.g., `storage.sh`, `tasks.sh`)
- Tests: `test_*.bats`

### Function Naming

- Public: `snake_case` (e.g., `task_add`, `storage_read`)
- Private: `_snake_case` (e.g., `_validate_input`)

### Error Codes

- 0: Success
- 1: General error
- 2: Invalid arguments
- 3: Resource not found

## Dependencies

### External

- bash 4.0+
- jq 1.5+
- git 2.0+

### Optional

- shellcheck (for linting)
- bats (for testing)
