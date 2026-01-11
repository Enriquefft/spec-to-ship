# Feature Specification: Spec-to-Ship Automated Development Workflow

**Feature Branch**: `001-spec-to-ship-workflow`
**Created**: 2026-01-11
**Status**: Draft
**Input**: User description: "Spec-to-Ship: Automated Development Workflow CLI tool that orchestrates the complete software development lifecycle from PRD to deployed code"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Initialize Project Structure (Priority: P1)

A solo developer wants to bootstrap a new project with Spec-to-Ship workflow structure so they can begin the specification-driven development process.

**Why this priority**: Without project initialization, no other workflow activities can occur. This is the entry point for all users.

**Independent Test**: Can be fully tested by running `workflow init` in an empty directory and verifying all expected files/directories are created.

**Acceptance Scenarios**:

1. **Given** an empty directory, **When** user runs `workflow init`, **Then** the system creates `.workflow/` directory with prompt templates, `docs/`, `specs/`, `src/`, `src/lib/` directories, `AGENTS.md` file, and `.workflow/config.sh` with defaults
2. **Given** an existing project with some files, **When** user runs `workflow init`, **Then** the system adds missing pieces without overwriting existing files
3. **Given** a PRD file at `~/my-prd.md`, **When** user runs `workflow init --from ~/my-prd.md`, **Then** the system initializes structure and copies PRD to `docs/PRD.md`

---

### User Story 2 - Clarify Requirements (Priority: P1)

A developer has a rough PRD and wants to transform it into a structured document with clear audiences, jobs-to-be-done, activities, and acceptance criteria.

**Why this priority**: Without clarified requirements, specifications cannot be generated properly. This transforms vague ideas into actionable items.

**Independent Test**: Can be fully tested by providing a rough PRD and verifying the output contains structured audiences, JTBDs, activities, and acceptance criteria.

**Acceptance Scenarios**:

1. **Given** a rough PRD in `docs/PRD.md`, **When** user runs `workflow clarify`, **Then** the system conducts an interactive clarification session (max 10 rounds) and generates `docs/PRD_STRUCTURED.md`
2. **Given** a rough PRD, **When** user runs `workflow clarify --no-interactive`, **Then** the system performs best-effort transformation without asking questions
3. **Given** a very detailed PRD, **When** user runs `workflow clarify`, **Then** the system asks fewer questions and completes faster
4. **Given** the clarification process completes, **When** user checks `docs/PRD.md`, **Then** the original PRD remains unchanged

---

### User Story 3 - Generate Individual Specs (Priority: P1)

A developer has a structured PRD and wants to generate individual specification files for each activity/topic to enable parallel development.

**Why this priority**: Individual specs are the foundation for architecture and planning phases. They enable focused, testable work units.

**Independent Test**: Can be fully tested by running specs generation on a structured PRD and verifying one spec file per activity exists with correct content.

**Acceptance Scenarios**:

1. **Given** `docs/PRD_STRUCTURED.md` exists with 5 activities, **When** user runs `workflow specs`, **Then** the system creates 5 spec files in `specs/` with kebab-case filenames
2. **Given** specs already exist, **When** user runs `workflow specs`, **Then** existing specs are skipped (not overwritten)
3. **Given** specs already exist, **When** user runs `workflow specs --force`, **Then** existing specs are overwritten with fresh content
4. **Given** activities have dependencies, **When** specs are generated, **Then** each spec references dependencies by filename

---

### User Story 4 - Generate Architecture Document (Priority: P2)

A developer has individual specs and wants to create a unified architecture document that defines component boundaries, interface contracts, and conventions.

**Why this priority**: Architecture provides guardrails for implementation. Without it, different specs may produce incompatible implementations.

**Independent Test**: Can be fully tested by generating architecture from specs and verifying it contains component map, interface contracts, data models, and conventions.

**Acceptance Scenarios**:

