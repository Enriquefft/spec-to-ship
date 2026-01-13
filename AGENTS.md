# Operational Guide for Spec-to-Ship Workflow

This document provides guidance for LLM agents operating within the Spec-to-Ship
workflow system.

## System Overview

Spec-to-Ship is an automated development workflow that transforms PRDs into
deployed code through a series of structured phases:

1. **Clarify** - Structure rough requirements
2. **Specs** - Generate detailed specifications
3. **Arch** - Design system architecture
4. **Plan** - Create implementation plans
5. **Build** - Execute autonomous build loops
6. **Gate** - Validate milestones

## Agent Responsibilities by Phase

### Clarify Phase (MODEL_CLARIFY)

**Model**: Opus (default) **Role**: Requirements analyst **Tasks**:

- Parse rough PRD documents
- Identify ambiguities and gaps
- Generate clarification questions (max 10 rounds)
- Structure requirements into: Audiences, JTBDs, Activities, Acceptance Criteria

**Input**: `docs/PRD.md` **Output**: `docs/PRD_STRUCTURED.md` **Prompt**:
`src/prompts/PROMPT_clarify.md`

### Specs Phase (MODEL_SPECS)

**Model**: Sonnet (default) **Role**: Technical writer **Tasks**:

- Parse structured PRD
- Generate one spec file per activity
- Include user stories, acceptance criteria, requirements
- Use kebab-case naming: `{activity-slug}.md`

**Input**: `docs/PRD_STRUCTURED.md` **Output**: `specs/{activity-slug}.md`
(multiple files) **Prompt**: `src/prompts/PROMPT_specs.md`

### Arch Phase (MODEL_ARCH)

**Model**: Opus (default) **Role**: System architect **Tasks**:

- Analyze all spec files
- Design system architecture
- Define data models, APIs, components
- Identify technical decisions and trade-offs

**Input**: All files in `specs/` **Output**: `docs/ARCHITECTURE.md` **Prompt**:
`src/prompts/PROMPT_arch.md`

### Plan Phase (MODEL_PLAN)

**Model**: Opus (default) **Role**: Engineering lead **Tasks**:

- Create implementation plan from specs + architecture
- Break down into milestones and tasks
- Define task dependencies
- Estimate complexity

**Input**: `specs/`, `docs/ARCHITECTURE.md` **Output**:
`docs/IMPLEMENTATION_PLAN.md` **Prompt**: `src/prompts/PROMPT_plan.md`

### Build Phase (MODEL_BUILD_PRIMARY, MODEL_BUILD_SECONDARY)

**Primary Model**: Opus (default) **Secondary Model**: Sonnet (default for
simple tasks) **Role**: Software engineer **Tasks**:

- Execute tasks from implementation plan
- Write code, tests, documentation
- Handle backpressure validation (tests, lint)
- Commit atomically with descriptive messages

**Input**: `docs/IMPLEMENTATION_PLAN.md` **Output**: Source code, tests,
documentation **Prompt**: `src/prompts/PROMPT_build.md`

**Build Loop Behavior**:

1. Load next pending task with satisfied dependencies
2. Execute task (primary model for complex, secondary for simple)
3. Run backpressure validation (tests, typecheck, lint)
4. Atomic commit if validation passes
5. Update task status to 'done' or 'failed'
6. Repeat until max iterations or no pending tasks

### Gate Phase (MODEL_GATE)

**Model**: Sonnet (default) **Role**: QA engineer **Tasks**:

- Run milestone validation
- Execute test suites
- Verify acceptance criteria
- Generate gate report

**Input**: Milestone tasks, codebase **Output**:
`docs/gates/M{n}-gate-report.md`

## Human-in-the-Loop (HITL) Integration

Agents must support HITL prompts at configurable checkpoints:

### HITL Modes

1. **task** - Pause after every task completion
2. **milestone** - Pause after milestone completion
3. **uncertain** - Pause when confidence is low
4. **every:N** - Pause every N iterations

### HITL API

