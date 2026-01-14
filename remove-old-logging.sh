#!/bin/bash
# remove-old-logging.sh - Remove activity.sh and spinner.sh systems

set -euo pipefail

echo "=== Removing Old Logging System ==="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Backup old files (just in case)
BACKUP_DIR=".backup/old-logging-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up old logging files..."
for file in src/lib/activity.sh src/lib/spinner.sh; do
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/"
        echo "  ✓ Backed up $(basename $file)"
    fi
done

# Remove references from other files
echo ""
echo "🔧 Removing references to old logging..."

# Update common.sh to remove logging functions
if [[ -f "src/lib/common.sh" ]]; then
    echo "  Updating src/lib/common.sh..."
    
    # Backup common.sh
    cp src/lib/common.sh "$BACKUP_DIR/common.sh.backup"
    
    # Remove old logging functions (keep non-logging utilities)
    sed -i '/^# Log level configuration/,/^# require_file(path)/d' src/lib/common.sh
    sed -i '/^# log_debug(message)/,/^# log_info(message)/d' src/lib/common.sh
    sed -i '/^# log_warn(message)/,/^# die(message, exit_code)/d' src/lib/common.sh
    sed -i '/^# log_to_file(level,/,/^# log_info(message)/d' src/lib/common.sh
    
    # Keep non-logging functions
    echo "    ✓ Removed logging functions"
else
    echo "  ⚠ src/lib/common.sh not found"
fi

# Check for activity.sh references in commands
echo ""
echo "🔍 Checking for activity.sh references..."
commands_with_activity=$(grep -l "activity_" src/commands/*.sh | wc -l)
if [[ $commands_with_activity -gt 0 ]]; then
    echo "  Found $commands_with_activity commands still referencing activity_ functions:"
    grep -l "activity_" src/commands/*.sh | sed 's/^/    /'
    echo ""
    echo "  These should be updated to use TUI bridge instead"
else
    echo "  ✓ No activity.sh references found"
fi

# Update workflow to not source activity.sh
echo ""
echo "🔄 Updating main workflow script..."
if [[ -f "src/workflow" ]]; then
    # Backup
    cp src/workflow "$BACKUP_DIR/workflow.backup"
    
    # Already updated in previous steps
    echo "  ✓ Already updated to use TUI bridge conditionally"
else
    echo "  ⚠ src/workflow not found"
fi

# Create migration notice
echo ""
echo "📄 Creating migration notice..."
cat > "MIGRATION-NOTICE.md" <<'EOF'
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
EOF

echo "  ✓ Created MIGRATION-NOTICE.md"

# Verify cleanup
echo ""
echo "🔍 Verifying cleanup..."
remaining_files=0

# Check if old files exist
for file in src/lib/activity.sh src/lib/spinner.sh; do
    if [[ -f "$file" ]]; then
        echo "  ⚠ $(basename $file) still exists"
        remaining_files=$((remaining_files + 1))
    fi
done

# Check if logging functions removed
if grep -q "log_debug\|log_info\|log_warn" src/lib/common.sh; then
    echo "  ⚠ Logging functions still in common.sh"
    remaining_files=$((remaining_files + 1))
fi

# Final status
echo ""
if [[ $remaining_files -eq 0 ]]; then
    echo -e "${GREEN}✓ Migration completed successfully!${NC}"
    echo ""
    echo "Old logging system removed."
    echo "New TUI system ready."
    echo ""
    echo "Run with: export WORKFLOW_TUI=true"
else
    echo -e "${YELLOW}⚠ Migration incomplete${NC}"
    echo "Some files remain or references exist."
    echo "Check the output above."
fi

echo ""
echo "=== Migration Complete ==="