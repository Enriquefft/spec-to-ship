# Data Model: Spec-to-Ship Automated Development Workflow

**Date**: 2026-01-11 **Branch**: `001-spec-to-ship-workflow`

## Overview

This document defines the data structures, entities, and relationships for the
Spec-to-Ship CLI tool. All data is file-based (Markdown, Bash config, JSON
logs).

---

## Core Entities

### 1. Configuration

**File**: `.workflow/config.sh` **Format**: Bash sourceable

| Field                            | Type    | Default       | Description                                            |
| -------------------------------- | ------- | ------------- | ------------------------------------------------------ |
| `MODEL_CLARIFY`                  | string  | `"opus"`      | Claude model for clarify phase                         |
| `MODEL_SPECS`                    | string  | `"sonnet"`    | Claude model for specs generation                      |
| `MODEL_ARCH`                     | string  | `"opus"`      | Claude model for architecture                          |
| `MODEL_PLAN`                     | string  | `"opus"`      | Claude model for planning                              |
| `MODEL_BUILD_PRIMARY`            | string  | `"opus"`      | Claude model for build loop main agent                 |
| `MODEL_BUILD_SUBAGENT_SEARCH`    | string  | `"sonnet"`    | Claude model for search subagents                      |
| `MODEL_BUILD_SUBAGENT_IMPLEMENT` | string  | `"sonnet"`    | Claude model for implementation subagents              |
| `MODEL_BUILD_SUBAGENT_DEBUG`     | string  | `"opus"`      | Claude model for debug subagents                       |
| `MODEL_BUILD_SUBAGENT_TRIVIAL`   | string  | `"haiku"`     | Claude model for trivial subagents                     |
| `MODEL_GATE`                     | string  | `"sonnet"`    | Claude model for gate validation                       |
| `MODEL_FEEDBACK`                 | string  | `"opus"`      | Claude model for feedback loop                         |
| `HITL_ENABLED`                   | boolean | `false`       | Enable human-in-the-loop by default                    |
| `HITL_MODE`                      | enum    | `"milestone"` | HITL mode: `task`, `milestone`, `uncertain`, `every:N` |
| `HITL_TIMEOUT`                   | string  | `""`          | HITL timeout (empty = wait indefinitely)               |
| `BUILD_MAX_ITERATIONS`           | integer | `0`           | Max build iterations (0 = unlimited)                   |
| `BUILD_PUSH_AFTER_COMMIT`        | boolean | `true`        | Auto-push after each commit                            |
| `REQUIRE_SANDBOX_WARNING`        | boolean | `true`        | Warn about sandbox recommendation                      |

**Validation Rules**:

- Model values must be one of: `opus`, `sonnet`, `haiku`
- HITL_MODE must match pattern: `task|milestone|uncertain|every:[0-9]+`
- HITL_TIMEOUT must be empty or match pattern: `[0-9]+[smh]`
  (seconds/minutes/hours)

---

### 2. PRD (Product Requirements Document)

**File**: `docs/PRD.md` **Format**: Markdown (free-form)

| Section         | Required | Description                                |
| --------------- | -------- | ------------------------------------------ |
| Overview        | Yes      | High-level description of the product      |
| Target Users    | No       | Audience definition                        |
| Jobs to Be Done | No       | User goals and desired outcomes            |
| Activities      | No       | User workflows and tasks                   |
| Requirements    | No       | Functional and non-functional requirements |

**State Transitions**:

```
[raw] --clarify--> [structured]
```

---

### 3. Structured PRD

**File**: `docs/PRD_STRUCTURED.md` **Format**: Markdown (templated)

| Section             | Required | Description                    |
| ------------------- | -------- | ------------------------------ |
| Audience            | Yes      | Defined user personas          |
| JTBDs               | Yes      | Jobs-to-be-done per audience   |
| Activities          | Yes      | Activities per JTBD            |
| Acceptance Criteria | Yes      | Testable criteria per activity |

**Relationships**:

- Generated FROM: `docs/PRD.md`
- Consumed BY: `workflow specs`

---

### 4. Spec File

**File**: `specs/{activity-slug}.md` **Format**: Markdown (templated)

| Field               | Type   | Required | Description                      |
| ------------------- | ------ | -------- | -------------------------------- |
| Activity Name       | string | Yes      | Kebab-case identifier            |
| Description         | string | Yes      | What this activity accomplishes  |
| User Journey        | string | Yes      | Context in user workflow         |
| Capability Depths   | array  | No       | Basic → Enhanced progression     |
| Acceptance Criteria | array  | Yes      | Testable criteria                |
| Dependencies        | array  | No       | List of dependent spec filenames |

**Validation Rules**:

- Filename must be kebab-case
- Must have at least one acceptance criterion
- Dependencies must reference existing spec files

**Relationships**:

- Generated FROM: `docs/PRD_STRUCTURED.md`
- Referenced BY: `docs/ARCHITECTURE.md`, `docs/IMPLEMENTATION_PLAN.md`

---

### 5. Architecture Document

**File**: `docs/ARCHITECTURE.md` **Format**: Markdown (templated)