```bash
hitl_should_pause "task|milestone|uncertain|iteration" iteration_number
hitl_prompt "Question text" "clarification|decision|validation|scope" "options"
hitl_prompt_yn "Yes/no question?"
hitl_log "question" "response" "action_taken"
```

### HITL Guidelines

- Always log interactions to `docs/hitl-log.md`
- Respect timeout settings (auto-continue if no response)
- Provide clear context in prompts
- Offer specific options when possible

## Backpressure Validation

Before any atomic commit, agents must pass backpressure checks:

### Tests (BUILD_BACKPRESSURE_TESTS=true)

- Run BATS test suites: `bats tests/`
- Must pass before commit proceeds

### Type Checking (BUILD_BACKPRESSURE_TYPECHECK)

- Run TypeScript: `tsc --noEmit`
- Run mypy for Python, etc.

### Linting (BUILD_BACKPRESSURE_LINT=true)

- Run shellcheck for Bash: `shellcheck src/**/*.sh`
- Run language-specific linters

**On Failure**: Staged changes are rolled back automatically

## Error Handling

### Recoverable Errors

- Retry with exponential backoff (3 attempts default)
- Log error details with context
- Continue with next task

### Unrecoverable Errors

- Mark task as 'failed'
- Log full error trace
- Halt build loop
- Notify user with actionable error message

## Configuration

Agents read config from `.workflow/config.sh`:

```bash
source ".workflow/config.sh"
model=$(config_model_for_phase "clarify")  # Returns "opus"
```

Override via environment:

```bash
export WORKFLOW_MODEL_CLARIFY="sonnet"
```

## Logging

All agent operations must log:

```bash
log_info "Starting clarify phase"
log_debug "Loaded PRD with 5 sections"
log_warn "Missing optional section: Timeline"
log_error "Failed to parse PRD: invalid YAML"
```

Session logs: `.workflow/logs/{timestamp}.log`

## Best Practices

1. **Read Before Write**: Always read existing files before modification
2. **Atomic Operations**: Use `git_atomic_commit` for all commits
3. **Idempotency**: Support re-running operations without side effects
4. **Clear Messages**: Commit messages should explain "why", not "what"
5. **Progressive Enhancement**: Implement core features before polish
6. **Test-First**: Write tests before implementation when possible
7. **Documentation**: Update docs alongside code changes
8. **Fail Fast**: Catch errors early, don't propagate bad state

## Security

- **NEVER** commit secrets (API keys, passwords, credentials)
- **NEVER** log secrets to files
- **ALWAYS** read secrets from environment variables
- **ALWAYS** validate user input before executing commands
- **ALWAYS** use proper quoting in shell commands

## Operational Limits

- **Clarify**: Max 10 question rounds
- **Build**: Configurable max iterations (default: unlimited)
- **HITL Timeout**: Configurable (default: no timeout)
- **Retry Attempts**: 3 (default)
- **Retry Delay**: 2s base, exponential backoff

## Agent Coordination

When multiple agents operate:

- Phases are sequential (clarify → specs → arch → plan → build)
- Build tasks can be parallel [P] if no file conflicts
- Use task dependencies to enforce ordering
- Plan library provides coordination primitives

## Success Criteria

An agent operation succeeds when:

1. All required outputs are generated
2. Outputs match specified schemas
3. Backpressure validation passes
4. No unhandled errors occurred
5. State is committed atomically

## Troubleshooting

### Agent Won't Start

- Check Claude API key: `echo $CLAUDE_API_KEY`
- Verify CLI installed: `claude --version`
- Check config file: `cat .workflow/config.sh`

### Validation Failures

- Run tests manually: `bats tests/`
- Check lint: `shellcheck src/**/*.sh`
- Review session log: `tail -f .workflow/logs/*.log`

### State Corruption

- Reset to last commit: `git reset --hard HEAD`
- Regenerate plan: `workflow plan --regen`
- Check task status: `workflow status`

---

**Last Updated**: 2026-01-11 **Version**: 1.0.0
