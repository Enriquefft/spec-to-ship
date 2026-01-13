# Tasks: Spec-to-Ship Automated Development Workflow

**Input**: Design documents from `/specs/001-spec-to-ship-workflow/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: BATS tests included per quickstart.md guidance

**Organization**: Tasks grouped by user story (9 total) for independent
implementation

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1-US9)
- File paths from plan.md structure

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize project structure for Bash CLI application

- [x] T001 Create directory structure: src/, src/lib/, src/commands/,
      src/prompts/, tests/unit/, tests/integration/, tests/fixtures/
- [x] T002 [P] Create main entry point script at src/workflow with shebang and
      permissions
- [x] T003 [P] Create README.md with prerequisites and installation instructions
- [x] T004 [P] Create .gitignore for .workflow/logs/, temp files, and OS
      artifacts

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core library infrastructure required by ALL user stories

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [x] T005 [P] Implement logging functions (log_debug, log_info, log_warn,
      log_error, die) in src/lib/common.sh per library-interfaces.md
- [x] T006 [P] Implement utility functions (require_command, require_file,
      ensure_dir) in src/lib/common.sh per library-interfaces.md
- [x] T007 [P] Implement config loading (config_load, config_get, config_set,
      config_validate, config_model_for_phase) in src/lib/config.sh per
      library-interfaces.md
- [x] T008 [P] Implement git operations (git_is_repo, git_root, git_branch,
      git_is_clean, git_atomic_commit, git_push, git_reset_staged) in
      src/lib/git.sh per library-interfaces.md
- [x] T009 [P] Implement Claude CLI wrapper (claude_invoke,
      claude_invoke_with_input, claude_stream) in src/lib/claude.sh per
      library-interfaces.md with retry logic and exponential backoff
- [x] T010 [P] Implement HITL functions (hitl_is_enabled, hitl_mode,
      hitl_should_pause, hitl_prompt, hitl_prompt_yn, hitl_log) in
      src/lib/hitl.sh per library-interfaces.md
- [x] T011 [P] Implement plan manipulation functions (plan_load,
      plan_get_next_task, plan_get_task_status, plan_set_task_status,
      plan_get_task_deps, plan_deps_satisfied, plan_milestone_complete) in
      src/lib/plan.sh per library-interfaces.md
- [x] T012 Update src/workflow to source all libraries and implement subcommand
      routing per cli-interface.md

**Checkpoint**: Foundation ready - user story implementation can now begin in
parallel

---

## Phase 3: User Story 1 - Initialize Project Structure (Priority: P1) 🎯 MVP

**Goal**: Enable users to bootstrap a new project with Spec-to-Ship workflow
structure

**Independent Test**: Run `workflow init` in empty directory and verify all
directories/files created per acceptance scenario 1

### Tests for User Story 1

- [x] T013 [P] [US1] Create BATS unit test for directory creation in
      tests/unit/test_init.bats
- [x] T014 [P] [US1] Create BATS integration test for init command in
      tests/integration/test_init.bats covering all 3 acceptance scenarios

### Implementation for User Story 1

- [x] T015 [US1] Implement workflow init command in src/commands/init.sh: create
      .workflow/, docs/, specs/, src/, src/lib/ directories per FR-003
- [x] T016 [US1] Add --from flag handling to copy PRD file to docs/PRD.md per
      acceptance scenario 3
- [x] T017 [US1] Implement idempotency check to preserve existing files unless
      --force specified per FR-004
- [x] T018 [US1] Generate default .workflow/config.sh with all MODEL*\* and
      HITL*\* defaults from data-model.md Configuration entity
- [x] T019 [US1] Generate AGENTS.md operational guide template in project root
- [x] T020 [US1] Create prompt template files: src/prompts/PROMPT_clarify.md,
      PROMPT_specs.md, PROMPT_arch.md, PROMPT_plan.md, PROMPT_build.md with
      placeholder content
- [x] T021 [US1] Add error handling for permission denied and invalid paths per
      cli-interface.md exit codes

**Checkpoint**: User Story 1 complete - `workflow init` functional and testable
independently

---

## Phase 4: User Story 2 - Clarify Requirements (Priority: P1)

**Goal**: Transform rough PRD into structured document with audiences, JTBDs,
activities, and acceptance criteria

**Independent Test**: Provide sample PRD in tests/fixtures/sample_prd.md, run
`workflow clarify`, verify docs/PRD_STRUCTURED.md contains structured sections
per acceptance scenario 1

### Tests for User Story 2

- [x] T022 [P] [US2] Create BATS integration test for clarify command in
      tests/integration/test_clarify.bats covering interactive and
      --no-interactive modes

### Implementation for User Story 2

- [x] T023 [US2] Implement workflow clarify command in src/commands/clarify.sh
      with --no-interactive flag support per FR-005
- [x] T024 [US2] Load PROMPT_clarify.md and invoke Claude via claude_invoke with
      model from config (MODEL_CLARIFY) per research.md Decision 4
- [x] T025 [US2] Implement interactive question loop (max 10 rounds per FR-006)
      using hitl_prompt for user responses
- [x] T026 [US2] Parse Claude output and generate docs/PRD_STRUCTURED.md with
      Audience, JTBDs, Activities, Acceptance Criteria sections per
      data-model.md Structured PRD entity
- [x] T027 [US2] Verify original docs/PRD.md remains unchanged per acceptance
      scenario 4
- [x] T028 [US2] Add error handling for missing PRD and Claude API failures per
      cli-interface.md exit codes

**Checkpoint**: User Story 2 complete - `workflow clarify` functional and
testable independently

---

## Phase 5: User Story 3 - Generate Individual Specs (Priority: P1)

**Goal**: Generate one spec file per activity from structured PRD to enable
parallel development

**Independent Test**: Create docs/PRD_STRUCTURED.md with 3 activities in
tests/fixtures/, run `workflow specs`, verify 3 kebab-case .md files in specs/
per acceptance scenario 1

### Tests for User Story 3

- [x] T029 [P] [US3] Create BATS integration test for specs command in
      tests/integration/test_specs.bats covering creation, skip, and --force
      modes

### Implementation for User Story 3

- [x] T030 [US3] Implement workflow specs command in src/commands/specs.sh with
      --force flag support per FR-007
- [x] T031 [US3] Load docs/PRD_STRUCTURED.md and parse activities using grep/sed
- [x] T032 [US3] Load PROMPT_specs.md and invoke Claude for each activity via
      claude_invoke with MODEL_SPECS from config
- [x] T033 [US3] Generate kebab-case filenames (e.g.,
      specs/initialize-project.md) and write spec files per data-model.md Spec
      File entity structure
- [x] T034 [US3] Include explicit dependency references between specs using
      filenames per FR-008 and acceptance scenario 4
- [x] T035 [US3] Implement skip logic when specs exist (unless --force) per
      acceptance scenarios 2-3
- [x] T036 [US3] Add error handling for missing structured PRD per
      cli-interface.md

**Checkpoint**: User Story 3 complete - `workflow specs` functional and testable
independently

---

## Phase 6: User Story 4 - Generate Architecture Document (Priority: P2)

**Goal**: Create unified architecture document defining component boundaries,
interface contracts, data models, and conventions

**Independent Test**: Create 2-3 spec files in tests/fixtures/, run
`workflow arch`, verify docs/ARCHITECTURE.md contains component map, interfaces,
data models, conventions per acceptance scenario 1

### Tests for User Story 4

- [x] T037 [P] [US4] Create BATS integration test for arch command in
      tests/integration/test_arch.bats covering generation and --review mode

### Implementation for User Story 4

- [x] T038 [US4] Implement workflow arch command in src/commands/arch.sh with
      --review flag per FR-009
- [x] T039 [US4] Load all specs/\*.md files and analyze for common patterns,
      shared data, integration points
- [x] T040 [US4] Load PROMPT_arch.md and invoke Claude via claude_invoke with
      MODEL_ARCH from config
- [x] T041 [US4] Generate docs/ARCHITECTURE.md with sections: Component Map,
      Interface Contracts, Data Models, Conventions (with code examples),
      Non-Functional Requirements per data-model.md Architecture Document entity
- [x] T042 [US4] Implement interactive refinement session for --review flag
      using hitl_prompt
- [x] T043 [US4] Add warning mechanism to detect architecture modifications and
      recommend plan regeneration per acceptance scenario 3
- [x] T044 [US4] Add error handling for no specs found per cli-interface.md

**Checkpoint**: User Story 4 complete - `workflow arch` functional and testable
independently

---

## Phase 7: User Story 5 - Generate Implementation Plan (Priority: P2)

**Goal**: Generate prioritized, milestone-based implementation plan with
dependencies and test requirements

**Independent Test**: Create specs/ and docs/ARCHITECTURE.md in tests/fixtures/,
run `workflow plan`, verify docs/IMPLEMENTATION_PLAN.md contains milestones,
ordered tasks, test requirements, dependencies per acceptance scenario 1

### Tests for User Story 5

- [x] T045 [P] [US5] Create BATS integration test for plan command in
      tests/integration/test_plan.bats covering generation, --regen, and
      --milestone modes

### Implementation for User Story 5

- [x] T046 [US5] Implement workflow plan command in src/commands/plan.sh with
      --regen and --milestone flags per FR-010
- [x] T047 [US5] Load specs/\*.md and docs/ARCHITECTURE.md for context
- [x] T048 [US5] Scan src/\* directory for existing code to perform gap analysis
      comparing spec requirements against current state per FR-010
- [x] T049 [US5] Load PROMPT_plan.md and invoke Claude via claude_invoke with
      MODEL_PLAN from config
- [x] T050 [US5] Generate docs/IMPLEMENTATION_PLAN.md with milestone-based SLC
      slices per FR-011 and data-model.md Implementation Plan entity
- [x] T051 [US5] Derive test requirements from acceptance criteria for each task
      per FR-012 and format as "Required tests:" lines
- [x] T052 [US5] Include explicit task dependencies using "depends:" markers and
      implement task state tracking (pending, in_progress, done, failed,
      blocked) per FR-028 and research.md Decision 5
- [x] T053 [US5] Support --regen to regenerate from scratch and --milestone to
      filter specific milestone per acceptance scenarios 2-3
- [x] T054 [US5] Add error handling for missing specs/architecture per
      cli-interface.md

**Checkpoint**: User Story 5 complete - `workflow plan` functional and testable
independently

---

## Phase 8: User Story 6 - Execute Autonomous Build Loop (Priority: P2)

**Goal**: Run autonomous implementation loop executing tasks one at a time with
backpressure validation

**Independent Test**: Create sample plan with 2 simple tasks in tests/fixtures/,
run `workflow build --max 2`, verify tasks implemented, tested, committed one at
a time per acceptance scenario 1

### Tests for User Story 6

- [x] T055 [P] [US6] Create BATS integration test for build command in
      tests/integration/test_build_loop.bats covering iteration limit, milestone
      filter, and Ctrl+C handling

### Implementation for User Story 6

- [x] T056 [US6] Implement workflow build command in src/commands/build.sh with
      --max, --milestone, --hitl, --no-hitl, --hitl-timeout flags per FR-013
- [x] T057 [US6] Load docs/IMPLEMENTATION_PLAN.md and use plan_get_next_task to
      select highest-priority incomplete task per FR-013
- [x] T058 [US6] Implement main loop using while statement that executes exactly
      one task per iteration
- [x] T059 [US6] Load PROMPT_build.md with context from plan and invoke Claude
      via claude_invoke with MODEL_BUILD_PRIMARY from config
- [x] T060 [US6] Implement task execution: search codebase before implementing,
      delegate to subagents based on complexity (use MODEL*BUILD_SUBAGENT*\*
      from config per research.md Decision 4)
- [x] T061 [US6] Implement backpressure validation: run tests, typecheck
      (shellcheck for bash), lint before allowing commit per FR-014
- [x] T062 [US6] Block commit when backpressure fails per FR-015 and retry fix
      in next iteration per acceptance scenario 2
- [x] T063 [US6] Update plan using plan_set_task_status to mark task done per
      FR-016
- [x] T064 [US6] Use git_atomic_commit to commit changes with descriptive
      message per FR-017 and research.md Decision 8
- [x] T065 [US6] Use git_push if BUILD_PUSH_AFTER_COMMIT is true per FR-017
- [x] T066 [US6] Implement Ctrl+C signal handler with trap to ensure clean exit
      and atomic git operations per FR-022 and acceptance scenario 5
- [x] T067 [US6] Support --max N to limit iterations per acceptance scenario 3
      and exit with code 2 when reached per cli-interface.md
- [x] T068 [US6] Support --milestone filter to execute only specified milestone
      tasks per acceptance scenario 4
- [x] T069 [US6] Integrate HITL checkpoints using hitl_should_pause and
      hitl_prompt when enabled per acceptance scenario 1 (integration with US7)
- [x] T070 [US6] Add error handling and return exit codes: 0 (complete), 1
      (error), 2 (max iterations) per FR-023

**Checkpoint**: User Story 6 complete - `workflow build` functional and testable
independently

---

## Phase 9: User Story 7 - Human-in-the-Loop Oversight (Priority: P3)

**Goal**: Enable oversight during autonomous execution with multiple HITL modes

**Independent Test**: Run `workflow build --hitl task` with sample plan, verify
system pauses after each task with prompt per acceptance scenario 2

### Tests for User Story 7

- [x] T071 [P] [US7] Create BATS integration test for HITL modes in
      tests/integration/test_hitl.bats covering task, milestone, uncertain,
      every:N modes

### Implementation for User Story 7

- [x] T072 [US7] Implement --hitl flag parsing in src/commands/build.sh to set
      HITL_MODE (task, milestone, uncertain, every:N) per FR-018
- [x] T073 [US7] Implement task-level HITL: pause after each task, show changes,
      prompt "Approve commit? [y/n/edit/skip]" per acceptance scenario 2
- [x] T074 [US7] Implement milestone-level HITL: pause after milestone
      completion, prompt "Proceed to next milestone? [y/n/rework/replan]" per
      acceptance scenario 1
- [x] T075 [US7] Implement uncertain HITL: detect agent uncertainty markers and
      pause with clarifying question per acceptance scenario 3
- [x] T076 [US7] Implement every:N HITL: pause every N iterations per acceptance
      scenario 4
- [x] T077 [US7] Implement response handling: y/yes (approve), n/no (rollback
      and retry), skip, edit per acceptance scenario 5
- [x] T078 [US7] Implement --hitl-timeout using read -t timeout in hitl_prompt
      per acceptance scenario 6
- [x] T079 [US7] Log all HITL interactions to docs/hitl-log.md using hitl_log
      function per FR-019 and data-model.md HITL Log entity format
- [x] T080 [US7] Add error handling for invalid HITL modes per cli-interface.md

**Checkpoint**: User Story 7 complete - `workflow build --hitl` functional and
testable independently

---

## Phase 10: User Story 8 - Validate Milestone Completion (Priority: P3)

**Goal**: Verify milestone completion with acceptance criteria validation and
gate reports

**Independent Test**: Mark all M1 tasks as done in sample plan, run
`workflow gate`, verify docs/gates/M1-gate-report.md generated with pass/fail
per acceptance scenario 1

### Tests for User Story 8

- [x] T081 [P] [US8] Create BATS integration test for gate command in
      tests/integration/test_gate.bats covering validation, blocking, and
      --force modes

### Implementation for User Story 8

- [x] T082 [US8] Implement workflow gate command in src/commands/gate.sh with
      --milestone and --force flags per FR-020
- [x] T083 [US8] Load docs/IMPLEMENTATION_PLAN.md and extract milestone
      definition with acceptance criteria
- [x] T084 [US8] Run full test suite using BATS framework per quickstart.md
- [x] T085 [US8] Check acceptance criteria (automated where possible) comparing
      actual vs expected outcomes
- [x] T086 [US8] Generate docs/gates/M{n}-gate-report.md with timestamp,
      tests_passed, tests_failed, criteria_status, recommendation
      (proceed/rework/update-architecture), details per data-model.md Gate
      Report entity
- [x] T087 [US8] Block `workflow build` for next milestone when gate fails per
      acceptance scenario 2
- [x] T088 [US8] Allow --force to proceed despite gate failure with prominent
      warning per acceptance scenario 3 and exit code 2
- [x] T089 [US8] Add error handling and return exit codes: 0 (passed), 1
      (failed), 2 (failed but --force) per cli-interface.md

**Checkpoint**: User Story 8 complete - `workflow gate` functional and testable
independently

---

## Phase 11: User Story 9 - Check Workflow Status (Priority: P3)

**Goal**: Display current workflow state including phase, milestone progress,
and HITL status

**Independent Test**: Run `workflow status` at various stages, verify output
shows correct phase, status, milestone progress per acceptance scenarios 1-3

### Tests for User Story 9

- [x] T090 [P] [US9] Create BATS integration test for status command in
      tests/integration/test_status.bats covering different workflow states

### Implementation for User Story 9

- [x] T091 [US9] Implement workflow status command in src/commands/status.sh (no
      flags required)
- [x] T092 [US9] Detect current workflow phase by checking existence of key
      files: docs/PRD.md (Requirements), docs/ARCHITECTURE.md (Architecture),
      docs/IMPLEMENTATION_PLAN.md (Planning/Execution)
- [x] T093 [US9] Parse plan file to determine current milestone and count
      completed/total tasks per cli-interface.md output format
- [x] T094 [US9] Check HITL status using hitl_is_enabled and detect if waiting
      for user input
- [x] T095 [US9] Format output as: Phase: [phase name], Status: [description],
      Milestone: [current] ([N/M] tasks complete), HITL: [enabled/disabled]
      ([waiting/not waiting]) per cli-interface.md example
- [x] T096 [US9] Add error handling and return exit code 0 per cli-interface.md

**Checkpoint**: User Story 9 complete - `workflow status` functional and
testable independently

---

## Phase 12: Remaining Subcommands (diff, config)

**Purpose**: Complete all 10 subcommands from cli-interface.md

- [x] T097 [P] Implement workflow diff command in src/commands/diff.sh with
      --milestone flag to show git diff output per cli-interface.md
- [x] T098 [P] Implement workflow config command in src/commands/config.sh with
      --edit, --get, --set flags for configuration management per
      cli-interface.md

---

## Phase 13: Polish & Cross-Cutting Concerns

**Purpose**: Final improvements affecting multiple user stories

- [x] T099 [P] Add session logging to .workflow/logs/ with timestamp-based
      filenames per FR-024 and research.md Decision 7
- [x] T100 [P] Implement --verbose flag handling in src/workflow to enable debug
      output per FR-025
- [x] T101 [P] Add environment variable validation to prevent secrets in config
      files per FR-026 and research.md Decision 3
- [x] T102 [P] Add secrets filtering in logging to never write secrets to logs
      or git per FR-027
- [x] T103 [P] Create test fixtures: tests/fixtures/sample_prd.md,
      sample_spec.md, sample_plan.md per quickstart.md
- [x] T104 [P] Add shellcheck compliance validation to all .sh files per plan.md
      Technical Context
- [x] T105 [P] Create installation script or instructions for making workflow
      command globally available
- [x] T106 Run full test suite with `bats tests/` and verify all acceptance
      scenarios pass
- [x] T107 Update README.md with usage examples for all 10 subcommands
- [x] T108 [P] Document edge case handling in README or docs/: mid-commit
      interruption, Claude rate limits, missing dependencies, subdirectory
      detection per spec.md Edge Cases

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies - start immediately
- **Foundational (Phase 2)**: Depends on Setup - BLOCKS all user stories
- **User Stories (Phase 3-11)**: All depend on Foundational completion
  - US1 (init) - no story dependencies
  - US2 (clarify) - no story dependencies
  - US3 (specs) - no story dependencies
  - US4 (arch) - no story dependencies
  - US5 (plan) - no story dependencies
  - US6 (build) - no story dependencies
  - US7 (hitl) - integrates with US6 but independently testable
  - US8 (gate) - no story dependencies
  - US9 (status) - no story dependencies
- **Remaining Subcommands (Phase 12)**: Depends on Foundational
- **Polish (Phase 13)**: Depends on all desired user stories complete

### User Story Dependencies

All 9 user stories are independently implementable after Foundational phase
completes. Each can be tested and delivered on its own.

### Within Each User Story

- Tests (if included) → Models/Libs → Services → Commands → Integration

### Parallel Opportunities

- Phase 1: All tasks except T001 can run in parallel
- Phase 2: All library implementations (T005-T011) can run in parallel
- Within each user story: Tests, multiple model files, utility functions can run
  in parallel
- Phase 12: Both subcommands can be implemented in parallel
- Phase 13: Most polish tasks can run in parallel

---

## Parallel Example: User Story 1

```bash
# Tests for US1 (parallel):
Task T013: "Create BATS unit test for directory creation"
Task T014: "Create BATS integration test for init command"