1. **Given** multiple spec files in `specs/`, **When** user runs `workflow arch`, **Then** the system generates `docs/ARCHITECTURE.md` with component map, interface contracts, data models, and conventions
2. **Given** architecture was generated, **When** user runs `workflow arch --review`, **Then** an interactive refinement session opens
3. **Given** architecture is modified, **When** user runs any subsequent workflow command, **Then** a warning appears recommending plan regeneration

---

### User Story 5 - Generate Implementation Plan (Priority: P2)

A developer has specs and architecture and wants to generate a prioritized, milestone-based implementation plan with dependencies.

**Why this priority**: The plan organizes work into achievable milestones with clear ordering, enabling autonomous execution.

**Independent Test**: Can be fully tested by generating a plan from specs/architecture and verifying it contains milestones, ordered tasks, test requirements, and dependencies.

**Acceptance Scenarios**:

1. **Given** specs and architecture exist, **When** user runs `workflow plan`, **Then** the system scans current code, performs gap analysis, and generates `docs/IMPLEMENTATION_PLAN.md`
2. **Given** a plan exists, **When** user runs `workflow plan --regen`, **Then** the plan is regenerated from scratch
3. **Given** a plan exists with 3 milestones, **When** user runs `workflow plan --milestone M1`, **Then** only milestone M1 tasks are shown/updated
4. **Given** the plan is generated, **When** user reviews it, **Then** each task includes "Required tests:" derived from acceptance criteria

---

### User Story 6 - Execute Autonomous Build Loop (Priority: P2)

A developer wants to run an autonomous implementation loop that executes tasks from the plan one at a time with proper validation.

**Why this priority**: This is the core value proposition - autonomous implementation with safety rails that delivers working code.

**Independent Test**: Can be fully tested by running `workflow build` on a plan with simple tasks and verifying tasks are implemented, tested, and committed one at a time.

**Acceptance Scenarios**:

1. **Given** a valid implementation plan, **When** user runs `workflow build`, **Then** the system executes tasks one at a time: implement, run backpressure (tests/typecheck/lint), update plan, commit, push
2. **Given** `workflow build` is running, **When** backpressure fails (test failure), **Then** the commit is blocked and the loop retries the fix
3. **Given** a long-running build, **When** user runs `workflow build --max 5`, **Then** the loop stops after 5 iterations
4. **Given** a plan with milestone M2 tasks, **When** user runs `workflow build --milestone M2`, **Then** only M2 tasks are executed
5. **Given** `workflow build` is running, **When** user presses Ctrl+C, **Then** the loop exits cleanly without corrupted state

---

### User Story 7 - Human-in-the-Loop Oversight (Priority: P3)

A developer wants to maintain oversight during autonomous execution without blocking automation entirely.

**Why this priority**: Provides safety net for high-stakes changes and allows course correction, but autonomous execution works without it.

**Independent Test**: Can be fully tested by running `workflow build --hitl` and verifying the system pauses at appropriate checkpoints with clear prompts.

**Acceptance Scenarios**:

1. **Given** `--hitl` is specified, **When** milestone completes, **Then** the system pauses and asks "Proceed to next milestone? [y/n/rework/replan]"
2. **Given** `--hitl task` is specified, **When** each task completes, **Then** the system pauses showing changes and asks "Approve commit? [y/n/edit/skip]"
3. **Given** `--hitl uncertain` is specified, **When** the agent encounters ambiguity, **Then** the system pauses with a clarifying question
4. **Given** `--hitl every:3` is specified, **When** every 3rd iteration completes, **Then** the system pauses for review
5. **Given** user responds "n" at a checkpoint, **When** processing continues, **Then** the task is rolled back and re-attempted
6. **Given** `--hitl-timeout 5m` is set, **When** no user response within 5 minutes, **Then** the system auto-continues

---

### User Story 8 - Validate Milestone Completion (Priority: P3)

