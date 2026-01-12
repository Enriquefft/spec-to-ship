# Spec-to-Ship Improvement Plan

**Focus**: Quality Gates, Robustness, Advanced Features, Token/Cost Optimization
**Enforcement**: Block by default (constitution/checklist violations)
**Refactoring**: Allowed

---

## Executive Summary

Spec-to-ship has **excellent feature parity** with spec-kit and a **clean multi-agent abstraction** (95% ready for 18+ agents). The main opportunities are:

1. **Token Optimization** - 8,000-15,000 tokens wasted per workflow (40-60% reduction achievable)
2. **Quality Gates** - Constitution/checklist enforcement missing (blocking by default)
3. **Robustness** - No versioning, audit trails, or resume capability
4. **Multi-Agent** - Abstraction exists, just needs more providers + fallback chains

---

## PHASE 1: Token & Cost Optimization (HIGH IMPACT)

### 1.1 Extend Cache TTLs (Quick Win)
**Current**: 300-600 second TTLs cause frequent recalculation
**Impact**: 200-400 tokens saved per workflow
**Files**:
- `src/lib/context.sh` lines 20-28, 65-68, 102-105, 242

```bash
# Change from:
cache_get "$cache_key" 300    # 5 min
cache_get "$cache_key" 600    # 10 min

# To:
cache_get "$cache_key" 1800   # 30 min for task context
cache_get "$cache_key" 3600   # 1 hour for stable context (specs, arch)
```

### 1.2 Load Spec Summaries Instead of Full Content
**Current**: `arch.sh:207-220` loads entire spec files
**Impact**: 1,500-2,000 tokens saved
**Files**:
- `src/commands/arch.sh` lines 207-220

```bash
# Replace full concat with summary loading
# Use context_get_spec_list() for titles
# Load full content only when referenced
```

### 1.3 Reduce Prompt Verbosity by 40%
**Current**: PROMPT_plan.md has 469 lines, 66 headings, excessive examples
**Impact**: 2,000-3,000 tokens saved per phase
**Files**:
- `src/prompts/PROMPT_plan.md` - Remove lines 95-150 (example details)
- `src/prompts/PROMPT_arch.md` - Trim code block examples
- `src/prompts/PROMPT_clarify.md` - Reduce formatting rules

**Strategy**: Keep base essentials, extract examples to optional enrichment file

### 1.4 Implement Agent History Summarization
**Current**: Full history grows exponentially (step 15 = 30,000+ tokens)
**Impact**: 4,000-8,000 tokens saved per build task
**Files**:
- `src/lib/agent.sh` lines 44-61, 82-86

```bash
# Keep last 3 steps in full detail
# Summarize earlier steps to bullet points
# Cache summary results
```

### 1.5 Pre-Parse Plan into Task Index
**Current**: `build.sh:358-370` rebuilds context for each of 50 tasks
**Impact**: 2,000-3,000 tokens saved per build
**Files**:
- `src/commands/build.sh` lines 358-370
- `src/lib/plan.sh` - Add `plan_get_task_index()` function

```bash
# Parse plan once at build start
# Store: task_id -> (desc, deps, milestone) in memory
# Reuse across all tasks instead of re-parsing
```

### 1.6 Cross-Phase Context Caching
**Current**: Same context recomputed in clarify→specs→arch→plan
**Impact**: 1,000-2,000 tokens across multi-phase runs
**Files**:
- `src/lib/cache.sh` - Add unified cache keys
- `src/lib/context.sh` - Use cross-phase keys

```bash
# Cache keys that persist across phases:
# - specs_summary (clarify→specs→arch→plan)
# - arch_overview (arch→plan→build)
# TTL: 3600+ seconds
```

**Total Token Savings**: ~8,000-15,000 tokens per workflow (40-60% reduction)

---

## PHASE 2: Quality Gates (Block by Default)

### 2.1 Constitution Enforcement
**Current**: Check exists in template but not enforced
**Fix**: Block build on violations, require `--force` to override

**Files to modify**:
- `src/commands/build.sh` - Add validation before task loop
- `src/lib/constitution.sh` (new) - Parsing and validation

```bash
# In build.sh, before task loop:
if ! constitution_validate "$project_root"; then
    if [[ "$force" != "true" ]]; then
        die "Constitution violations detected. Use --force to override."
    fi
    log_warn "Proceeding despite constitution violations (--force)"
fi
```

### 2.2 Checklist Gate Integration
**Current**: Warns but doesn't block
**Fix**: Block build if checklist incomplete, require `--force` to override

**Files to modify**:
- `src/commands/build.sh` - Add checklist validation
- `src/lib/checklist.sh` (new) - Checklist parsing

```bash
# CONFIG: REQUIRE_CHECKLIST=true (default)
# Flag: --no-checklist to skip
```

### 2.3 Default Constitution Example
**Files to create**:
- `.specify/constitution.md` - Populated with sensible defaults

```markdown
# Project Constitution

## Principles

1. **Dependency Discipline**: Max 3 new external dependencies per feature
2. **Test Coverage**: All public APIs must have tests before merge
3. **Breaking Changes**: Require migration path and deprecation notice
4. **Feature Flags**: New features behind flags for gradual rollout
5. **Documentation**: Public APIs documented before implementation

## Enforcement
- Gate: build phase blocks on violations
- Override: --force flag with justification
```

