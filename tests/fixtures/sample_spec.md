# Spec: Task Management CLI - Core Task Operations

## Summary

Implement core task management operations (add, list, complete) with local file storage in git repositories.

## Dependencies

None - this is a foundational component

## Goals

1. Enable users to quickly add and track tasks from command line
2. Store tasks in structured, version-controlled format
3. Provide fast filtering and querying capabilities

## Non-Goals

- Cloud synchronization
- Team collaboration
- Complex reporting

## Technical Design

### Data Model

Tasks stored in `.tasks/tasks.json`:

```json
{
  "tasks": [
    {
      "id": "uuid-v4",
      "title": "string",
      "status": "pending|in-progress|done",
      "priority": "high|medium|low",
      "created_at": "ISO-8601 timestamp",
      "completed_at": "ISO-8601 timestamp | null"
    }
  ]
}
```

### CLI Interface

```bash
# Add task
task add "Fix login bug" --priority high

# List tasks
task list
task list --status pending
task list --priority high

# Complete task
task complete <task-id>

# Show task details
task show <task-id>
```

### Implementation Approach

1. Use bash for CLI argument parsing
2. Use `jq` for JSON manipulation
3. Store tasks in git repository root `.tasks/` directory
4. Auto-commit task changes to git

## Acceptance Criteria

1. User can add task with title and priority
2. Tasks persist across sessions
3. User can list all tasks or filter by status
4. User can mark task as complete
5. All task operations complete in < 500ms
6. Task data is human-readable JSON
7. Works without network connection

## Test Plan

### Unit Tests

- JSON parsing and writing
- Task ID generation
- Status transitions

### Integration Tests

- Full workflow: add → list → complete
- Filter operations
- Edge cases: empty task list, invalid IDs

### Performance Tests

- List operation with 100 tasks
- Add operation stress test
