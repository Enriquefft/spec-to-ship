# Implementation Plan: Spec-to-Ship Automated Development Workflow

**Branch**: `001-spec-to-ship-workflow` | **Date**: 2026-01-11 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-spec-to-ship-workflow/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Build a CLI tool (`workflow`) that orchestrates the complete software development lifecycle from PRD to deployed code. The tool uses POSIX-compatible Bash scripts with Claude Code CLI for AI-powered processing, implementing a specification-driven workflow with 10 subcommands (init, clarify, specs, arch, plan, build, gate, status, diff, config), autonomous build loops with backpressure validation, and optional human-in-the-loop checkpoints.

## Technical Context

**Language/Version**: Bash (POSIX-compatible) with shellcheck compliance
**Primary Dependencies**: Claude Code CLI, git, jq, envsubst
**Storage**: File-based (Markdown documents, JSON/YAML config, session logs)
**Testing**: BATS (Bash Automated Testing System) for shell scripts
**Target Platform**: Linux/macOS terminals (POSIX-compatible systems)
**Project Type**: Single CLI application
**Performance Goals**: Init <5s, clarify session <10min, build iteration <15min, HITL prompt <5s
**Constraints**: No external databases, secrets via environment variables only, atomic git operations
**Scale/Scope**: Solo developers or small teams (1-3 people), projects 1 week to 2 months

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

> Note: Project constitution (`constitution.md`) contains template placeholders. Using default software engineering principles for gate evaluation.

| Gate | Status | Evidence |
|------|--------|----------|
| Self-contained & testable | PASS | Single CLI with BATS testing, no external service dependencies |
| CLI interface (text in/out) | PASS | All subcommands use stdin/args → stdout, errors → stderr |
| Test-first approach | PASS | spec.md defines acceptance scenarios for all 9 user stories |
| Observability | PASS | FR-024/FR-025 mandate session logs + verbose flag |
| Simplicity (YAGNI) | PASS | Out-of-scope explicitly excludes GUI, multi-agent, CI/CD integration |
| Security basics | PASS | FR-026/FR-027 mandate env vars for secrets, no secrets in logs |

**Pre-Phase 0 Result**: All gates PASS. No violations require justification.

## Project Structure

### Documentation (this feature)

```text
specs/001-spec-to-ship-workflow/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
src/
├── workflow             # Main entry point script
├── lib/
│   ├── common.sh        # Shared utilities (logging, error handling, colors)
│   ├── config.sh        # Configuration loading and validation
│   ├── git.sh           # Git operations (atomic commits, branch management)
│   ├── claude.sh        # Claude CLI wrapper (model selection, retry logic)
│   └── hitl.sh          # Human-in-the-loop interaction handling
├── commands/
│   ├── init.sh          # workflow init
│   ├── clarify.sh       # workflow clarify
│   ├── specs.sh         # workflow specs
│   ├── arch.sh          # workflow arch
│   ├── plan.sh          # workflow plan
│   ├── build.sh         # workflow build (main loop)
│   ├── gate.sh          # workflow gate
│   ├── status.sh        # workflow status
│   ├── diff.sh          # workflow diff
│   └── config.sh        # workflow config
└── prompts/
    ├── PROMPT_clarify.md
    ├── PROMPT_specs.md
    ├── PROMPT_arch.md
    ├── PROMPT_plan.md
    └── PROMPT_build.md

tests/
├── unit/
│   ├── test_common.bats
│   ├── test_config.bats
│   └── test_git.bats
├── integration/
│   ├── test_init.bats
│   ├── test_clarify.bats
│   ├── test_build_loop.bats
│   └── test_hitl.bats
└── fixtures/
    ├── sample_prd.md
    ├── sample_spec.md
    └── sample_plan.md
```

**Structure Decision**: Single CLI application using Bash scripts. Commands are modular (`src/commands/`), shared logic in libraries (`src/lib/`), prompt templates in `src/prompts/`. Tests use BATS framework with unit, integration, and fixture directories.

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No violations to justify. All gates passed.

## Post-Design Constitution Re-Check

*Re-evaluated after Phase 1 design completion.*

| Gate | Status | Evidence |
|------|--------|----------|
| Self-contained & testable | PASS | data-model.md defines file-based entities with no external deps; contracts define testable interfaces |
| CLI interface (text in/out) | PASS | cli-interface.md specifies stdin/stdout/stderr for all 10 subcommands |
| Test-first approach | PASS | quickstart.md includes BATS test patterns; library-interfaces.md defines testable function contracts |
| Observability | PASS | data-model.md defines Session Log entity; contracts specify `--verbose` flag behavior |
| Simplicity (YAGNI) | PASS | Single project structure; no abstractions beyond necessary libraries |
| Security basics | PASS | data-model.md Configuration entity uses env var pattern; no secrets in file-based storage |

**Post-Phase 1 Result**: All gates PASS. Design aligns with constitution principles.

## Generated Artifacts

| Artifact | Path | Description |
|----------|------|-------------|
| Research | `specs/001-spec-to-ship-workflow/research.md` | 8 technical decisions documented |
| Data Model | `specs/001-spec-to-ship-workflow/data-model.md` | 9 entities with schemas and relationships |
| CLI Contract | `specs/001-spec-to-ship-workflow/contracts/cli-interface.md` | 10 subcommands with options and exit codes |
| Library Contracts | `specs/001-spec-to-ship-workflow/contracts/library-interfaces.md` | 5 library modules with function signatures |
| Quickstart | `specs/001-spec-to-ship-workflow/quickstart.md` | Development setup and testing guide |
| Agent Context | `CLAUDE.md` | Updated with technology stack |