---

## PHASE 3: Robustness

### 3.1 Progress Persistence & Resume
**Current**: Build state lost on interruption
**Fix**: Checkpoint after each task, resume from checkpoint

**Files to modify**:
- `src/commands/build.sh` - Add `--resume` flag
- `.workflow/state.json` (new) - Persistence file

```json
{
  "build_id": "abc123",
  "started_at": "2024-01-12T10:00:00Z",
  "last_task": "T005",
  "completed_tasks": ["T001", "T002", "T003", "T004", "T005"],
  "current_milestone": "M1"
}
```

### 3.2 Decision Audit Trail
**Current**: Clarification answers not persisted
**Fix**: Store Q&A history with timestamps

**Files to modify**:
- `src/commands/clarify.sh` - Persist decisions
- `specs/NNN-feature/decisions.md` (new) - Audit file

```markdown
# Decision Log

## 2024-01-12 10:30

**Q**: Should we use REST or GraphQL?
**A**: REST - simpler for MVP, team familiar
**Rationale**: Speed to market priority
```

### 3.3 Spec Versioning
**Current**: Specs overwritten, no history
**Fix**: Version on regeneration, allow comparison

**Files to modify**:
- `src/commands/specs.sh` - Add versioning logic
- `specs/NNN-feature/versions/` (new) - Version directory

```bash
# On spec regeneration:
# 1. Copy current to versions/spec-v1.md
# 2. Generate new spec.md
# 3. Log version bump
```

### 3.4 Enhanced Error Messages
**Current**: Errors show what failed, not how to fix
**Fix**: Add recovery hints

**Files to modify**:
- `src/lib/common.sh` - Enhance `die()` function

```bash
die_with_hint() {
    local msg="$1"
    local hint="$2"
    log_error "$msg"
    log_info "Hint: $hint"
    exit 1
}

# Usage:
die_with_hint "Constitution validation failed" \
    "Run 'workflow status --constitution' to see violations"
```

---

## PHASE 4: Multi-Agent Support (First-Class Priority)

### 4.1 Design Goals
- **Easy to enable**: Single config change or flag
- **Transparent**: Always show which agent is being used
- **Graceful fallback**: Automatic failover if primary unavailable
- **Cost-aware**: Show token/cost estimates per agent

### 4.2 Current State (Already 95% There)
- Provider abstraction layer exists (`src/lib/provider.sh`)
- 3 providers implemented (Claude, OpenCode, Gemini)
- Phase-based resolution works
- Auto-discovery from `src/lib/providers/` directory

### 4.3 Simple Enable Experience

**Option A: Global default agent**
```bash
# .workflow/config or workflow config set
workflow config set PROVIDER_DEFAULT opencode

# Or environment variable
export WORKFLOW_PROVIDER=gemini
```

**Option B: Per-phase agent selection**
```bash
workflow config set PROVIDER_PLAN claude      # Use Claude for planning
workflow config set PROVIDER_BUILD opencode   # Use OpenCode for build
```

**Option C: Command-line override**
```bash
workflow plan --provider gemini
workflow build --provider opencode
```

### 4.4 Transparent Agent Display
**Add to all commands**: Show which agent is being used

```bash
$ workflow plan
[INFO] Using provider: claude (claude-sonnet-4-5-20250929)
[INFO] Phase: plan (capability: high)
[INFO] Loading implementation plan...
```

**Files to modify**:
- `src/lib/provider.sh` - Add `provider_announce()` function
- All commands - Call announce before invocation

```bash
provider_announce() {
    local phase="$1"
    local provider model capability
    provider="$(provider_get_for_phase "$phase")"
    model="$(provider_resolve_model "$provider" "$phase")"
    capability="$(provider_resolve_capability "$phase")"

    log_info "Using provider: $provider ($model)"
    log_info "Phase: $phase (capability: $capability)"
}
```

### 4.5 Automatic Fallback Chains
**Config**:
```bash
# Primary fails → try next in chain
PROVIDER_FALLBACK_CHAIN="claude,opencode,gemini"

# Per-phase fallback (optional)
PROVIDER_PLAN_FALLBACK="claude,gemini"
PROVIDER_BUILD_FALLBACK="opencode,claude"
```

**Behavior**:
```bash
$ workflow build
[INFO] Primary provider (claude) unavailable
[INFO] Falling back to: opencode
[INFO] Using provider: opencode (opencode/glm-4.7-free)
```

**Files to modify**:
- `src/lib/provider.sh` - Enhance `provider_get_for_phase()`
- `src/lib/config.sh` - Add fallback chain config

### 4.6 Agent Availability Command
**New command**: `workflow provider`

```bash
$ workflow provider list
PROVIDER     STATUS      MODELS
claude       available   opus-4, sonnet-4.5, haiku-4
opencode     available   big-pickle, glm-4.7-free, grok-code
gemini       available   gemini-3-pro, gemini-2.5-flash
cursor       not found   (install: cursor-cli)
windsurf     not found   (install: windsurf-cli)

$ workflow provider test claude
Testing claude... OK (response time: 1.2s)

$ workflow provider set-default opencode
Default provider set to: opencode
```