# Implementation setup (sequential after tests):
Task T015: "Implement workflow init command"
Task T016: "Add --from flag handling"
...
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (T001-T004)
2. Complete Phase 2: Foundational (T005-T012) - CRITICAL
3. Complete Phase 3: User Story 1 (T013-T021)
4. **STOP and VALIDATE**: Run `workflow init` in empty directory
5. MVP ready for demo

### Incremental Delivery (Recommended)

1. Foundation: Phases 1-2 (T001-T012)
2. **MVP**: Add US1 (T013-T021) → Test → Demo
3. Add US2 (T022-T028) → Test → Demo
4. Add US3 (T029-T036) → Test → Demo
5. Add US4 (T037-T044) → Test → Demo
6. Add US5 (T045-T054) → Test → Demo
7. Add US6 (T055-T070) → Test → Demo
8. Add US7 (T071-T080) → Test → Demo
9. Add US8 (T081-T089) → Test → Demo
10. Add US9 (T090-T096) → Test → Demo
11. Complete remaining (T097-T098)
12. Polish (T099-T108)

### Parallel Team Strategy

With multiple developers after Foundational phase:

- Developer A: US1, US2, US3
- Developer B: US4, US5, US6
- Developer C: US7, US8, US9
- All: Polish tasks

---

## Task Summary

