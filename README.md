# Spec-to-Ship

Transform product requirements into working software through AI-orchestrated,
specification-driven development.

**Philosophy**: Write a PRD, get deployable code. Each phase generates artifacts
that feed the next—requirements → specs → architecture → plan →
implementation—with human oversight when you want it.

Inspired by [spec-kit](https://github.com/github/spec-kit) and
[ralph-claude-code](https://github.com/frankbria/ralph-claude-code).

## Quick Start

```bash
# Install
git clone <repository-url> && cd spec-to-ship
export PATH="$PWD/src:$PATH"

# Initialize project
mkdir my-project && cd my-project && git init
workflow init

# Edit docs/PRD.md with your requirements, then:
workflow clarify    # Refine requirements interactively
workflow constitution # Define the project non-negotiables
workflow specs      # Generate feature specifications
workflow arch       # Create architecture document
workflow plan       # Generate implementation plan
workflow build      # Execute autonomous build loop
```

## Prerequisites

| Tool                                                     | Version | Install                                        |
| -------------------------------------------------------- | ------- | ---------------------------------------------- |
| Bash                                                     | 4.0+    | System                                         |
| Git                                                      | 2.0+    | System                                         |
| [Claude Code](https://github.com/anthropics/claude-code) | Latest  | See link                                       |
| jq                                                       | 1.6+    | `brew install jq` / `apt install jq`           |
| envsubst                                                 | Any     | `brew install gettext` / `apt install gettext` |

## Commands

| Command    | Purpose                         |
| ---------- | ------------------------------- |
| `init`     | Initialize project structure    |
| `clarify`  | Refine PRD interactively        |
| `specs`    | Generate feature specifications |
| `arch`     | Create architecture document    |
| `plan`     | Generate implementation plan    |
| `build`    | Execute autonomous build loop   |
| `gate`     | Validate milestone completion   |
| `status`   | Show workflow state             |
| `explore`  | Analyze existing codebase       |
| `ci`       | CI/CD integration commands      |
| `provider` | Manage AI providers             |
| `config`   | Manage configuration            |

See [docs/COMMANDS.md](docs/COMMANDS.md) for full reference.

## Key Features

### Multi-Provider Support

Use different AI providers per phase:

```bash
workflow provider list              # Show available providers
workflow config set PROVIDER_DEFAULT opencode
workflow build --provider claude    # Override for one run
```

### Human-in-the-Loop (HITL)

Control when to pause for review:

```bash
workflow build --hitl task          # Pause after every task
workflow build --hitl milestone     # Pause after milestones
workflow build --hitl every:5       # Pause every 5 iterations
```

### Brownfield Projects

Work with existing codebases:

```bash
workflow explore --depth deep       # Analyze existing code
workflow init --brownfield          # Initialize with protection
```

### CI/CD Integration

Integrate with your pipeline:

```bash
workflow ci validate                # Run quality gates
workflow ci report json             # JSON for CI systems
workflow ci hooks install           # Git hooks
```

### Quality Gates

Block builds on violations:

```bash
workflow ci gate constitution       # Check project constitution
workflow ci gate checklist          # Check feature checklist
```

### Build Resume

Interrupted builds resume automatically:

```bash
workflow build                      # Prompts to resume if interrupted
```

## Configuration

```bash
workflow config                     # View all settings
workflow config set KEY=VALUE       # Set a value
```

Key settings:

- `PROVIDER_DEFAULT` - AI provider (claude, opencode, gemini, copilot)
- `HITL_ENABLED` / `HITL_MODE` - Human oversight
- `BUILD_MAX_ITERATIONS` - Iteration limit

## Project Structure

```
.workflow/           # State, config, logs, audit trails
docs/                # PRD, architecture, implementation plan
specs/               # Feature specifications
src/                 # Your source code
```

## Workflow Phases

```
PRD → clarify → specs → arch → plan → build → gate
         ↓         ↓       ↓       ↓        ↓
   Structured   Specs  Arch.md  Plan.md   Code
      PRD       *.md
```

## Documentation

- **[Command Reference](docs/COMMANDS.md)** - All commands and options
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions
- **[AI Providers](docs/AI_PROVIDER_MODEL_MAPPING.md)** - Provider configuration

## Development

```bash
bats tests/                         # Run tests
shellcheck src/**/*.sh              # Lint scripts
```

## License

`LICENSE`
