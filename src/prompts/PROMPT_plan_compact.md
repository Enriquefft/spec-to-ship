# Implementation Plan Generator

Generate an implementation plan from specs and architecture.

## Output Structure

```markdown
# Implementation Plan: [Project]

**Created**: [Date]
**Version**: 1.0

## Overview
[Brief summary - 2-3 sentences]

## Task Summary

**REQUIRED FORMAT** - Build system parses this:

### Milestone 1: [Name]
- [ ] T001 [M1] Task description (depends: none)
- [ ] T002 [M1] Task description (depends: T001) [P]

### Milestone 2: [Name]
- [ ] T003 [M2] Task description (depends: T002)

## Detailed Tasks

### T001 - [Title]
**Milestone**: M1
**Dependencies**: None
**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2
**Files**: `path/to/files`

[Repeat for each task]

## Quality Gates

### After M1
- [ ] Tests pass
- [ ] Coverage >70%

## Risk Mitigation
[Key risks and mitigations]
```

## Rules

1. **Task Size**: 2-8 hours each
2. **Dependencies**: Form valid DAG (no cycles)
3. **Markers**: `[P]` = parallel-safe, `[TDD]` = test-first
4. **Priorities**: High (blocking), Medium (important), Low (nice-to-have)
5. **Each task MUST appear in both Task Summary AND Detailed Tasks**

## Task Types

- **Setup**: Project structure, tooling
- **Core**: Business logic, features
- **Test**: Unit/integration tests
- **Integration**: External systems
- **Documentation**: README, API docs

## Format Examples

**Good - Has both summary and detail:**
```markdown
## Task Summary
- [ ] T001 [M1] Setup project structure (depends: none)

## Detailed Tasks
### T001 - Setup project structure
**Dependencies**: None
**Acceptance Criteria**:
- [ ] Directory structure matches architecture
```

**Bad - Missing summary entry:**
```markdown
## Detailed Tasks
### T001 - Setup project structure
[No corresponding entry in Task Summary - INVALID]
```

Generate a complete, actionable plan following this format exactly.
