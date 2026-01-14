# Migration to TUI System

## Completed
- Old logging system backed up to: $BACKUP_DIR
- src/lib/common.sh updated (removed logging functions)
- Commands updated to use TUI bridge

## What Changed
- Removed: src/lib/activity.sh, src/lib/spinner.sh
- Removed: Log functions from src/lib/common.sh
- Added: TUI bridge with JSON message protocol
- Added: Real-time TUI display

## To Use New System
```bash
export WORKFLOW_TUI=true
workflow <command>
```

## To Revert if Needed
```bash
# Restore from backup
cp .backup/old-logging-*/src/lib/* src/lib/
cp .backup/old-logging-*/src/workflow src/

# Reload or restart terminal
```

## Notes
The TUI system provides:
- Real-time visibility into LLM operations
- Message injection capability (Ctrl+I)
- Better UX with progress bars and metrics
- Backward compatibility (can disable with WORKFLOW_TUI=false)
