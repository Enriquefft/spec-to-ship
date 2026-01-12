# Edge Case Handling

This document describes how the Spec-to-Ship workflow handles various edge cases and exceptional situations.

## Table of Contents

1. [Mid-Commit Interruption](#mid-commit-interruption)
2. [Claude API Rate Limits](#claude-api-rate-limits)
3. [Missing Dependencies](#missing-dependencies)
4. [Subdirectory Detection](#subdirectory-detection)
5. [Configuration Issues](#configuration-issues)
6. [File System Errors](#file-system-errors)
7. [Network Failures](#network-failures)

---

## Mid-Commit Interruption

**Scenario**: User interrupts `workflow build` with Ctrl+C during a git commit operation.

**Handling**:

1. Signal handler catches SIGINT/SIGTERM
2. System completes current atomic operation before exit
3. Git operations use `git_atomic_commit` which ensures:
   - All changes are staged before commit
   - Commit happens as single atomic operation
   - If interrupted before commit: changes remain staged (can be reviewed/committed manually)
   - If interrupted after commit: commit is complete and safe

**Recovery**:
```bash
# Check git status
git status

# If changes are staged but not committed:
git commit -m "Manual commit after interruption"
# OR
git reset  # to unstage

# Then resume workflow
workflow build
```

**Prevention**: The build loop updates the implementation plan AFTER successful commit, so interruption won't mark incomplete work as done.

---

## Claude API Rate Limits

**Scenario**: Claude API returns rate limit errors (429 status) or quota exceeded.

**Handling**:

1. System implements exponential backoff in `claude_invoke` function:
   - Initial delay: `RETRY_BASE_DELAY` seconds (default: 2)
   - Max attempts: `RETRY_MAX_ATTEMPTS` (default: 3)
   - Backoff multiplier: 2x per attempt

2. Retry sequence:
   ```
   Attempt 1: Immediate
   Attempt 2: Wait 2 seconds
   Attempt 3: Wait 4 seconds
   Final:     Fail with error
   ```

3. User notification:
   - Log warning on first retry
   - Log error with instructions after final failure

**Configuration**:
```bash
# In .workflow/config.sh
RETRY_MAX_ATTEMPTS=5      # More retries
RETRY_BASE_DELAY=10       # Longer initial delay
```

**Recovery**:
- Wait for rate limit reset (typically 1 minute to 1 hour)
- Check API status: https://status.anthropic.com
- Resume with: `workflow build`

**Alternative**: Switch to different model tiers:
```bash
# Use faster, lower-tier model for build iterations
MODEL_BUILD_PRIMARY="haiku"  # Instead of "opus"
```

---

## Missing Dependencies

**Scenario**: Required commands or files are not available.

### Missing System Commands

**Detection**: `require_command` checks for required binaries

**Common Missing Dependencies**:
- `git` - Version control system
- `jq` - JSON processing
- `envsubst` - Template variable substitution
- `bats` - Testing framework (development only)

**Handling**:
```bash
workflow: line 42: require_command: git
ERROR: Required command not found: git
```

**Recovery**:
```bash
# Debian/Ubuntu
sudo apt-get install git jq gettext-base

# macOS
brew install git jq gettext

# Arch Linux
sudo pacman -S git jq envsubst
```

### Missing Required Files

**Detection**: `require_file` checks for critical files

**Examples**:
- `docs/PRD.md` required for `workflow clarify`
- `docs/PRD_STRUCTURED.md` required for `workflow specs`
- `.workflow/config.sh` expected (but uses defaults if missing)

**Handling**:
```bash
ERROR: Required file not found: docs/PRD.md
```

**Recovery**: Create missing file or run prerequisite command:
```bash
# For missing PRD
echo "# Product Requirements" > docs/PRD.md

# For missing structured PRD
workflow clarify

# For missing config (auto-created by init)
workflow init
```

---

## Subdirectory Detection

**Scenario**: User runs `workflow init` from a subdirectory of a git repository.

**Detection**:
```bash
git_root=$(get_git_root)
current_dir=$(pwd)

if [[ "$git_root" != "$current_dir" ]]; then
    # Not at repository root
fi
```

**Handling**:

1. System detects git root using `git rev-parse --show-toplevel`
2. Warns user about non-standard location:
   ```
   WARNING: Running in subdirectory of git repository
   Git root: /home/user/project
   Current:  /home/user/project/backend

   Consider running from repository root for consistency.
   ```

3. User options:
   - **Recommended**: `cd` to git root and re-run
   - **Alternative**: Continue in subdirectory (workflow will work but files may be in unexpected locations)

**Configuration Location**:

The system uses git root for configuration and logs:
```bash
.workflow/          # At git root
  config.sh
  logs/
```

If run from subdirectory, files are still created at git root, not current directory.

---

## Configuration Issues

### Invalid Configuration Values

**Scenario**: Config file contains invalid model names, boolean values, or other settings.

**Handling**:

1. `config_validate()` checks all settings
2. Reports all validation errors at once:
   ```
   ERROR: Invalid model for MODEL_BUILD_PRIMARY: gpt4 (must be one of: opus sonnet haiku)
   ERROR: Invalid boolean value for HITL_ENABLED: yes (must be true or false)
   ```

3. System exits with code 1

**Recovery**:
```bash
# Edit configuration
workflow config --edit

# Or manually
vim .workflow/config.sh

# Check configuration
workflow config --get MODEL_BUILD_PRIMARY
```

### Secrets in Configuration

**Scenario**: User accidentally puts API keys or passwords in config file.

**Handling**:

1. `config_validate_no_secrets()` scans for common secret patterns:
   - API keys (sk-*, ghp_*, etc.)
   - Hash values (MD5, SHA1, SHA256)
   - Private keys

2. Blocks loading with error:
   ```
   ERROR: Configuration key 'CLAUDE_API_KEY' appears to contain a secret
   ERROR: Secrets should be stored in environment variables like WORKFLOW_CLAUDE_API_KEY, not in config files
   ```

**Recovery**:
```bash
# Remove secret from config file
vim .workflow/config.sh

# Set as environment variable instead
export WORKFLOW_CLAUDE_API_KEY="sk-..."

# Or add to ~/.bashrc for persistence
echo 'export WORKFLOW_CLAUDE_API_KEY="sk-..."' >> ~/.bashrc
```

**Logging Protection**: Secrets are automatically redacted from logs (see `_sanitize_message` in `src/lib/common.sh`).

---

## File System Errors

### Permission Denied

**Scenario**: Cannot create directories or write files.

**Common Causes**:
- Running in read-only directory
- Insufficient permissions on target directory
- SELinux or AppArmor restrictions

**Handling**:
```bash
ERROR: Failed to create directory: .workflow/logs
```

**Recovery**:
```bash
# Check permissions
ls -ld .workflow/

# Fix permissions
chmod 755 .workflow/

# Or run in directory where you have write access
cd ~/projects/myproject
workflow init
```

### Disk Full

**Scenario**: No space available for logs or generated files.

**Handling**: System fails with error when disk is full

**Recovery**:
```bash
# Check disk space
df -h

# Clean up logs
rm .workflow/logs/*.log

# Clean up old git objects
git gc --aggressive
```

---

## Network Failures

### Transient Network Issues

**Scenario**: Network connection drops during Claude API call.

**Handling**:

1. Caught by retry logic in `claude_invoke`
2. Automatically retries with exponential backoff
3. Logs warning for transient failures

**User sees**:
```
WARN: Claude API request failed (attempt 1/3): Connection timeout
WARN: Retrying in 2 seconds...
```

### Persistent Network Failure

**Scenario**: No internet connection available.

**Handling**:

1. All retry attempts fail
2. System exits with clear error:
   ```
   ERROR: Failed to invoke Claude API after 3 attempts
   ERROR: Please check your internet connection and try again
   ```

**Recovery**:
```bash
# Check connectivity
ping api.anthropic.com

# Check API status
curl -I https://api.anthropic.com

# When network is restored
workflow build
```

### Git Push Failures

**Scenario**: `workflow build` with `BUILD_PUSH_AFTER_COMMIT=true` fails to push.

**Handling**:

1. Commit succeeds locally (atomic operation)
2. Push failure is logged but doesn't block progress
3. User can push manually later

**Configuration**:
```bash
# Disable auto-push if connectivity is unreliable
BUILD_PUSH_AFTER_COMMIT=false
```

---

## Summary of Exit Codes

Understanding exit codes helps with automation and error handling:

| Code | Meaning | Examples |
|------|---------|----------|
| 0 | Success | All operations completed successfully |
| 1 | Error | Missing files, validation failures, API errors |
| 2 | Partial Success | Max iterations reached, gate failed but forced |

**Usage in scripts**:
```bash
if workflow build --max 10; then
    echo "Build completed successfully"
elif [ $? -eq 2 ]; then
    echo "Build reached max iterations (not an error)"
else
    echo "Build failed"
    exit 1
fi
```

---

## Best Practices

1. **Always work from git repository root** for consistency
2. **Set secrets in environment variables**, never in config files
3. **Run with --verbose** when debugging issues
4. **Check logs** in `.workflow/logs/` for detailed error information
5. **Use configuration validation** before long-running operations:
   ```bash
   workflow config --get MODEL_BUILD_PRIMARY  # Validates config
   ```

6. **Monitor disk space** if running many build iterations
7. **Keep git repository clean** - commit or stash changes before running workflow
8. **Test API connectivity** before starting long operations:
   ```bash
   # Quick test
   workflow clarify --help  # No API call
   ```

---

## Getting Help

If you encounter an edge case not documented here:

1. Check logs: `.workflow/logs/*.log`
2. Run with verbose output: `workflow --verbose <command>`
3. Review git status: `git status`
4. Check configuration: `workflow config --get`
5. Report issue: [GitHub Issues](https://github.com/your-org/spec-to-ship)

For emergency recovery:
```bash
# Reset to clean state
git reset --hard HEAD
git clean -fd

# Reinitialize
workflow init --force
```
