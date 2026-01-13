# Feature Spec: Spec-to-Ship Improvements

**Branch**: `002-spec-to-ship-improvements` **Priority**: P1 **Status**: In
Progress

## Overview

Enhance spec-to-ship with token optimization, first-class multi-agent support,
and quality gate enforcement. Inspired by GitHub's spec-kit, targeting 40-60%
token cost reduction and production-grade robustness.

## User Stories

### US1: Token Cost Optimization (P1)

**As a** developer using spec-to-ship workflows **I want** reduced token
consumption per workflow run **So that** I can minimize AI costs without
sacrificing quality

**Acceptance Criteria**:

- [ ] Cache TTLs extended to 30-60 minutes for stable context
- [ ] Prompts reduced by 40% without losing essential guidance
- [ ] Agent history summarized after 3 steps (not full history)
- [ ] Plan parsed once per build, not per task
- [ ] Cross-phase context cached and reused

**Success Metric**: 40-60% reduction in tokens per workflow run

### US2: Multi-Agent Support (P1)

**As a** developer with different AI tool preferences **I want** easy switching
between AI providers **So that** I can use my preferred agent or fallback when
one is unavailable

**Acceptance Criteria**:

- [ ] Single command to set default provider:
      `workflow config set PROVIDER_DEFAULT <agent>`
- [ ] Always displays which agent/model is being used
- [ ] Automatic fallback chain when primary unavailable
- [ ] `workflow provider list` shows available agents
- [ ] `workflow provider test <agent>` verifies connectivity
- [ ] Cost/token estimation displayed after each phase

**Success Metric**: Provider switch takes < 30 seconds, clear visibility

### US3: Quality Gate Enforcement (P1)

**As a** team lead ensuring code quality **I want** build to block on
constitution/checklist violations **So that** quality standards are enforced
automatically

**Acceptance Criteria**:

- [ ] Constitution violations block build by default
- [ ] `--force` flag required to override
- [ ] Incomplete checklists block build by default
- [ ] Clear error messages with recovery hints
- [ ] Default constitution example provided

**Success Metric**: Zero builds proceed with violations unless explicitly
overridden

### US4: Build Resilience (P2)

**As a** developer running long build loops **I want** to resume from where I
left off after interruption **So that** I don't lose progress on partial builds

**Acceptance Criteria**:

- [ ] Build state persisted to `.workflow/state.json`
- [ ] `workflow build --resume` continues from last checkpoint
- [ ] Completed tasks not re-executed

### US5: Decision Audit Trail (P2)

**As a** team member reviewing past decisions **I want** clarification Q&A
history persisted **So that** I can understand why certain choices were made

**Acceptance Criteria**:

- [ ] Q&A stored in `specs/NNN-feature/decisions.md`
- [ ] Timestamped entries with question, answer, rationale

## Technical Approach

See `plan.md` for detailed implementation plan covering:

- Phase 1: Token Optimization
- Phase 2: Multi-Agent UX
- Phase 3: Quality Gates
- Phase 4: Robustness
- Phase 5: Advanced Features

## Dependencies

- Existing provider abstraction layer (src/lib/provider.sh)
- Existing cache system (src/lib/cache.sh)
- Existing context compression (src/lib/context.sh)

## Risks & Mitigations

| Risk                                 | Mitigation                                |
| ------------------------------------ | ----------------------------------------- |
| Aggressive caching causes stale data | Add cache invalidation on file changes    |
| Prompt reduction loses quality       | A/B test before/after on sample workflows |
| Breaking existing workflows          | Maintain backward compatibility flags     |