A developer wants to verify that a milestone is truly complete before proceeding to the next phase.

**Why this priority**: Gates ensure quality before proceeding, but manual verification can substitute.

**Independent Test**: Can be fully tested by completing a milestone and running `workflow gate` to verify acceptance criteria pass.

**Acceptance Scenarios**:

1. **Given** all M1 tasks are marked complete, **When** user runs `workflow gate`, **Then** the system runs tests, checks acceptance criteria, and generates `docs/gates/M1-gate-report.md`
2. **Given** gate validation fails, **When** user tries `workflow build` for next milestone, **Then** execution is blocked with recommendation to fix issues
3. **Given** gate validation fails, **When** user runs `workflow build --force`, **Then** execution proceeds with a prominent warning

---

### User Story 9 - Check Workflow Status (Priority: P3)

A developer wants to quickly see the current state of the workflow - what phase they're in and what's been completed.

**Why this priority**: Helpful for orientation but not blocking for execution.

**Independent Test**: Can be fully tested by running `workflow status` at various stages and verifying accurate state reporting.

**Acceptance Scenarios**:

1. **Given** project is initialized but no clarification done, **When** user runs `workflow status`, **Then** output shows "Phase: Requirements - Clarification pending"
2. **Given** M1 tasks complete but gate not passed, **When** user runs `workflow status`, **Then** output shows "Phase: Execution - M1 complete (gate pending)"
3. **Given** HITL is enabled and waiting, **When** user runs `workflow status`, **Then** output shows pending HITL checkpoint info

---

### Edge Cases

- What happens when `workflow build` is interrupted mid-commit? System uses atomic git operations to ensure partial commits don't occur
- How does system handle Claude API rate limits? Implements exponential backoff with user notification after 3 retries
- What happens when spec references non-existent dependency? System warns during validation and blocks build until resolved
- How does system handle conflicting acceptance criteria between specs? Architecture generation identifies conflicts and prompts resolution
- What happens when `workflow init` is run in a git repository's subdirectory? System detects git root and warns about non-standard location

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST provide a single `workflow` command as the entry point for all operations
- **FR-002**: System MUST support these subcommands: `init`, `clarify`, `specs`, `arch`, `plan`, `build`, `gate`, `status`, `diff`, `config`
- **FR-003**: System MUST create standard directory structure on `init`: `.workflow/`, `docs/`, `specs/`, `src/`, `src/lib/`
- **FR-004**: System MUST preserve existing files during `init` unless `--force` is specified
- **FR-005**: System MUST transform PRD into structured format with audience, JTBDs, activities, and acceptance criteria during `clarify`
- **FR-006**: System MUST limit interactive clarification to maximum 10 question rounds
- **FR-007**: System MUST generate one spec file per activity with kebab-case filenames
- **FR-008**: System MUST include explicit dependency references between specs using filenames
- **FR-009**: System MUST generate architecture document containing component map, interface contracts, data models, and conventions
- **FR-010**: System MUST perform gap analysis comparing specs against current code during planning
- **FR-011**: System MUST group implementation tasks into milestone-based slices (Simple, Lovable, Complete)
- **FR-012**: System MUST derive test requirements from acceptance criteria in the plan
- **FR-013**: System MUST execute exactly one task per build loop iteration
- **FR-014**: System MUST run backpressure validation (tests, typecheck, lint) before committing
- **FR-015**: System MUST block commits when backpressure fails
- **FR-016**: System MUST update implementation plan after each completed task
- **FR-017**: System MUST commit and push changes after successful task completion
- **FR-018**: System MUST support HITL modes: task, milestone, uncertain, every:N
- **FR-019**: System MUST log all HITL interactions to `docs/hitl-log.md`
- **FR-020**: System MUST generate gate reports to `docs/gates/M{n}-gate-report.md`
- **FR-021**: System MUST support model selection configuration per workflow phase
- **FR-022**: System MUST exit cleanly on Ctrl+C without corrupted state
- **FR-023**: System MUST provide clear exit codes: 0 (complete), 1 (error), 2 (max iterations reached)
- **FR-024**: System MUST append structured logs to `.workflow/logs/` per session for debugging and audit
- **FR-025**: System MUST support `--verbose` flag for real-time debug output to stderr
- **FR-026**: System MUST read secrets (API keys, credentials) from environment variables, not config files
- **FR-027**: System MUST NOT write secrets to log files or commit them to git
- **FR-028**: System MUST track task states as: `pending` → `in_progress` → `done` / `failed` / `blocked`
- **FR-029**: System MUST mark tasks `blocked` when dependencies are unmet or `failed`