**Files**:
- `src/commands/provider.sh` - Already exists, enhance it

### 4.7 Cost/Token Estimation Display
**Add to phase completion**:

```bash
$ workflow plan
[INFO] Using provider: claude (claude-sonnet-4-5-20250929)
...
[INFO] ✓ Plan generated successfully
[INFO] Tokens used: ~4,500 (est. cost: $0.045)
```

**Files to modify**:
- `src/lib/provider.sh` - Add `provider_estimate_cost()`
- Track token counts from responses

### 4.8 Provider Interface (For Adding New Agents)

**Required functions** (each provider ~300-400 lines):
```bash
# src/lib/providers/<agent>.sh

provider_<NAME>_validate()      # Check CLI installed, API key set
provider_<NAME>_invoke()        # Send prompt, get response
provider_<NAME>_stream()        # Optional: streaming mode
provider_<NAME>_list_models()   # Return available models
provider_<NAME>_map_model()     # Map capability level to model name
provider_<NAME>_init()          # One-time initialization
```

**Adding a new provider**:
1. Create `src/lib/providers/cursor.sh`
2. Implement required functions
3. Provider auto-discovered on next run
4. Configure: `workflow config set PROVIDER_DEFAULT cursor`

### 4.9 Priority Providers to Add
| Agent | CLI | Priority | Notes |
|-------|-----|----------|-------|
| Cursor | cursor | High | Popular IDE agent |
| Windsurf | windsurf | High | Codeium's agent |
| Copilot | gh copilot | Medium | GitHub native |
| Amazon Q | q | Medium | AWS ecosystem |
| Aider | aider | Low | Terminal-based |

### 4.10 Documentation
**Create**: `docs/PROVIDERS.md`

```markdown
# Multi-Agent Support

## Quick Start
workflow config set PROVIDER_DEFAULT <agent>

## Available Providers
- claude: Anthropic Claude (default)
- opencode: OpenCode models
- gemini: Google Gemini

## Adding Custom Providers
See src/lib/providers/claude.sh as template...

## Fallback Configuration
...
```

---

## PHASE 5: Advanced Features

### 5.1 Creative Exploration Mode
**Add**: `workflow plan --explore 3` generates 3 alternative approaches

**Files**:
- `src/commands/plan.sh` - Add `--explore N` flag
- Generate N plans with different tech stack constraints

### 5.2 Brownfield Analysis
**Add**: `workflow analyze` scans existing codebase before planning

**Files to create**:
- `src/commands/analyze.sh` - Scan patterns, tech stack, conventions
- Feed analysis into plan phase context

### 5.3 CI/CD Integration
**Files to create**:
- `.github/workflows/spec-to-ship.yml` - GitHub Actions template
- `docs/CI_INTEGRATION.md` - Setup guide

---

## Implementation Roadmap

| Phase | Focus | Effort | Impact |
|-------|-------|--------|--------|
| **1** | Token Optimization | 2-3 days | -40-60% cost reduction |
| **2** | Multi-Agent UX | 2-3 days | Easy enable, transparent, fallback |
| **3** | Quality Gates | 1-2 days | Block-by-default enforcement |
| **4** | Robustness | 2-3 days | Resume, versioning, audit |
| **5** | Advanced | 3-5 days | Exploration, brownfield, CI/CD |

**Execution Plan**:
1. Commit all current 001 changes first
2. Create new feature branch: `002-spec-to-ship-improvements`
3. Work on Phases 1, 2, 3 **in parallel** (all high priority)
4. Phase 4 (Robustness) after core complete
5. Phase 5 (Advanced) as stretch goals

---

## Next Steps (Post-Plan Mode)

```bash
# 1. Commit current 001 changes
git add -A
git commit -m "feat: complete 001-spec-to-ship-workflow implementation"

# 2. Create new feature for improvements
workflow init 002-spec-to-ship-improvements

# 3. Copy this plan to new feature spec
cp ~/.claude/plans/fluttering-mixing-treasure.md specs/002-spec-to-ship-improvements/

# 4. Begin implementation (parallel work streams)
```

**Parallel Work Streams**:
- **Stream A**: Token optimization (context.sh, prompts, agent.sh)
- **Stream B**: Multi-agent UX (provider.sh, provider command)
- **Stream C**: Quality gates (build.sh, constitution.sh, checklist.sh)

---

## Critical Files Reference

**Token Optimization**:
- `src/lib/context.sh` - Cache TTLs, compression
- `src/lib/agent.sh` - History management
- `src/prompts/PROMPT_*.md` - Verbosity reduction
- `src/commands/build.sh` - Task context assembly

**Quality Gates**:
- `src/commands/build.sh` - Validation hooks
- `src/lib/constitution.sh` (new)
- `src/lib/checklist.sh` (new)

**Multi-Agent**:
- `src/lib/provider.sh` - Abstraction layer
- `src/lib/providers/*.sh` - Individual providers
- `src/lib/config.sh` - Capability matrix
