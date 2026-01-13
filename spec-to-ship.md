# Spec-to-Ship: Automated Development Workflow

## Overview

Spec-to-Ship is a CLI tool that orchestrates the complete software development
lifecycle from PRD to deployed code. It combines structured specification-driven
development with autonomous AI execution loops (Ralph pattern) to deliver
working software through well-defined phases.

## Target Users

- Solo developers or small teams building projects spanning 1 week to 2 months
- Users comfortable with CLI tools and AI-assisted development
- Projects using Claude Code as the primary AI coding agent

## Jobs to Be Done

### JTBD 1: Transform vague requirements into actionable specifications

**Desired Outcome:** User provides a rough PRD and receives structured,
clarified requirements with explicit acceptance criteria, broken into discrete
specs per activity/topic.

### JTBD 2: Establish architectural guardrails before implementation

**Desired Outcome:** User has a generated architecture document defining
component boundaries, interface contracts, and conventions that all specs
reference as source of truth.

### JTBD 3: Generate and manage implementation plans

**Desired Outcome:** User has a prioritized, milestone-based task plan with
dependencies, derived test requirements, and integration checkpoints—regenerable
when stale.

### JTBD 4: Execute autonomous implementation with safety rails

**Desired Outcome:** User can run unattended build loops that implement one task
per iteration, validate via backpressure (tests/types/lint), commit, and
continue until milestone complete.

### JTBD 5: Validate milestone completion before proceeding

**Desired Outcome:** User has explicit gates that verify integration, run
acceptance criteria checks, and surface whether to proceed, rework, or update
upstream docs.

### JTBD 6: Maintain human oversight without blocking automation

**Desired Outcome:** User can optionally enable interactive checkpoints where
the system pauses, presents progress/decisions, asks clarifying questions, and
incorporates feedback before continuing.

---

## Activities

### Activity 1: Initialize Project

**Description:** Bootstrap a new project with the Spec-to-Ship file structure
and configuration.

**Steps:**

1. Create `.workflow/` directory with prompt templates
2. Create `docs/`, `specs/`, `src/`, `src/lib/` directories
3. Generate starter `AGENTS.md` with project-specific commands
4. Create `.workflow/config.sh` with default settings
5. Optionally copy existing PRD to `docs/PRD.md`

**Acceptance Criteria:**

- Running `workflow init` in empty directory creates complete structure
- Running `workflow init` in existing project adds missing pieces without
  overwriting
- `workflow init --from <prd-file>` copies PRD to correct location
- All prompt templates are valid and reference correct paths
- Config file includes default model selection and HITL settings

---

### Activity 2: Clarify PRD

**Description:** Transform a rough PRD into a structured document with audience,
JTBDs, activities, and acceptance criteria.

**Model Selection:** Opus (complex reasoning for gap identification)

**Steps:**

1. Read `docs/PRD.md`
2. Run interactive clarification session (LLM asks questions via
   AskUserQuestionTool pattern)
3. Generate `docs/PRD_STRUCTURED.md` with:
   - Audience definition
   - JTBDs per audience
   - Activities per JTBD
   - Acceptance criteria per activity

**Acceptance Criteria:**

- Handles PRDs of varying quality (vague to detailed)
- Interactive mode asks targeted questions, max 10 rounds
- Non-interactive mode (`--no-interactive`) makes best-effort transformation
- Output follows consistent markdown structure
- Preserves original PRD unchanged

---

### Activity 3: Generate Specs

**Description:** Create individual spec files from the structured PRD, one per
activity/topic.

**Model Selection:** Sonnet (pattern-following transformation)

**Steps:**

1. Read `docs/PRD_STRUCTURED.md`
2. For each activity, generate `specs/{activity-slug}.md` containing:
   - Activity description
   - User journey context
   - Capability depths (basic → enhanced)
   - Acceptance criteria
   - Dependencies on other specs

**Acceptance Criteria:**

- One spec file per activity (not per JTBD)
- Spec filenames are kebab-case slugs
- Specs reference each other by filename for dependencies
- Specs include acceptance criteria copied from structured PRD
- Running twice overwrites existing specs (with `--force`) or skips (default)

---

### Activity 4: Generate Architecture

**Description:** Create system architecture document from specs defining shared
contracts.

**Model Selection:** Opus (architectural decisions, trade-off analysis)

**Steps:**

1. Read all `specs/*.md`
2. Analyze for common patterns, shared data, integration points
3. Generate `docs/ARCHITECTURE.md` containing:
   - Component map (what exists, responsibilities)
   - Interface contracts (types, API signatures)
   - Data models (shared schemas)
   - Conventions (naming, error handling, patterns)
   - Non-functional requirements (performance, security)