### Key Entities

- **PRD (Product Requirements Document)**: Raw input document describing what the product should do, transformed into structured format
- **Structured PRD**: Organized requirements with audiences, JTBDs, activities, and acceptance criteria
- **Spec File**: Individual specification for one activity/topic with acceptance criteria and dependencies
- **Architecture Document**: System-wide contracts including component map, interfaces, data models, and conventions
- **Implementation Plan**: Milestone-organized task list with dependencies, test requirements, and integration checkpoints; tasks have states: `pending`, `in_progress`, `done`, `failed`, `blocked`
- **Gate Report**: Validation results for a completed milestone with pass/fail status and recommendations
- **HITL Log**: Chronological record of all human-in-the-loop interactions and decisions
- **Configuration**: User settings for model selection, HITL defaults, and build behavior

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can initialize a new project structure in under 5 seconds
- **SC-002**: Interactive clarification sessions complete within 10 minutes for typical PRDs
- **SC-003**: Plan generation completes in 1-3 iterations accounting for gap analysis
- **SC-004**: Single build loop iterations complete within 15 minutes for typical tasks
- **SC-005**: HITL prompts appear within 5 seconds of trigger condition
- **SC-006**: Users can recover from any interrupted state by running the same command again
- **SC-007**: 90% of autonomous build iterations successfully complete their task on first attempt
- **SC-008**: Gate reports accurately reflect milestone completion status with zero false positives
- **SC-009**: All workflow commands provide clear error messages with recovery suggestions
- **SC-010**: Users can complete an entire project lifecycle (init through gate) without documentation reference after initial onboarding

## Clarifications

### Session 2026-01-11

- Q: What observability approach should the system use? → A: File logging to `.workflow/logs/` per session plus `--verbose` flag for debug output
- Q: How should secrets (API keys, credentials) be handled? → A: Environment variables for secrets; non-sensitive settings in config files
- Q: What task states should the system track? → A: Standard states: `pending` → `in_progress` → `done` / `failed` / `blocked`

## Assumptions

- Users have Claude CLI (`claude` command) installed and configured
- Users have Git installed and repository initialized
- Users have `jq` and `envsubst` utilities available
- Projects are developed by solo developers or small teams (1-3 people)
- Project scope is 1 week to 2 months of work
- Users are comfortable with command-line interfaces
- Sandboxed execution environment (Docker, E2B) is recommended but not required for operation

## Dependencies

- Claude Code CLI for AI-powered processing
- Git for version control operations
- Bash (POSIX-compatible) for script execution
- jq for JSON processing
- envsubst for template substitution

## Scope Boundaries

### In Scope
- CLI-based workflow orchestration
- All 9 activities described (init, clarify, specs, arch, plan, build, gate, status, feedback)
- Human-in-the-loop checkpoints
- Model selection per phase
- Git integration for commits and pushes

### Out of Scope (v1)
- GUI or web interface
- Multi-agent orchestration beyond subagent spawning
- Integration with external project management tools (Jira, Linear, etc.)
- Automated deployment/CI-CD integration
- Support for AI agents other than Claude Code
- Parallel milestone execution
- Cloud-based execution orchestration