- **Total Tasks**: 108
- **Phase 1 (Setup)**: 4 tasks
- **Phase 2 (Foundational)**: 8 tasks (BLOCKS all user stories)
- **Phase 3 (US1)**: 9 tasks (7 implementation + 2 tests)
- **Phase 4 (US2)**: 7 tasks (6 implementation + 1 test)
- **Phase 5 (US3)**: 8 tasks (7 implementation + 1 test)
- **Phase 6 (US4)**: 8 tasks (7 implementation + 1 test)
- **Phase 7 (US5)**: 10 tasks (9 implementation + 1 test)
- **Phase 8 (US6)**: 16 tasks (15 implementation + 1 test)
- **Phase 9 (US7)**: 10 tasks (9 implementation + 1 test)
- **Phase 10 (US8)**: 9 tasks (8 implementation + 1 test)
- **Phase 11 (US9)**: 7 tasks (6 implementation + 1 test)
- **Phase 12 (Remaining)**: 2 tasks
- **Phase 13 (Polish)**: 10 tasks

**Parallel Opportunities**: 35+ tasks marked [P] can run in parallel within
their phases

**Independent Test Criteria**: Each user story phase includes "Checkpoint"
validation that story works independently

**Suggested MVP Scope**: Phases 1-3 (T001-T021) = Foundational + User Story 1
(workflow init)

**Format Validation**: ✅ All tasks follow checklist format with checkbox, ID,
[P]/[Story] labels, and file paths