**Acceptance Criteria:**

- Architecture references specs by filename
- Contracts are specific enough to validate against (not vague)
- Conventions section includes code examples
- Running `workflow arch --review` opens interactive refinement
- Architecture changes trigger warning to re-run planning

---

### Activity 5: Generate Plan

**Description:** Create implementation plan with milestones, ordered tasks, and
test requirements.

**Model Selection:** Opus (dependency analysis, prioritization, SLC slice
design)

**Steps:**

1. Read `specs/*`, `docs/ARCHITECTURE.md`, scan `src/*`
2. Perform gap analysis (what specs say vs what code does)
3. Group tasks into milestones (SLC slices)
4. Order tasks within milestones by dependency
5. Derive test requirements from acceptance criteria
6. Generate `docs/IMPLEMENTATION_PLAN.md` containing:
   - Milestone definitions (scope, goal, acceptance)
   - Task list per milestone (ordered, with dependencies)
   - Test requirements per task
   - Integration checkpoint definitions

**Acceptance Criteria:**

- Plan reflects current code state (not stale)
- Milestones are coherent SLC slices (Simple, Lovable, Complete)
- Tasks include "Required tests:" derived from acceptance criteria
- Dependencies are explicit (`depends: [task-id]`)
- `workflow plan --regen` regenerates from scratch
- `workflow plan --milestone M1` scopes to single milestone

---

### Activity 6: Execute Build Loop

**Description:** Run autonomous Ralph-style loop that implements tasks from
plan.

**Model Selection:**

- Main agent: Opus (task selection, prioritization, coordination)
- Subagents (search/read): Sonnet (bulk parallel operations)
- Subagents (implement): Sonnet (code generation)
- Subagents (debug/architect): Opus (complex reasoning when stuck)
- Subagents (trivial): Haiku (status updates, simple reads)

**Steps:**

