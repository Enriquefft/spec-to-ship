# Command Reference

Complete documentation for all Spec-to-Ship commands with options, examples, and usage patterns.

## Table of Contents

- [Global Options](#global-options)
- [init - Initialize Project](#init)
- [clarify - Clarify Requirements](#clarify)
- [specs - Generate Specifications](#specs)
- [arch - Generate Architecture](#arch)
- [plan - Generate Implementation Plan](#plan)
- [build - Execute Build Loop](#build)
- [gate - Milestone Validation](#gate)
- [status - Show Status](#status)
- [diff - Show Changes](#diff)
- [config - Manage Configuration](#config)

---

## Global Options

These options must appear **before** the subcommand:

```bash
workflow [GLOBAL_OPTIONS] <command> [COMMAND_OPTIONS]
```

| Option | Description |
|--------|-------------|
| `--verbose` | Enable debug output to stderr |
| `-c, --config PATH` | Use custom config file location |
| `-h, --help` | Show help message |
| `-v, --version` | Show version |

**Example:**
```bash
workflow --verbose build --max 10
workflow -c /custom/config.sh status
```

---

## init

Initialize a new project with Spec-to-Ship directory structure.

### Synopsis

```bash
workflow init [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--from FILE` | Copy existing PRD file to docs/PRD.md |
| `--force` | Overwrite existing files |
| `--help` | Show help message |

### Created Structure

```
.workflow/
  config.sh              # Default configuration
  logs/                  # Session logs directory
docs/
  PRD.md                 # PRD template
specs/                   # Specifications directory
src/
  lib/                   # Library directory
```

### Examples

```bash
# Basic initialization
workflow init

# Initialize with existing PRD
workflow init --from requirements.md
workflow init --from ~/Documents/project-brief.md

# Force reinitialize (overwrites existing files)
workflow init --force
```

### Notes

- Creates git repository if none exists
- Won't overwrite existing files unless `--force` is used
- Default PRD.md is a template with sections for you to fill

---

## clarify

Transform a rough PRD into a structured document with audiences, JTBDs (Jobs To Be Done), activities, and acceptance criteria.

### Synopsis

```bash
workflow clarify [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--no-interactive` | Skip interactive clarification loop |
| `--help` | Show help message |

### Input/Output

- **Requires:** `docs/PRD.md`
- **Creates:** `docs/PRD_STRUCTURED.md`
- **Preserves:** Original `docs/PRD.md` unchanged

### Interactive Mode (Default)

Claude asks up to 10 clarifying questions to refine requirements:
1. Analyzes your PRD
2. Identifies ambiguities
3. Asks targeted questions
4. You provide answers
5. Generates structured PRD with refined requirements

### Examples

```bash
# Interactive clarification (recommended)
workflow clarify

# Non-interactive mode (uses PRD as-is)
workflow clarify --no-interactive
```

### Output Structure

`PRD_STRUCTURED.md` includes:
- **Audiences**: Who will use this?
- **JTBDs**: What jobs are users trying to accomplish?
- **Activities**: Specific user activities grouped by JTBD
- **Acceptance Criteria**: How to validate each activity works

### Notes

- Interactive mode is recommended for best results
- Maximum 10 clarification rounds to prevent infinite loops
- Original PRD.md remains as historical reference

---

## specs

Generate one specification file per activity from the structured PRD.

### Synopsis

```bash
workflow specs [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--force` | Regenerate existing spec files |
| `--help` | Show help message |

### Input/Output

- **Requires:** `docs/PRD_STRUCTURED.md`
- **Creates:** `specs/{activity-slug}.md` (one per activity)

### Spec File Contents

Each specification includes:
- **Summary**: What this activity accomplishes
- **Dependencies**: Other specs this depends on
- **Technical Design**: Implementation approach
- **Acceptance Criteria**: Testable success conditions
- **Test Plan**: How to validate implementation

### Examples

```bash
# Generate specs (skips existing files)
workflow specs

# Regenerate all specs
workflow specs --force

# Common workflow: regenerate after PRD changes
workflow clarify
workflow specs --force
```

### Notes

- Spec filenames are kebab-case slugs of activity names
- Each spec is self-contained but tracks dependencies
- Use `--force` after major PRD changes to regenerate

---

## arch

Create a unified architecture document from all specifications.

### Synopsis

```bash
workflow arch [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--review` | Enter interactive review mode |
| `--help` | Show help message |

### Input/Output

- **Requires:** `specs/*.md` (one or more spec files)
- **Creates:** `docs/ARCHITECTURE.md`

### Architecture Contents

- **Component Map**: System components and their relationships
- **Interface Contracts**: APIs, function signatures, data flows
- **Data Models**: Schemas, types, database structures
- **Coding Conventions**: Style guide, patterns to follow
- **Non-Functional Requirements**: Performance, security, scalability

### Examples

```bash
# Generate architecture
workflow arch

# Generate with interactive refinement
workflow arch --review
```

### Interactive Review Mode

When `--review` is enabled:
1. Claude generates initial architecture
2. Presents it for your review
3. You can request changes or refinements
4. Claude updates and re-presents
5. Continue until satisfied

### Notes

- Architecture unifies all specs into cohesive design
- Serves as source of truth for implementation
- Update after significant spec changes

---

## plan

Generate a prioritized, milestone-based implementation plan with task dependencies.

### Synopsis

```bash
workflow plan [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--regen` | Regenerate from scratch |
| `--milestone NAME` | Filter to show specific milestone |
| `--help` | Show help message |

### Input/Output

- **Requires:** `specs/*.md`, `docs/ARCHITECTURE.md`
- **Creates:** `docs/IMPLEMENTATION_PLAN.md`

### Plan Structure

- **Milestones**: Grouped by SLC (Simple, Lovable, Complete) slices
- **Tasks**: Atomic work units with clear deliverables
- **Dependencies**: Explicit task ordering requirements
- **Test Requirements**: Validation criteria per task
- **State Tracking**: pending/in_progress/done/blocked

### Task States

| State | Description |
|-------|-------------|
| `pending` | Not started, dependencies may not be met |
| `in_progress` | Currently being worked on |
| `done` | Completed and validated |
| `blocked` | Cannot proceed due to unmet dependencies |

### Examples

```bash
# Generate plan
workflow plan

# Regenerate completely (discards task states)
workflow plan --regen

# View specific milestone
workflow plan --milestone M1
workflow plan --milestone M2

# Common workflow: regenerate after architecture changes
workflow arch --review
workflow plan --regen
```

### Notes

- Plan is milestone-oriented (M1, M2, M3, ...)
- Each milestone represents a deployable slice
- Tasks are topologically sorted by dependencies
- Task states are preserved unless `--regen` is used

---

## build

Run the autonomous implementation loop, executing tasks one at a time with validation.

### Synopsis

```bash
workflow build [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--max N` | Limit to N iterations (default: unlimited) |
| `--milestone NAME` | Only execute tasks for specific milestone |
| `--hitl MODE` | Enable human-in-the-loop (task\|milestone\|uncertain\|every:N) |
| `--no-hitl` | Disable HITL even if configured |
| `--hitl-timeout DURATION` | Auto-continue after timeout (e.g., "5m", "1h") |
| `--help` | Show help message |

### Build Loop Process

For each iteration:
1. **Select Task**: Highest-priority incomplete task with met dependencies
2. **Execute**: Search codebase, implement changes, write tests
3. **Validate**: Run tests, lint, typecheck (if enabled)
4. **Commit**: Atomic git commit with descriptive message
5. **Update**: Mark task as done in plan
6. **Repeat**: Continue to next task

### HITL Modes

| Mode | Behavior |
|------|----------|
| `task` | Pause after every task completion |
| `milestone` | Pause after each milestone completes |
| `uncertain` | Pause only when Claude detects ambiguity |
| `every:N` | Pause every N iterations (e.g., `every:5`) |

### Examples

```bash
# Basic autonomous build
workflow build

# Limited iterations (useful for testing)
workflow build --max 10

# Milestone-specific build
workflow build --milestone M1
workflow build --milestone M2

# With human oversight
workflow build --hitl task              # Pause after each task
workflow build --hitl milestone          # Pause after milestones
workflow build --hitl uncertain          # Pause when unsure
workflow build --hitl every:5            # Pause every 5 iterations

# With timeout (auto-continue)
workflow build --hitl milestone --hitl-timeout 5m
workflow build --hitl task --hitl-timeout 1h

# Disable HITL for this run (even if configured)
workflow build --no-hitl

# Combine options
workflow build --milestone M1 --max 15 --hitl milestone
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tasks complete |
| 1 | Error occurred |
| 2 | Max iterations reached (incomplete) |

### Validation (Backpressure)

Controlled by configuration:
- `BUILD_BACKPRESSURE_TESTS`: Run test suite after each task
- `BUILD_BACKPRESSURE_LINT`: Run linter after each task
- `BUILD_BACKPRESSURE_TYPECHECK`: Run type checker after each task

If validation fails, task is retried or marked blocked.

### Notes

- Each task gets its own atomic commit
- Commits include task ID and description
- HITL interactions logged to `docs/hitl-log.md`
- Resumes automatically from last completed task

---

## gate

Validate that a milestone is complete by checking acceptance criteria and running tests.

### Synopsis

```bash
workflow gate [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--milestone NAME` | Validate specific milestone (default: current) |
| `--force` | Proceed even if validation fails |
| `--help` | Show help message |

### Input/Output

- **Requires:** `docs/IMPLEMENTATION_PLAN.md`, all milestone tasks marked done
- **Creates:** `docs/gates/M{n}-gate-report.md`

### Validation Process

1. **Task Completion**: Verify all milestone tasks are done
2. **Test Suite**: Run full test suite
3. **Acceptance Criteria**: Check each criterion from specs
4. **Generate Report**: Pass/fail status with details
5. **Recommendation**: Proceed, rework, or update architecture

### Report Contents

- Overall pass/fail status
- Test results summary
- Acceptance criteria checklist
- Issues found (if any)
- Recommendations for next steps

### Examples

```bash
# Validate current milestone
workflow gate

# Validate specific milestone
workflow gate --milestone M1
workflow gate --milestone M2

# Force proceed despite failures (not recommended)
workflow gate --force

# Typical workflow
workflow build --milestone M1
workflow gate --milestone M1
# Review docs/gates/M1-gate-report.md
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Validation passed |
| 1 | Validation failed |
| 2 | Failed but forced (with --force) |

### Recommendations

Gate reports include one of:
- **Proceed**: All checks passed, move to next milestone
- **Rework**: Fix issues before proceeding
- **Update Architecture**: Design assumptions violated, revisit architecture

### Notes

- Gate reports are permanent record of validation
- Failed gates should not be forced without careful consideration
- Use gates to maintain quality and catch issues early

---

## status

Display current workflow state including phase, milestone progress, and HITL status.

### Synopsis

```bash
workflow status [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--help` | Show help message |

### Output

```
Phase: Execution
Status: Building implementation
Milestone: M2 (5/12 tasks complete)
HITL: enabled (not waiting)
```

### Workflow Phases

| Phase | Description | Trigger |
|-------|-------------|---------|
| Requirements | Initial state | After `init` |
| Architecture | Specs being created | After `clarify` |
| Planning | Plan being generated | After `arch` |
| Execution | Implementation in progress | After `plan` |
| Complete | All milestones done | All tasks complete |

### HITL Status

- **enabled (waiting)**: HITL active, waiting for human input
- **enabled (not waiting)**: HITL active, currently executing
- **disabled**: HITL not configured

### Examples

```bash
# Show current status
workflow status

# Check status during build
workflow build --max 5 &
sleep 10
workflow status
```

### Use Cases

- Check progress during long builds
- Verify HITL state before leaving
- Understand current phase for next action

---

## diff

Show git diff of changes since the last milestone or for a specific milestone.

### Synopsis

```bash
workflow diff [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--milestone NAME` | Show changes for specific milestone |
| `--help` | Show help message |

### Behavior

**Without `--milestone`**: Shows uncommitted changes (staged + unstaged)
**With `--milestone`**: Shows all commits for that milestone

### Examples

```bash
# Show uncommitted changes
workflow diff

# Show changes for milestone M1
workflow diff --milestone M1

# Show changes for milestone M2
workflow diff --milestone M2

# Pipe to pager
workflow diff --milestone M1 | less

# Save to file
workflow diff --milestone M1 > m1-changes.patch
```

### Use Cases

- Review what `build` did before committing
- Compare milestone implementations
- Generate change summaries for documentation
- Create patches for sharing or review

### Notes

- Milestone diffs include all commits tagged for that milestone
- Uncommitted changes are useful during HITL pauses
- Use with `gate` to review before validation

---

## config

View and modify workflow configuration settings.

### Synopsis

```bash
workflow config [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--get KEY` | Get specific configuration value |
| `--set KEY=VALUE` | Set configuration value (persists to file) |
| `--edit` | Open config file in $EDITOR |
| `--help` | Show help message |

### Configuration Keys

#### Model Settings

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `MODEL_CLARIFY` | opus/sonnet/haiku | opus | Model for requirements clarification |
| `MODEL_SPECS` | opus/sonnet/haiku | sonnet | Model for spec generation |
| `MODEL_ARCH` | opus/sonnet/haiku | opus | Model for architecture |
| `MODEL_PLAN` | opus/sonnet/haiku | opus | Model for planning |
| `MODEL_BUILD_PRIMARY` | opus/sonnet/haiku | opus | Primary model for build loop |
| `MODEL_BUILD_SECONDARY` | opus/sonnet/haiku | sonnet | Fallback model for build |
| `MODEL_GATE` | opus/sonnet/haiku | opus | Model for gate validation |
| `MODEL_FEEDBACK` | opus/sonnet/haiku | sonnet | Model for feedback analysis |

#### HITL Settings

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `HITL_ENABLED` | true/false | false | Enable human-in-the-loop |
| `HITL_MODE` | task/milestone/uncertain/every:N | milestone | When to pause |
| `HITL_TIMEOUT` | duration (e.g., "5m") | "" | Auto-continue timeout |

#### Build Settings

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `BUILD_MAX_ITERATIONS` | integer | 0 | Iteration limit (0=unlimited) |
| `BUILD_BACKPRESSURE_TESTS` | true/false | true | Run tests after each task |
| `BUILD_BACKPRESSURE_LINT` | true/false | true | Run linter after each task |
| `BUILD_BACKPRESSURE_TYPECHECK` | true/false | true | Run type checker after each task |

#### Retry Settings

| Key | Values | Default | Description |
|-----|--------|---------|-------------|
| `RETRY_MAX_ATTEMPTS` | integer | 3 | Max retries on failure |
| `RETRY_BASE_DELAY` | integer (seconds) | 2 | Base delay between retries |

### Examples

```bash
# View all configuration
workflow config

# Get specific values
workflow config --get MODEL_BUILD_PRIMARY
workflow config --get HITL_ENABLED

# Set values (persists to .workflow/config.sh)
workflow config --set MODEL_BUILD_PRIMARY=sonnet
workflow config --set HITL_ENABLED=true
workflow config --set HITL_MODE=milestone
workflow config --set BUILD_MAX_ITERATIONS=50

# Disable backpressure checks
workflow config --set BUILD_BACKPRESSURE_TYPECHECK=false
workflow config --set BUILD_BACKPRESSURE_LINT=false

# Edit interactively
workflow config --edit
```

### Common Configurations

#### Fast Iteration

```bash
workflow config --set MODEL_BUILD_PRIMARY=sonnet
workflow config --set BUILD_BACKPRESSURE_TYPECHECK=false
workflow config --set BUILD_BACKPRESSURE_LINT=false
```

#### Maximum Quality

```bash
workflow config --set MODEL_BUILD_PRIMARY=opus
workflow config --set HITL_ENABLED=true
workflow config --set HITL_MODE=task
workflow config --set BUILD_BACKPRESSURE_TESTS=true
```

#### Balanced (Recommended)

```bash
workflow config --set MODEL_BUILD_PRIMARY=opus
workflow config --set HITL_ENABLED=true
workflow config --set HITL_MODE=milestone
workflow config --set BUILD_MAX_ITERATIONS=100
```

### Notes

- Configuration is stored in `.workflow/config.sh`
- Changes persist across sessions
- Can override with environment variables: `WORKFLOW_MODEL_BUILD_PRIMARY=sonnet workflow build`
- Invalid values are rejected with error message

---

## See Also

- [Main README](../README.md) - Overview and quick start
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
