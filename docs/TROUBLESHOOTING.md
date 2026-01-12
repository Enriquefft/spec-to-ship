# Troubleshooting Guide

Common issues, debugging techniques, and solutions for Spec-to-Ship workflows.

## Table of Contents

- [Getting Help](#getting-help)
- [Common Errors](#common-errors)
- [Build Loop Issues](#build-loop-issues)
- [Configuration Problems](#configuration-problems)
- [Integration Issues](#integration-issues)
- [Performance & Timeout Issues](#performance--timeout-issues)
- [Debugging Techniques](#debugging-techniques)
- [Recovery Procedures](#recovery-procedures)

---

## Getting Help

### Quick Diagnostics

```bash
# Check current state
workflow status

# View recent logs
tail -50 .workflow/logs/*.log

# Verify configuration
workflow config

# Enable debug mode
workflow --verbose build 2>&1 | tee debug.log
```

### Log Locations

- **Session logs**: `.workflow/logs/workflow-YYYYMMDD-HHMMSS.log`
- **HITL interactions**: `docs/hitl-log.md`
- **Gate reports**: `docs/gates/M*-gate-report.md`

### Getting Verbose Output

```bash
# Enable for single command
workflow --verbose build --max 5

# Capture to file
workflow --verbose build 2>&1 | tee debug.log

# Set environment variable
export WORKFLOW_LOG_LEVEL=DEBUG
workflow build
```

---

## Common Errors

### "Command not found: workflow"

**Cause**: `workflow` script not in PATH

**Solutions:**

```bash
# Option 1: Add to PATH
export PATH="/path/to/spec-to-ship/src:$PATH"

# Option 2: Create symlink
sudo ln -s /path/to/spec-to-ship/src/workflow /usr/local/bin/workflow

# Option 3: Use absolute path
/path/to/spec-to-ship/src/workflow init
```

**Permanent fix**: Add to `~/.bashrc` or `~/.zshrc`:

```bash
export PATH="/path/to/spec-to-ship/src:$PATH"
```

---

### "Claude API key not found"

**Cause**: Missing or invalid `CLAUDE_API_KEY`

**Solutions:**

```bash
# Set in environment
export CLAUDE_API_KEY="sk-ant-..."

# Or configure in Claude CLI
claude-code config set api-key sk-ant-...

# Verify it's set
echo $CLAUDE_API_KEY
```

**Permanent fix**: Add to `~/.bashrc` or `~/.zshrc`:

```bash
export CLAUDE_API_KEY="sk-ant-..."
```

---

### "No such file: docs/PRD.md"

**Cause**: Missing PRD file

**Solutions:**

```bash
# Initialize creates template
workflow init

# Or copy existing PRD
workflow init --from existing-requirements.md

# Or create manually
mkdir -p docs
cat > docs/PRD.md << 'EOF'
# Product Requirements Document

## Overview
[Your project description]

## Goals
[What you're trying to achieve]

## Requirements
[Detailed requirements]
EOF
```

---

### "Git repository required"

**Cause**: Not in a git repository

**Solutions:**

```bash
# Initialize git
git init

# Or initialize with workflow (includes git init)
workflow init

# Verify
git status
```

---

### "Cannot transition from X to Y phase"

**Cause**: Skipped required workflow steps

**Example error**: `Cannot transition from Requirements to Execution`

**Solution**: Follow the correct sequence:

```bash
# Correct order
workflow clarify    # Requirements → Architecture
workflow specs      # Architecture → Architecture
workflow arch       # Architecture → Planning
workflow plan       # Planning → Execution
workflow build      # Execution phase
```

**Check current phase:**

```bash
workflow status
```

---

### "Task dependency cycle detected"

**Cause**: Circular dependencies in implementation plan

**Solutions:**

```bash
# Regenerate plan
workflow plan --regen

# If persists, review architecture
workflow arch --review

# Check dependency chain
grep -A 5 "dependencies:" docs/IMPLEMENTATION_PLAN.md
```

**Prevention**: Keep dependencies acyclic during architecture design

---

## Build Loop Issues

### Build Loop Stuck or Repeating

**Symptoms**:
- Same task attempted multiple times
- No progress after many iterations
- Infinite loop behavior

**Diagnosis:**

```bash
# Check last N iterations
tail -100 .workflow/logs/*.log | grep "Task:"

# Check task states
grep "state:" docs/IMPLEMENTATION_PLAN.md
```

**Solutions:**

```bash
# 1. Stop build and check status
workflow status

# 2. Review what's blocking
grep "blocked\|in_progress" docs/IMPLEMENTATION_PLAN.md

# 3. Reset stuck task manually
# Edit docs/IMPLEMENTATION_PLAN.md, change task state to "pending"

# 4. Resume with HITL for oversight
workflow build --hitl task --max 10
```

---

### Validation Failures After Every Task

**Symptoms**:
- Tests fail consistently
- Lint errors block progress
- Typecheck failures

**Diagnosis:**

```bash
# Check which validation is failing
tail -50 .workflow/logs/*.log | grep "FAIL\|ERROR"

# Run validations manually
npm test              # or your test command
npm run lint          # or your lint command
npm run typecheck     # or your typecheck command
```

**Solutions:**

**Tests failing:**

```bash
# Temporarily disable test backpressure
workflow config --set BUILD_BACKPRESSURE_TESTS=false

# Or fix test setup
# Check test configuration, dependencies, etc.
```

**Linting issues:**

```bash
# Disable lint backpressure
workflow config --set BUILD_BACKPRESSURE_LINT=false

# Or fix lint config
# Update .eslintrc, add ignores, etc.
```

**Type errors:**

```bash
# Disable typecheck backpressure
workflow config --set BUILD_BACKPRESSURE_TYPECHECK=false

# Or fix type configuration
# Update tsconfig.json, add type definitions, etc.
```

**Note**: Disabling validations reduces quality checks. Re-enable after fixing root causes.

---

### Tasks Marked as Blocked

**Cause**: Unmet dependencies or previous task failures

**Diagnosis:**

```bash
# Find blocked tasks
grep -B 2 "state: blocked" docs/IMPLEMENTATION_PLAN.md

# Check their dependencies
grep -A 5 "^### Task:" docs/IMPLEMENTATION_PLAN.md | grep -A 3 "blocked"
```

**Solutions:**

```bash
# 1. Complete dependency tasks first
workflow build --milestone M1  # Focus on earlier milestone

# 2. If dependency is wrong, regenerate plan
workflow plan --regen

# 3. If task should not be blocked, manually edit
# Change state from "blocked" to "pending" in docs/IMPLEMENTATION_PLAN.md

# 4. Resume
workflow build
```

---

### Build Completes But Code Doesn't Work

**Symptoms**:
- Tasks marked done but features broken
- Tests pass but functionality wrong
- Acceptance criteria not actually met

**Solutions:**

```bash
# 1. Run milestone gate
workflow gate --milestone M1

# 2. Review gate report
cat docs/gates/M1-gate-report.md

# 3. If issues found, mark tasks as pending
# Edit docs/IMPLEMENTATION_PLAN.md, change relevant tasks to "pending"

# 4. Rebuild with more oversight
workflow build --hitl task --milestone M1

# 5. Re-validate
workflow gate --milestone M1
```

**Prevention**: Use HITL modes to catch issues early

---

## Configuration Problems

### Configuration Changes Not Taking Effect

**Cause**: Environment variables or cached values

**Solutions:**

```bash
# 1. Verify configuration is saved
workflow config --get MODEL_BUILD_PRIMARY

# 2. Check for environment variable overrides
env | grep WORKFLOW_

# 3. Unset conflicting environment variables
unset WORKFLOW_MODEL_BUILD_PRIMARY

# 4. Edit directly if needed
workflow config --edit

# 5. Verify changes
workflow config
```

---

### Invalid Configuration Value

**Error**: `Invalid value for MODEL_BUILD_PRIMARY: gpt4`

**Cause**: Unsupported configuration value

**Valid values**:

- **Models**: `opus`, `sonnet`, `haiku`
- **HITL modes**: `task`, `milestone`, `uncertain`, `every:N` (e.g., `every:5`)
- **Booleans**: `true`, `false`
- **Integers**: Positive numbers only

**Solutions:**

```bash
# Fix invalid value
workflow config --set MODEL_BUILD_PRIMARY=opus

# Check valid values for a setting
workflow config --help
```

---

### Config File Corrupted

**Symptoms**: Parse errors, unexpected behavior

**Solutions:**

```bash
# 1. Backup current config
cp .workflow/config.sh .workflow/config.sh.backup

# 2. Regenerate default config
workflow init --force

# 3. Manually restore desired settings
workflow config --set MODEL_BUILD_PRIMARY=sonnet
# etc.

# Or restore from backup and fix syntax
vim .workflow/config.sh
```

---

## Integration Issues

### Claude Code CLI Not Found

**Error**: `claude-code: command not found`

**Solutions:**

```bash
# Install Claude Code CLI
# Follow: https://github.com/anthropics/claude-code

# Verify installation
claude-code --version

# Check PATH
which claude-code
```

---

### Git Commit Failures

**Error**: `Git commit failed` or `Nothing to commit`

**Causes & Solutions:**

**Not in git repository:**

```bash
git init
git add .
git commit -m "Initial commit"
```

**Git not configured:**

```bash
git config --global user.name "Your Name"
git config --global user.email "your@email.com"
```

**Working directory not clean:**

```bash
# Commit or stash changes
git status
git add .
git commit -m "Checkpoint"
```

**Permission issues:**

```bash
# Check repository permissions
ls -la .git
```

---

### jq or envsubst Missing

**Error**: `jq: command not found` or `envsubst: command not found`

**Solutions:**

```bash
# macOS
brew install jq gettext

# Ubuntu/Debian
sudo apt-get install jq gettext

# Arch Linux
sudo pacman -S jq gettext

# Verify
which jq envsubst
```

---

## Performance & Timeout Issues

### Claude API Timeouts

**Symptoms**:
- Requests timing out
- Connection errors
- Rate limit errors

**Solutions:**

```bash
# 1. Check API key validity
echo $CLAUDE_API_KEY

# 2. Retry with exponential backoff (automatic)
# Check retry settings
workflow config --get RETRY_MAX_ATTEMPTS

# 3. Increase retry attempts if needed
workflow config --set RETRY_MAX_ATTEMPTS=5

# 4. Check network connectivity
ping api.anthropic.com

# 5. Switch to smaller model temporarily
workflow config --set MODEL_BUILD_PRIMARY=sonnet
```

---

### Build Taking Too Long

**Symptoms**: Hours per milestone, slow iteration

**Solutions:**

**1. Use faster models:**

```bash
workflow config --set MODEL_BUILD_PRIMARY=sonnet
workflow config --set MODEL_SPECS=sonnet
```

**2. Reduce validation overhead:**

```bash
# Only run critical validations
workflow config --set BUILD_BACKPRESSURE_TYPECHECK=false
workflow config --set BUILD_BACKPRESSURE_LINT=false
# Keep tests: BUILD_BACKPRESSURE_TESTS=true
```

**3. Focus on specific milestone:**

```bash
workflow build --milestone M1
```

**4. Limit iterations for testing:**

```bash
workflow build --max 20
```

**5. Use HITL to catch issues early:**

```bash
workflow build --hitl every:5
```

---

### HITL Timeout Not Working

**Symptoms**: `--hitl-timeout` ignored, still waiting indefinitely

**Diagnosis:**

```bash
# Check configuration
workflow config --get HITL_TIMEOUT

# Verify format (should be like "5m", "1h")
workflow build --hitl task --hitl-timeout 5m
```

**Valid timeout formats**:
- `30s` - 30 seconds
- `5m` - 5 minutes
- `1h` - 1 hour
- `2h30m` - 2 hours 30 minutes

**Solutions:**

```bash
# Set valid format
workflow build --hitl milestone --hitl-timeout 10m

# Or configure persistently
workflow config --set HITL_TIMEOUT=5m
```

---

## Debugging Techniques

### Enable Verbose Logging

```bash
# For single command
workflow --verbose build --max 5 2>&1 | tee debug.log

# Or set environment variable
export WORKFLOW_LOG_LEVEL=DEBUG
workflow build
```

### Inspect Claude Prompts

```bash
# View session logs to see prompts sent
less .workflow/logs/workflow-*.log

# Search for specific prompts
grep -A 20 "Sending prompt:" .workflow/logs/*.log
```

### Trace Task Execution

```bash
# Follow build progress in real-time
tail -f .workflow/logs/*.log

# Filter to task transitions
tail -f .workflow/logs/*.log | grep "Task:"

# Check task state changes
watch -n 5 'grep "state:" docs/IMPLEMENTATION_PLAN.md | head -20'
```

### Validate Files Generated

```bash
# Check expected files exist
ls -la docs/
ls -la specs/

# Validate JSON structure in logs
jq . < .workflow/logs/session.json  # if applicable

# Check file contents
cat docs/IMPLEMENTATION_PLAN.md | less
```

### Test Individual Commands

```bash
# Test without full workflow
mkdir test-project && cd test-project
git init
workflow init
echo "Test PRD" > docs/PRD.md
workflow --verbose clarify --no-interactive
```

---

## Recovery Procedures

### Reset to Clean State

```bash
# WARNING: This discards uncommitted work

# 1. Reset git working directory
git reset --hard HEAD

# 2. Clean untracked files
git clean -fd

# 3. Check status
workflow status
git status
```

### Recover from Failed Build

```bash
# 1. Check what went wrong
workflow status
tail -50 .workflow/logs/*.log

# 2. Identify problematic task
grep "ERROR\|FAIL" .workflow/logs/*.log

# 3. Reset task state
# Edit docs/IMPLEMENTATION_PLAN.md
# Change task state from "in_progress" to "pending"

# 4. Resume with oversight
workflow build --hitl task --max 5
```

### Regenerate Corrupted Plan

```bash
# 1. Backup current plan
cp docs/IMPLEMENTATION_PLAN.md docs/IMPLEMENTATION_PLAN.md.backup

# 2. Regenerate from specs and architecture
workflow plan --regen

# 3. Review changes
diff docs/IMPLEMENTATION_PLAN.md.backup docs/IMPLEMENTATION_PLAN.md
```

### Recover from Architecture Changes

```bash
# 1. Update architecture
workflow arch --review

# 2. Regenerate plan to match
workflow plan --regen

# 3. Check for breaking changes
workflow diff

# 4. If needed, reset and rebuild
git reset --hard HEAD
workflow build --milestone M1
```

### Emergency Stop During Build

```bash
# Press Ctrl+C to interrupt

# Check state
workflow status

# Build will resume from last completed task
workflow build
```

### Restore from Milestone

```bash
# 1. Find milestone tag
git tag -l "milestone-*"

# 2. Reset to milestone
git reset --hard milestone-M1

# 3. Regenerate plan from that point
workflow plan --regen

# 4. Continue
workflow build --milestone M2
```

---

## Still Having Issues?

### Gather Debug Information

```bash
# Create debug report
cat > debug-report.txt << EOF
Version: $(workflow --version)
Phase: $(workflow status)
Git status: $(git status --short)
Configuration:
$(workflow config)

Recent logs:
$(tail -100 .workflow/logs/*.log)
EOF

cat debug-report.txt
```

### Check Documentation

- [Main README](../README.md)
- [Command Reference](COMMANDS.md)

### Report Issues

When reporting issues, include:
1. Command that failed
2. Error message
3. Output of `workflow --version`
4. Output of `workflow status`
5. Relevant logs from `.workflow/logs/`
6. Steps to reproduce

**GitHub Issues**: [repository-url/issues]

---

## Quick Reference: Common Fixes

| Problem | Quick Fix |
|---------|-----------|
| Build stuck | `workflow build --hitl task --max 5` |
| Tests failing | `workflow config --set BUILD_BACKPRESSURE_TESTS=false` |
| Too slow | `workflow config --set MODEL_BUILD_PRIMARY=sonnet` |
| Wrong state | Edit `docs/IMPLEMENTATION_PLAN.md`, change task state |
| Corrupted plan | `workflow plan --regen` |
| Uncommitted changes | `git reset --hard HEAD` |
| API timeout | `workflow config --set RETRY_MAX_ATTEMPTS=5` |
| Task blocked | Complete dependencies or edit plan |
| Config not working | `unset WORKFLOW_*` (remove env overrides) |
| Need oversight | `workflow build --hitl milestone` |