| Section             | Required | Description                                      |
| ------------------- | -------- | ------------------------------------------------ |
| Component Map       | Yes      | System components and responsibilities           |
| Interface Contracts | Yes      | Types, API signatures                            |
| Data Models         | Yes      | Shared schemas                                   |
| Conventions         | Yes      | Naming, error handling, patterns (with examples) |
| Non-Functional      | No       | Performance, security requirements               |

**Relationships**:

- Generated FROM: `specs/*.md`
- Consumed BY: `workflow plan`, `workflow build`

---

### 6. Implementation Plan

**File**: `docs/IMPLEMENTATION_PLAN.md` **Format**: Markdown with embedded state
markers

| Section                 | Required | Description                          |
| ----------------------- | -------- | ------------------------------------ |
| Milestones              | Yes      | SLC slices with scope and acceptance |
| Tasks                   | Yes      | Ordered task list per milestone      |
| Test Requirements       | Yes      | Derived tests per task               |
| Integration Checkpoints | Yes      | Validation points                    |

**Task Schema**:

| Field     | Type   | Description                                           |
| --------- | ------ | ----------------------------------------------------- |
| id        | string | Unique identifier (e.g., `T1.1`)                      |
| title     | string | Task description                                      |
| status    | enum   | `pending`, `in_progress`, `done`, `failed`, `blocked` |
| depends   | array  | List of task IDs this depends on                      |
| tests     | array  | Required test descriptions                            |
| milestone | string | Parent milestone ID (e.g., `M1`)                      |

**State Transitions**:

```
pending --> in_progress --> done
                       --> failed --> blocked (dependents)
                       --> blocked (dependencies failed/unmet)
```

**Inline Format**:

```markdown
- [ ] **Task T1.1**: Implement init command `status: pending` `depends: []`
  - Required tests: Directory creation, idempotency, --from flag
```

---

### 7. Gate Report

**File**: `docs/gates/M{n}-gate-report.md` **Format**: Markdown

| Field           | Type    | Required | Description                                |
| --------------- | ------- | -------- | ------------------------------------------ |
| milestone       | string  | Yes      | Milestone identifier                       |
| timestamp       | ISO8601 | Yes      | When gate was run                          |
| tests_passed    | integer | Yes      | Count of passing tests                     |
| tests_failed    | integer | Yes      | Count of failing tests                     |
| criteria_status | array   | Yes      | Per-criterion pass/fail                    |
| recommendation  | enum    | Yes      | `proceed`, `rework`, `update-architecture` |
| details         | string  | No       | Additional context                         |

---

### 8. HITL Log

**File**: `docs/hitl-log.md` **Format**: Append-only log

| Field         | Type    | Description                                        |
| ------------- | ------- | -------------------------------------------------- |
| timestamp     | ISO8601 | When interaction occurred                          |
| question_type | enum    | `clarification`, `decision`, `validation`, `scope` |
| question      | string  | What was asked                                     |
| response      | string  | User's answer                                      |
| action_taken  | string  | What the system did with the response              |

**Log Entry Format**:

```
## [2026-01-11T14:30:00]

**Type**: decision
**Question**: Two approaches possible: A (faster) or B (more maintainable). Preference?
**Response**: B
**Action**: Selected maintainable approach, updated task T2.3
```

---

### 9. Session Log

**File**: `.workflow/logs/{timestamp}.log` **Format**: Structured text log

| Field     | Type    | Description                                       |
| --------- | ------- | ------------------------------------------------- |
| timestamp | ISO8601 | When event occurred                               |
| level     | enum    | `DEBUG`, `INFO`, `WARN`, `ERROR`                  |
| component | string  | Source component (e.g., `build`, `git`, `claude`) |
| message   | string  | Event description                                 |

**Line Format**:

```
[2026-01-11T14:30:00] [INFO] [build] Starting task T1.1
```

---

## Entity Relationships

```
PRD.md
    │
    ▼ (workflow clarify)
PRD_STRUCTURED.md
    │
    ▼ (workflow specs)
specs/*.md ──────────────────┐
    │                        │
    ▼ (workflow arch)        │
ARCHITECTURE.md              │
    │                        │
    ▼ (workflow plan)        │
IMPLEMENTATION_PLAN.md ◄─────┘
    │
    ▼ (workflow build)
├── Task execution
├── Session logs
├── HITL interactions
└── Git commits
    │
    ▼ (workflow gate)
Gate Reports
```

---

## File System Layout

```
project-root/
├── .workflow/
│   ├── config.sh           # Configuration entity
│   ├── logs/               # Session log entities
│   │   └── {timestamp}.log
│   └── PROMPT_*.md         # Prompt templates (not entities)
├── docs/
│   ├── PRD.md              # PRD entity
│   ├── PRD_STRUCTURED.md   # Structured PRD entity
│   ├── ARCHITECTURE.md     # Architecture entity
│   ├── IMPLEMENTATION_PLAN.md  # Plan entity
│   ├── hitl-log.md         # HITL log entity
│   └── gates/
│       └── M{n}-gate-report.md  # Gate report entities
├── specs/
│   └── {activity-slug}.md  # Spec file entities
├── src/                    # Source code (not data entities)
└── AGENTS.md               # Operational guide (generated on init)
```