1. Read `AGENTS.md`, `docs/IMPLEMENTATION_PLAN.md`, `docs/ARCHITECTURE.md`
2. Select highest-priority incomplete task
3. Search codebase before implementing (don't assume not implemented)
4. Implement using subagents (model selection per task complexity)
5. Run backpressure (tests, typecheck, lint per `AGENTS.md`)
6. If HITL enabled: pause for review before commit
7. Update `docs/IMPLEMENTATION_PLAN.md` (mark done, note discoveries)
8. Commit with descriptive message
9. Push to current branch
10. Loop continues (fresh context each iteration)

**Acceptance Criteria:**

- Each iteration completes exactly one task
- Backpressure failure blocks commit (loop retries fix)
- Plan updates persist between iterations
- `--max N` limits iterations
- `--milestone M1` filters to milestone tasks only
- `--hitl` enables human-in-the-loop mode
- Ctrl+C cleanly exits loop
- Exit codes: 0 (complete), 1 (error), 2 (max iterations reached)

---

### Activity 7: Human-in-the-Loop Checkpoints

**Description:** Optional interactive checkpoints during autonomous execution
for human oversight and guidance.

**Model Selection:** Opus (synthesizing progress, formulating clarifying
questions)

**Modes:**

1. **Per-task review (`--hitl task`)**
   - Pause after each task implementation, before commit
   - Present: what was done, files changed, test results
   - Ask: "Approve commit? [y/n/edit/skip]"
   - Allow inline feedback that feeds into next iteration

2. **Per-milestone review (`--hitl milestone`)** [default when `--hitl`
   specified]
   - Pause after all tasks in milestone complete
   - Present: milestone summary, all changes, integration status
   - Ask: "Proceed to next milestone? [y/n/rework/replan]"

3. **On-uncertainty review (`--hitl uncertain`)**
   - Continue autonomously unless agent is uncertain
   - Agent self-identifies uncertainty (ambiguous spec, multiple valid
     approaches, unexpected state)
   - Pause and ask clarifying question
   - Resume with user's guidance incorporated

4. **Scheduled review (`--hitl every:N`)**
   - Pause every N iterations regardless of task boundaries
   - Present: progress summary, current trajectory
   - Ask: "Continue? Any adjustments?"

**Interactive Question Types:**

- **Clarification:** "The spec says X but I found Y in code. Which is correct?"
- **Decision:** "Two approaches possible: A (faster) or B (more maintainable).
  Preference?"
- **Validation:** "This implementation differs from spec in [way]. Intentional?"
- **Scope:** "Discovered related issue Z. Address now or add to plan for later?"

**Acceptance Criteria:**

- `--hitl` flag activates human-in-the-loop (defaults to `milestone` mode)
- `--hitl task|milestone|uncertain|every:N` selects specific mode
- Questions are concise and actionable (not walls of text)
- User can respond with short answers (y/n) or detailed guidance
- Timeout option: `--hitl-timeout 5m` auto-continues if no response
- All interactions logged to `docs/hitl-log.md`
- `--no-hitl` explicitly disables (fully autonomous)
- HITL mode works with all other flags (`--max`, `--milestone`, etc.)

---

### Activity 8: Validate Milestone Gate

**Description:** Run integration validation after milestone tasks complete.

**Model Selection:** Sonnet (test execution, criteria checking)

**Steps:**

1. Read milestone definition from plan
2. Run full test suite
3. Check acceptance criteria (automated where possible)
4. Generate gate report with:
   - Tests passed/failed
   - Acceptance criteria status
   - Recommendation: proceed / rework / update-architecture

**Acceptance Criteria:**

- Gate runs automatically when milestone tasks marked complete (optional)
- `workflow gate` runs manually
- Gate failure blocks `workflow build` from starting next milestone
- Report saved to `docs/gates/M{n}-gate-report.md`
- `--force` proceeds despite gate failure (with warning)

---

### Activity 9: Update Feedback Loop

**Description:** Propagate learnings from implementation back to upstream docs.

**Model Selection:** Opus (analyzing drift, proposing updates)

**Steps:**

1. After milestone gate passes
2. Check if architecture contracts evolved during implementation
3. Check if spec acceptance criteria need clarification
4. Prompt user to approve updates or skip
5. Update `docs/ARCHITECTURE.md` and/or `specs/*.md`

**Acceptance Criteria:**

- Never auto-updates without user confirmation
- Shows diff of proposed changes
- Updates include comment noting "Updated after M{n}"
- Skipped updates logged for future reference

---

## Technical Requirements

### CLI Framework

- Bash scripts (POSIX-compatible where possible)
- Single entry point: `workflow` command
- Subcommands: `init`, `clarify`, `specs`, `arch`, `plan`, `build`, `gate`,
  `status`, `diff`

### Dependencies

- `claude` CLI (Claude Code)
- `git`
- `jq` (JSON processing)
- `envsubst` (template substitution)

### Configuration File (`.workflow/config.sh`)

```bash
# Model selection per phase
MODEL_CLARIFY="opus"
MODEL_SPECS="sonnet"
MODEL_ARCH="opus"
MODEL_PLAN="opus"
MODEL_BUILD_PRIMARY="opus"
MODEL_BUILD_SUBAGENT_SEARCH="sonnet"
MODEL_BUILD_SUBAGENT_IMPLEMENT="sonnet"
MODEL_BUILD_SUBAGENT_DEBUG="opus"
MODEL_BUILD_SUBAGENT_TRIVIAL="haiku"
MODEL_GATE="sonnet"
MODEL_FEEDBACK="opus"

# Human-in-the-loop defaults
HITL_ENABLED=false
HITL_MODE="milestone"  # task|milestone|uncertain|every:N
HITL_TIMEOUT=""        # empty = wait indefinitely

# Build loop defaults
BUILD_MAX_ITERATIONS=0  # 0 = unlimited
BUILD_PUSH_AFTER_COMMIT=true

# Safety
REQUIRE_SANDBOX_WARNING=true
```

### File Locations

- Prompts: `.workflow/PROMPT_*.md`
- Config: `.workflow/config.sh`
- Docs: `docs/`
- Specs: `specs/`
- Source: `src/` with `src/lib/` for shared utilities
- Operational guide: `AGENTS.md` (project root)
- HITL log: `docs/hitl-log.md`
- Gate reports: `docs/gates/`

### Claude Code Integration

- Use `-p` flag for headless operation
- Use `--dangerously-skip-permissions` for autonomous loops
- Use `--output-format=stream-json` for structured logging
- Use `--model <model>` dynamically based on config and phase
- Subagent model selection via prompt instructions

### Model Selection Automation

The workflow automatically selects models based on phase:

```bash
# In loop.sh (pseudocode)
case "$PHASE" in
  clarify)  MODEL="$MODEL_CLARIFY" ;;
  specs)    MODEL="$MODEL_SPECS" ;;
  arch)     MODEL="$MODEL_ARCH" ;;
  plan)     MODEL="$MODEL_PLAN" ;;
  build)    MODEL="$MODEL_BUILD_PRIMARY" ;;
  gate)     MODEL="$MODEL_GATE" ;;
  feedback) MODEL="$MODEL_FEEDBACK" ;;
esac

claude --model "$MODEL" -p ...
```

Subagent model selection is embedded in prompt templates:

```markdown
# PROMPT_build.md

Use up to 500 parallel ${MODEL_BUILD_SUBAGENT_SEARCH} subagents for searches...
Use ${MODEL_BUILD_SUBAGENT_DEBUG} subagents when complex reasoning is needed...
Use ${MODEL_BUILD_SUBAGENT_TRIVIAL} subagents for status updates...
```

### Human-in-the-Loop Mechanics

**Detection (for `--hitl uncertain` mode):**

Prompt includes instruction for self-identified uncertainty:

```markdown
# In PROMPT_build.md when HITL_MODE=uncertain

If you encounter any of these situations, STOP and ask for human input:

- Spec is ambiguous or contradictory
- Multiple valid implementation approaches exist
- Existing code contradicts spec
- Test failure cause is unclear
- Security/data implications need confirmation

To ask, output: `[HITL_QUESTION]: Your question here` Then STOP and wait for
response in next iteration.
```

**Interaction Flow:**

```
┌─────────────────────────────────────────┐
│ Build Loop Iteration                    │
├─────────────────────────────────────────┤
│ 1. Execute task                         │
│ 2. Check HITL trigger:                  │
│    - task mode: always trigger          │
│    - milestone: trigger if milestone    │
│    - uncertain: trigger if [HITL_Q]     │
│    - every:N: trigger if iteration % N  │
│ 3. If triggered:                        │
│    a. Display context + question        │
│    b. Wait for input (or timeout)       │
│    c. Log interaction                   │
│    d. Incorporate response              │
│ 4. Continue or exit based on response   │
└─────────────────────────────────────────┘
```

**Response Handling:**

| Response            | Action                                         |
| ------------------- | ---------------------------------------------- |
| `y` / `yes` / Enter | Approve and continue                           |
| `n` / `no`          | Reject, rollback task, re-attempt              |
| `s` / `skip`        | Skip task, mark for later, continue            |
| `e` / `edit`        | Open $EDITOR for manual changes, then continue |
| `r` / `replan`      | Regenerate plan, restart milestone             |
| `q` / `quit`        | Clean exit                                     |
| Free-form text      | Incorporate as guidance for next iteration     |

### Loop Mechanics

- Outer loop: bash `while` loop feeding prompt to claude
- Inner loop: single task execution within claude session
- Context reset: each iteration starts fresh (no conversation history)
- State persistence: via files on disk (`IMPLEMENTATION_PLAN.md`, `hitl-log.md`)

### Safety

- Recommend sandboxed execution (Docker, E2B)
- Document security implications of `--dangerously-skip-permissions`
- Provide `git reset --hard` escape hatch instructions
- Plan regeneration as recovery mechanism
- HITL mode as safety net for high-stakes changes

---

## Non-Functional Requirements

### Performance

- `workflow init` completes in <5 seconds
- `workflow clarify` interactive session <10 minutes typical
- `workflow plan` completes in 1-3 loop iterations
- `workflow build` single iteration <15 minutes typical
- HITL prompts appear within 5 seconds of trigger

### Reliability

- Idempotent operations where possible
- Clear error messages with recovery suggestions
- Graceful handling of Claude API rate limits
- Resume capability after interruption
- HITL log enables replay/audit of decisions

### Usability

- `workflow status` shows current phase and progress
- `workflow --help` documents all commands
- Prompt templates are human-readable and editable
- Minimal configuration required for basic usage
- HITL questions are concise (<100 words) with clear options

---

## CLI Reference

```bash
# Initialize
workflow init [--from <prd-file>]

# Requirements phase
workflow clarify [--no-interactive]
workflow specs [--force]

# Architecture phase
workflow arch [--review]

# Planning phase
workflow plan [--regen] [--milestone <M>]

# Execution phase
workflow build [--max <N>] [--milestone <M>] [--hitl [mode]] [--no-hitl]
#   --hitl modes: task, milestone (default), uncertain, every:N
#   --hitl-timeout <duration>  (e.g., 5m, 1h)

# Validation phase
workflow gate [--milestone <M>] [--force]

# Utilities
workflow status
workflow diff
workflow config [--edit]
```

---

## Out of Scope (v1)

- GUI or web interface
- Multi-agent orchestration beyond subagent spawning
- Integration with external project management tools
- Automated deployment/CI-CD integration
- Support for AI agents other than Claude Code
- Parallel milestone execution
- Cloud-based execution orchestration
