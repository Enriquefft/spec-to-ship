# Spec-to-Ship: Automated Development Workflow

A CLI tool that orchestrates the complete software development lifecycle from PRD to deployed code, using specification-driven workflows with AI-powered processing.

## Prerequisites

Before using the workflow tool, ensure you have the following installed:

### Required
- **Bash** 4.0+ (POSIX-compatible shell)
- **Git** 2.0+
- **Claude Code CLI** - [Installation guide](https://github.com/anthropics/claude-code)
- **jq** 1.6+ - JSON processor
- **envsubst** - Part of gettext package

### Optional
- **BATS** - Bash Automated Testing System (for running tests)
- **shellcheck** - Shell script linter (for development)

### Installation Commands

#### macOS (Homebrew)
```bash
brew install git jq gettext bats-core shellcheck
# Install Claude Code CLI separately
```

#### Ubuntu/Debian
```bash
sudo apt-get install git jq gettext shellcheck
# Install BATS and Claude Code CLI separately
```

#### Arch Linux
```bash
sudo pacman -S git jq gettext shellcheck bats
# Install Claude Code CLI separately
```

## Installation

### Option 1: Add to PATH
```bash
git clone <repository-url>
cd spec-to-ship
export PATH="$PWD/src:$PATH"
```

### Option 2: Create Symlink
```bash
git clone <repository-url>
cd spec-to-ship
sudo ln -s "$PWD/src/workflow" /usr/local/bin/workflow
```

## Quick Start

### 1. Initialize a New Project
```bash
# Create new project directory
mkdir my-project && cd my-project
git init

# Initialize Spec-to-Ship structure
workflow init

# Or initialize with existing PRD
workflow init --from my-prd.md
```

### 2. Run the Workflow
```bash
# Step 1: Clarify requirements (interactive)
workflow clarify

# Step 2: Generate specifications
workflow specs

# Step 3: Generate architecture
workflow arch

# Step 4: Generate implementation plan
workflow plan

# Step 5: Execute build loop
workflow build

# Step 6: Check status anytime
workflow status
```

## Usage

### Global Options

Use these options before the subcommand:

- `--verbose` - Enable debug output to stderr
- `-c, --config PATH` - Use custom config file location
- `-h, --help` - Show help message
- `-v, --version` - Show version

Example: `workflow --verbose build --max 10`

### Commands Reference

#### 1. `workflow init` - Initialize Project

Initialize a new project with Spec-to-Ship directory structure.

**Options:**
- `--from FILE` - Copy existing PRD file to docs/PRD.md
- `--force` - Overwrite existing files
- `--help` - Show help

**Examples:**
```bash
# Basic initialization
workflow init

# Initialize with existing PRD
workflow init --from requirements.md

# Force reinitialize (overwrites existing files)
workflow init --force
```

**Creates:**
- `.workflow/` - Configuration and logs
- `docs/` - Documentation directory
- `specs/` - Specifications directory
- `src/`, `src/lib/` - Source code directories
- `.workflow/config.sh` - Default configuration
- `docs/PRD.md` - PRD template

---

#### 2. `workflow clarify` - Clarify Requirements

Transform a rough PRD into a structured document with audiences, JTBDs, activities, and acceptance criteria.

**Options:**
- `--no-interactive` - Skip interactive clarification loop
- `--help` - Show help

**Examples:**
```bash
# Interactive clarification (default)
workflow clarify

# Non-interactive mode (uses PRD as-is)
workflow clarify --no-interactive
```

**Requires:** `docs/PRD.md`
**Creates:** `docs/PRD_STRUCTURED.md`

**Interactive Mode:**
- Claude asks clarifying questions (max 10 rounds)
- You provide answers to refine requirements
- Original PRD.md remains unchanged

---

#### 3. `workflow specs` - Generate Specifications

Generate one specification file per activity from the structured PRD.

**Options:**
- `--force` - Regenerate existing spec files
- `--help` - Show help

**Examples:**
```bash
# Generate specs (skips existing)
workflow specs

# Regenerate all specs
workflow specs --force
```

**Requires:** `docs/PRD_STRUCTURED.md`
**Creates:** `specs/{activity-slug}.md` (one per activity)

**Spec files include:**
- Summary and dependencies
- Technical design
- Acceptance criteria
- Test plan

---

#### 4. `workflow arch` - Generate Architecture

Create a unified architecture document from all specifications.

**Options:**
- `--review` - Enter interactive review mode
- `--help` - Show help

**Examples:**
```bash
# Generate architecture
workflow arch

# Generate with interactive refinement
workflow arch --review
```

**Requires:** `specs/*.md` (one or more spec files)
**Creates:** `docs/ARCHITECTURE.md`

**Architecture includes:**
- Component map
- Interface contracts
- Data models
- Coding conventions
- Non-functional requirements

---

#### 5. `workflow plan` - Generate Implementation Plan

Generate a prioritized, milestone-based implementation plan with task dependencies.

**Options:**
- `--regen` - Regenerate from scratch
- `--milestone NAME` - Filter specific milestone
- `--help` - Show help

**Examples:**
```bash
# Generate plan
workflow plan

# Regenerate completely
workflow plan --regen

# Show specific milestone
workflow plan --milestone M1
```

**Requires:**
- `specs/*.md`
- `docs/ARCHITECTURE.md`

**Creates:** `docs/IMPLEMENTATION_PLAN.md`

**Plan includes:**
- Milestone-based SLC slices
- Ordered tasks with dependencies
- Test requirements per task
- Task state tracking (pending/in_progress/done/blocked)

---

#### 6. `workflow build` - Execute Build Loop

Run the autonomous implementation loop, executing tasks one at a time with validation.

**Options:**
- `--max N` - Limit to N iterations (default: unlimited)
- `--milestone NAME` - Only execute tasks for specific milestone
- `--hitl MODE` - Enable human-in-the-loop (task|milestone|uncertain|every:N)
- `--no-hitl` - Disable HITL even if configured
- `--hitl-timeout DURATION` - Auto-continue after timeout (e.g., "5m", "1h")
- `--help` - Show help

**Examples:**
```bash
# Basic autonomous build
workflow build

# Limited iterations
workflow build --max 10

# Milestone-specific build
workflow build --milestone M1

# With human oversight (pause after each task)
workflow build --hitl task

# Pause after milestones
workflow build --hitl milestone

# Pause every 5 iterations
workflow build --hitl every:5

# With timeout (auto-continue after 5 minutes)
workflow build --hitl milestone --hitl-timeout 5m

# Disable HITL for this run
workflow build --no-hitl
```

**Requires:** `docs/IMPLEMENTATION_PLAN.md`
**Updates:** Task states in plan, creates commits

**Build loop:**
1. Select highest-priority incomplete task
2. Execute task (search codebase, implement, test)
3. Validate (run tests, lint, typecheck)
4. Commit changes atomically
5. Update plan status
6. Repeat

**Exit codes:**
- 0: All tasks complete
- 1: Error occurred
- 2: Max iterations reached

---

#### 7. `workflow gate` - Milestone Validation

Validate that a milestone is complete by checking acceptance criteria and running tests.

**Options:**
- `--milestone NAME` - Validate specific milestone (default: current)
- `--force` - Proceed even if validation fails
- `--help` - Show help

**Examples:**
```bash
# Validate current milestone
workflow gate

# Validate specific milestone
workflow gate --milestone M1

# Validate and proceed despite failures (not recommended)
workflow gate --force
```

**Requires:**
- `docs/IMPLEMENTATION_PLAN.md`
- All milestone tasks marked as done

**Creates:** `docs/gates/M{n}-gate-report.md`

**Validation includes:**
- Running full test suite
- Checking acceptance criteria
- Generating pass/fail report
- Recommendations (proceed/rework/update-architecture)

**Exit codes:**
- 0: Validation passed
- 1: Validation failed
- 2: Failed but forced (with --force)

---

#### 8. `workflow status` - Show Status

Display current workflow state including phase, milestone progress, and HITL status.

**Options:**
- `--help` - Show help

**Examples:**
```bash
# Show current status
workflow status
```

**Output includes:**
- Current phase (Requirements/Architecture/Planning/Execution/Complete)
- Status description
- Current milestone with task completion (N/M tasks)
- HITL status (enabled/disabled, waiting/not waiting)

**Example output:**
```
Phase: Execution
Status: Building implementation
Milestone: M2 (5/12 tasks complete)
HITL: enabled (not waiting)
```

---

#### 9. `workflow diff` - Show Changes

Show git diff of changes since the last milestone or for a specific milestone.

**Options:**
- `--milestone NAME` - Show changes for specific milestone
- `--help` - Show help

**Examples:**
```bash
# Show uncommitted changes
workflow diff

# Show changes for milestone M1
workflow diff --milestone M1
```

**Shows:**
- Staged and unstaged changes (default)
- All commits for a milestone (with --milestone)

---

#### 10. `workflow config` - Manage Configuration

View and modify workflow configuration settings.

**Options:**
- `--get KEY` - Get specific configuration value
- `--set KEY=VALUE` - Set configuration value (persists to file)
- `--edit` - Open config file in $EDITOR
- `--help` - Show help

**Examples:**
```bash
# Show all configuration
workflow config

# Get specific value
workflow config --get MODEL_BUILD_PRIMARY

# Set a value
workflow config --set MODEL_BUILD_PRIMARY=sonnet
workflow config --set HITL_ENABLED=true
workflow config --set HITL_MODE=milestone

# Edit configuration interactively
workflow config --edit
```

**Configuration keys:**
- **Model Settings:** `MODEL_CLARIFY`, `MODEL_SPECS`, `MODEL_ARCH`, `MODEL_PLAN`, `MODEL_BUILD_PRIMARY`, `MODEL_BUILD_SECONDARY`, `MODEL_GATE`, `MODEL_FEEDBACK`
- **HITL Settings:** `HITL_ENABLED`, `HITL_MODE`, `HITL_TIMEOUT`
- **Build Settings:** `BUILD_MAX_ITERATIONS`, `BUILD_BACKPRESSURE_TESTS`, `BUILD_BACKPRESSURE_TYPECHECK`, `BUILD_BACKPRESSURE_LINT`
- **Retry Settings:** `RETRY_MAX_ATTEMPTS`, `RETRY_BASE_DELAY`

**Valid values:**
- Models: `opus`, `sonnet`, `haiku`
- HITL modes: `task`, `milestone`, `uncertain`, `every:N`
- Booleans: `true`, `false`
- Integers: positive numbers

---

### Common Workflows

#### Complete End-to-End

```bash
# 1. Initialize
workflow init

# 2. Edit docs/PRD.md with your requirements

# 3. Run full workflow
workflow clarify
workflow specs
workflow arch
workflow plan
workflow build

# 4. Validate milestones
workflow gate --milestone M1
workflow gate --milestone M2

# 5. Check status anytime
workflow status
```

#### Iterative Development with HITL

```bash
# Initial setup
workflow init
# Edit docs/PRD.md
workflow clarify
workflow specs
workflow arch
workflow plan

# Build with oversight
workflow build --hitl milestone --max 10

# After each milestone:
workflow gate
workflow status
workflow diff --milestone M1

# Continue next milestone
workflow build --hitl milestone --max 10
```

#### Configuration Tuning

```bash
# Use faster models for iteration
workflow config --set MODEL_BUILD_PRIMARY=sonnet

# Enable HITL for uncertain situations only
workflow config --set HITL_ENABLED=true
workflow config --set HITL_MODE=uncertain

# Disable typecheck if not applicable
workflow config --set BUILD_BACKPRESSURE_TYPECHECK=false
```

## Configuration

Configuration is stored in `.workflow/config.sh`. Key settings:

```bash
# Model selection for each phase
MODEL_CLARIFY="opus"
MODEL_SPECS="sonnet"
MODEL_ARCH="opus"
MODEL_PLAN="opus"
MODEL_BUILD_PRIMARY="opus"

# HITL settings
HITL_ENABLED="false"
HITL_MODE="milestone"  # task, milestone, uncertain, every:N
HITL_TIMEOUT=""        # e.g., "5m", "1h"

# Build settings
BUILD_MAX_ITERATIONS="0"  # 0 = unlimited
BUILD_BACKPRESSURE_TESTS="true"
BUILD_BACKPRESSURE_LINT="true"
```

## Project Structure

```
.workflow/          # Workflow state and configuration
  config.sh         # Configuration file
  logs/             # Session logs
docs/               # Documentation
  PRD.md            # Product Requirements Document
  PRD_STRUCTURED.md # Structured PRD (after clarify)
  ARCHITECTURE.md   # Architecture document
  IMPLEMENTATION_PLAN.md  # Implementation plan
  gates/            # Milestone gate reports
  hitl-log.md       # Human-in-the-loop interaction log
specs/              # Feature specifications
  {feature-slug}.md # Individual spec files
src/                # Your source code
```

## Environment Variables

### Required (if not configured in Claude CLI)
- `CLAUDE_API_KEY` - Claude API authentication key

### Optional
- `WORKFLOW_CONFIG` - Override config file location
- `WORKFLOW_LOG_LEVEL` - Set log verbosity (DEBUG, INFO, WARN, ERROR)
- `WORKFLOW_*` - Override any config.sh setting (e.g., `WORKFLOW_MODEL_CLARIFY=opus`)

## Development

### Running Tests
```bash
# Run all tests
bats tests/

# Run specific test suite
bats tests/unit/test_common.bats
bats tests/integration/test_init.bats

# Verbose output
bats --verbose-run tests/
```

### Linting
```bash
# Lint all shell scripts
shellcheck src/workflow src/lib/*.sh src/commands/*.sh

# Auto-fix common issues
shellcheck -f diff src/lib/*.sh | patch -p0
```

## Troubleshooting

### Enable Verbose Logging
```bash
workflow build --verbose 2>&1 | tee debug.log
```

### Check Session Logs
```bash
# View latest session log
tail -f .workflow/logs/*.log

# View all logs
ls -lt .workflow/logs/
```

### Verify Configuration
```bash
workflow config
```

### Reset to Clean State
```bash
# Undo uncommitted changes
git reset --hard HEAD

# Regenerate plan
workflow plan --regen
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidelines.

## License

[Add your license here]

## Support

For issues and questions:
- GitHub Issues: [repository-url/issues]
- Documentation: [link to docs]
