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

### Available Commands

- `workflow init` - Initialize project structure
- `workflow clarify` - Transform rough PRD into structured format
- `workflow specs` - Generate spec files from structured PRD
- `workflow arch` - Generate architecture document
- `workflow plan` - Generate implementation plan
- `workflow build` - Execute autonomous build loop
- `workflow gate` - Run milestone validation
- `workflow status` - Show current workflow state
- `workflow diff` - Show changes since last milestone
- `workflow config` - Manage configuration

### Global Options

- `--verbose` - Enable debug output
- `--config PATH` - Use custom config file
- `--help` - Show help message
- `--version` - Show version

### Examples

#### Basic Workflow
```bash
workflow init
workflow clarify
workflow specs
workflow arch
workflow plan
workflow build
```

#### With Human-in-the-Loop
```bash
# Pause after each milestone
workflow build --hitl milestone

# Pause after uncertain decisions
workflow build --hitl uncertain

# Pause every 5 iterations
workflow build --hitl every:5
```

#### Limited Build Iterations
```bash
# Run maximum 10 build iterations
workflow build --max 10
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
