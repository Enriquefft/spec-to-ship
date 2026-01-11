# Quickstart: Spec-to-Ship Development

**Date**: 2026-01-11
**Branch**: `001-spec-to-ship-workflow`

## Prerequisites

Before starting development, ensure you have:

```bash
# Required tools
claude --version    # Claude Code CLI
git --version       # Git 2.x+
jq --version        # jq 1.6+
envsubst --version  # Part of gettext

# Optional but recommended
bats --version      # BATS testing framework
shellcheck --version # Shell script linter
```

## Project Setup

### 1. Clone and Initialize

```bash
git clone <repo-url>
cd spec-to-ship

# Make the workflow command available
chmod +x src/workflow
export PATH="$PWD/src:$PATH"

# Or create a symlink
ln -s "$PWD/src/workflow" /usr/local/bin/workflow
```

### 2. Environment Variables

```bash
# Required: Claude API access (if not configured in claude CLI)
export CLAUDE_API_KEY="your-api-key"

# Optional: Override config location
export WORKFLOW_CONFIG="/path/to/config.sh"

# Optional: Debug logging
export WORKFLOW_LOG_LEVEL="DEBUG"
```

## Development Workflow

### Running Tests

```bash
# Run all tests
bats tests/

# Run specific test file
bats tests/unit/test_common.bats

# Run with verbose output
bats --verbose-run tests/

# Run tests with timing
bats --timing tests/
```

### Linting

```bash
# Lint all shell scripts
shellcheck src/workflow src/lib/*.sh src/commands/*.sh

# Fix common issues
shellcheck -f diff src/lib/*.sh | patch -p0
```

### Manual Testing

```bash
# Test init command
mkdir /tmp/test-project && cd /tmp/test-project
workflow init --verbose

# Test with sample PRD
workflow init --from ~/sample-prd.md
workflow clarify --no-interactive
workflow specs
workflow arch
workflow plan
workflow status
```

## Key Files to Know

| File | Purpose |
|------|---------|
| `src/workflow` | Main entry point |
| `src/lib/common.sh` | Logging, error handling |
| `src/lib/claude.sh` | Claude CLI wrapper |
| `src/lib/hitl.sh` | Human-in-the-loop logic |
| `src/commands/*.sh` | Individual subcommands |
| `src/prompts/*.md` | AI prompt templates |

## Common Development Tasks

### Adding a New Subcommand

1. Create `src/commands/newcmd.sh`:
```bash
#!/usr/bin/env bash
# workflow newcmd - Description

source "${LIB_DIR}/common.sh"

cmd_newcmd() {
    local force=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done

    log_info "Running newcmd..."
    # Implementation
}
```

2. Register in `src/workflow`:
```bash
case "$cmd" in
    newcmd) source "$COMMANDS_DIR/newcmd.sh"; cmd_newcmd "$@" ;;
    # ...
esac
```

3. Add tests in `tests/unit/test_newcmd.bats`

### Modifying a Prompt Template

1. Edit `src/prompts/PROMPT_*.md`
2. Test with verbose mode: `workflow build --verbose`
3. Check session logs: `tail -f .workflow/logs/*.log`

### Debugging Build Loop

```bash
# Run single iteration with verbose
workflow build --max 1 --verbose

# Enable HITL for manual inspection
workflow build --hitl task

# Check session log
cat .workflow/logs/$(ls -t .workflow/logs/ | head -1)
```

## Testing Strategy

### Unit Tests (`tests/unit/`)

Test individual library functions in isolation:

```bash
# tests/unit/test_common.bats
@test "log_info writes to stderr" {
    run log_info "test message"
    [[ "$status" -eq 0 ]]
    [[ "$output" =~ "[INFO]" ]]
}
```

### Integration Tests (`tests/integration/`)

Test command flows with fixtures:

```bash
# tests/integration/test_init.bats
setup() {
    TEST_DIR="$(mktemp -d)"
    cd "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "init creates directory structure" {
    run workflow init
    [[ "$status" -eq 0 ]]
    [[ -d ".workflow" ]]
    [[ -d "docs" ]]
    [[ -d "specs" ]]
}
```

### Fixtures (`tests/fixtures/`)

Sample data for testing:
- `sample_prd.md` - Example PRD for clarify tests
- `sample_spec.md` - Example spec for plan tests
- `sample_plan.md` - Example plan for build tests

## Debugging Tips

### Enable Verbose Logging

```bash
workflow build --verbose 2>&1 | tee debug.log
```

### Inspect Claude Interactions

```bash
# Check what prompts are being sent
cat .workflow/logs/*.log | grep "\[claude\]"
```

### Test HITL Without Timeout

```bash
# Interactive mode for testing prompts
workflow build --hitl task --hitl-timeout 0
```

### Reset to Clean State

```bash
# Undo uncommitted changes
git reset --hard HEAD

# Regenerate plan from scratch
workflow plan --regen
```

## Code Style

- Use `shellcheck` for all scripts
- Source libraries, don't execute directly
- Use `local` for function variables
- Quote all variable expansions
- Use `[[ ]]` for conditionals
- Use `$(command)` not backticks
- Exit with meaningful codes (0, 1, 2)

## Getting Help

```bash
workflow --help
workflow <subcommand> --help

# Check status anytime
workflow status
```
