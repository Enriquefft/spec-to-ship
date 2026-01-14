# Plan: Real-Time Transparent LLM UI Replacement

## Executive Summary

Replace the current logging system (`src/lib/activity.sh`, `src/lib/spinner.sh`, and related components) with a modern, real-time transparent UI that provides maximum visibility into LLM operations. The new system will be built as a lightweight Go application using Bubble Tea for the TUI, communicating with the main bash workflow via simple JSON messages over stdio/FIFOs.

## Vision

A split-screen terminal interface showing:
- **Top Panel**: Enhanced workflow status with progress bars, task queues, and metrics
- **Bottom Panel**: Real-time LLM communication stream showing prompts, responses, and metadata
- **Interactive Mode**: Ability to inject messages into LLM conversations
- **Minimal Overhead**: Sub-100ms latency for UI updates, <5MB memory usage

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                New TUI System (Go + Bubble Tea)          │
├─────────────────────────────────────────────────────────────┤
│  Workflow Status Panel      │    LLM Stream Panel          │
│  - Phase Progress          │    - Live Prompts/Responses  │
│  - Task Queue             │    - Timestamps & Metadata    │
│  - Metrics & Stats        │    - Message Injection Input  │
│  - Error Display          │    - Search/Filter           │
└─────────────────────────────────────────────────────────────┘
                    ↑ JSON over stdio/FIFO
┌─────────────────────────────────────────────────────────────┐
│          Modified Bash Workflow (Minimal Changes)           │
│  - Preserved: All existing commands and logic            │
│  - Added: JSON message emission to TUI                   │
│  - Removed: Old activity.sh, spinner.sh, common.sh logging│
└─────────────────────────────────────────────────────────────┘
```

## Implementation Phases

### Phase 0: Preparation (Day 0)
- Backup current implementation
- Create Go module structure
- Set up development environment

### Phase 1: Core TUI Framework (Days 1-2)
**New Files:**
- `cmd/workflow-tui/main.go` - Main TUI application entry point
- `internal/ui/` - Bubble Tea components and views
- `internal/config/` - Configuration parsing
- `internal/message/` - Message protocol definitions
- `internal/logger/` - Fallback logging when TUI unavailable

**Objectives:**
- Basic split-screen layout
- JSON message receiver
- Simple status display
- Integration with bash workflow

### Phase 2: Message Protocol Integration (Days 3-4)
**Modified Files:**
- `src/workflow` - Add TUI launch wrapper
- `src/lib/provider.sh` - Emit JSON messages for LLM calls
- New `src/lib/tui_bridge.sh` - Handle UI communication

**Message Types:**
```json
{
  "type": "llm_start",
  "phase": "clarify",
  "provider": "claude",
  "model": "claude-opus-4",
  "timestamp": "2025-01-13T10:00:00Z"
}

{
  "type": "llm_prompt",
  "content": "...",
  "tokens": 1500
}

{
  "type": "llm_response",
  "content": "...",
  "tokens": 800,
  "duration_ms": 3500
}

{
  "type": "phase_start",
  "phase": "build",
  "tasks": ["Task 1", "Task 2", "Task 3"]
}

{
  "type": "task_update",
  "task": "Task 1",
  "status": "in_progress",
  "progress": 0.6
}
```

### Phase 3: Enhanced Workflow UI (Days 5-6)
**Removed Files:**
- `src/lib/activity.sh` (entirely)
- `src/lib/spinner.sh` (entirely)
- Status line components from `src/lib/common.sh`

**Modified Files:**
- All command files in `src/commands/` - Replace activity calls with TUI messages
- All provider files - Remove logging, add TUI emission

**New Features:**
- Real-time progress bars for multi-step operations
- Task queue visualization
- Error highlight and details
- Phase transition animations
- Metrics dashboard (tokens used, costs, timing)

### Phase 4: Interactive Features (Days 7-8)
**New Components:**
- Message injection interface
- Search/filter for LLM history
- Export conversation feature
- Pause/resume workflow capability
- Configuration hot-reload

**Interactive Elements:**
- Ctrl+I: Inject message into current LLM conversation
- Ctrl+S: Search conversation history
- Ctrl+E: Export current session
- Space: Pause/resume
- Ctrl+C: Graceful shutdown

### Phase 5: Polish & Optimization (Days 9-10)
- Performance optimization (<100ms UI updates)
- Theme system (light/dark/custom)
- Accessibility features
- Comprehensive error handling
- Documentation and examples

## Technical Details

### Dependencies
**New Dependencies:**
- Go 1.22+ (for TUI application)
- github.com/charmbracelet/bubbletea (TUI framework)
- github.com/charmbracelet/lipgloss (styling)
- github.com/charmbracelet/bubbles (components)

**Removed Dependencies:**
- All bash logging utilities
- Color codes from common.sh
- Terminal control sequences

### Communication Protocol
Using JSON over stdio for simplicity and reliability:
```bash
# In bash
tui_emit() {
  echo "$1" > "$TUI_FIFO"
}

# Usage
tui_emit '{"type":"phase_start","phase":"clarify"}'
```

### Backward Compatibility
- All command-line interfaces remain unchanged
- Existing config files work unchanged
- Log files still generated (by TUI app)
- Can disable TUI with `WORKFLOW_TUI=false`

### Fallback Mode
If TUI unavailable:
- Simple line-based output
- Basic progress indicators
- Preserves all functionality

## File Structure After Migration

```
src/
├── workflow                    # Modified to launch TUI
├── commands/                   # Modified (no activity.sh calls)
├── lib/
│   ├── common.sh              # Simplified (removed logging)
│   ├── config.sh              # Unchanged
│   ├── tui_bridge.sh          # NEW: TUI communication
│   ├── provider.sh            # Modified (emit JSON)
│   ├── providers/             # Modified (no direct logging)
│   └── [REMOVED] activity.sh, spinner.sh
└── prompts/                   # Unchanged

cmd/workflow-tui/               # NEW: Go TUI application
├── main.go
├── internal/
│   ├── ui/
│   │   ├── model.go
│   │   ├── view.go
│   │   ├── update.go
│   │   └── components/
│   ├── message/
│   │   ├── types.go
│   │   └── decoder.go
│   └── config/
│       └── config.go
```

## Advantages of This Approach

1. **Maximum Transparency**: See every LLM message in real-time
2. **Modern UX**: Smooth animations, progress bars, interactive elements
3. **Low Overhead**: Go application is lightweight and fast
4. **Incremental**: Can be deployed phase by phase
5. **Maintainable**: Clean separation of concerns
6. **Extensible**: Easy to add new features
7. **Cross-Platform**: Works on Linux, macOS, Windows

## Risk Mitigation

1. **Complexity Risk**: Keep bash changes minimal, most logic in Go
2. **Performance Risk**: Benchmark each phase, optimize bottlenecks
3. **Compatibility Risk**: Preserve all existing interfaces
4. **Adoption Risk**: Feature flag to toggle old/new system

## Success Metrics

- UI latency < 100ms
- Memory usage < 5MB for TUI
- Zero functional regressions
- Improved developer satisfaction
- Reduced debugging time

## Rollback Plan

If issues arise:
- Keep old logging files for 2 versions
- Simple config flag `WORKFLOW_TUI=false` disables new system
- Can revert to old system within hours

## Next Steps

1. Approve this plan
2. Set up Go development environment
3. Begin Phase 1 implementation
4. Daily progress reviews
5. User testing after each phase