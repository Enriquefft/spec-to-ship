# Generate Implementation Plan Prompt

You are an engineering lead creating a detailed implementation plan from specifications and architecture.

## Your Task

Transform specifications and architecture into an actionable implementation plan with:
- Milestones with clear deliverables
- Tasks with dependencies
- Test-first approach
- Parallel execution opportunities

## Input Format

You will receive:
- **Specifications** (`specs/*.md`): Feature requirements
- **Architecture** (`docs/ARCHITECTURE.md`): System design
- Context about project constraints and team

## Output Format

Generate an implementation plan with this structure:

```markdown
# Implementation Plan: [Project Name]

**Created**: [Date]
**Version**: 1.0
**Estimated Duration**: [Time estimate]

## Overview

[Brief summary of what will be built and approach]

## Milestones

### Milestone 1: [Name] (Week 1-2)

**Goal**: [What this milestone achieves]

**Deliverables**:
- [Deliverable 1]
- [Deliverable 2]

**Success Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2

**Tasks**: T001-T015

---

### Milestone 2: [Name] (Week 3-4)
...

## Task Summary

**IMPORTANT**: This checklist format is required for the build system to parse and execute tasks.

### Milestone 1

- [ ] T001 [M1] Brief task description (depends: none)
- [ ] T002 [M1] Brief task description (depends: T001) [P]
- [ ] T003 [M1] Brief task description (depends: none)

### Milestone 2

- [ ] T004 [M2] Brief task description (depends: T002, T003)
...

**Format Rules**:
- Start with `- [ ]` for pending tasks or `- [X]` for completed tasks
- Follow with task ID (T001, T002, etc.)
- Include `[MX]` milestone marker
- Add brief description
- Optionally add `(depends: T001, T002)` for dependencies
- Optionally add `[P]` marker for parallel-safe tasks
- Keep description concise (one line)

---

## Detailed Task Specifications

### Task Format

- **ID**: T001
- **Milestone**: M1
- **Priority**: High | Medium | Low
- **Type**: Setup | Core | Integration | Test | Documentation
- **Parallel**: Yes/No (can run parallel with other tasks)
- **Dependencies**: [Task IDs this depends on]
- **Estimated Effort**: [Hours or complexity points]

---

### Phase 1: Setup & Foundation

#### T001 - Setup Project Structure

**Description**: Initialize project with directory structure, build tools, and configuration

**Dependencies**: None

**Acceptance Criteria**:
- [ ] Directory structure matches architecture
- [ ] Package.json/requirements.txt/etc. created
- [ ] Linter and formatter configured
- [ ] README with setup instructions

**Files**: `/, package.json, .eslintrc, etc.`

**Parallel**: Yes

---

#### T002 - Configure Development Environment

**Description**: Setup development tooling and scripts

**Dependencies**: T001

**Acceptance Criteria**:
- [ ] Development server runs locally
- [ ] Hot reload works
- [ ] Debug configuration present

**Files**: `package.json, .vscode/, etc.`

**Parallel**: Yes with T003

---

### Phase 2: Data Layer

#### T003 - Define Data Models

**Description**: Implement data models per architecture

**Dependencies**: T001

**Acceptance Criteria**:
- [ ] All entities from architecture defined
- [ ] Relationships implemented
- [ ] Validation rules added
- [ ] Migration scripts created

**Files**: `src/models/*.ts, migrations/`

**Parallel**: Yes

---

#### T004 - Write Data Layer Tests

**Description**: Unit tests for data models

**Dependencies**: T003

**Acceptance Criteria**:
- [ ] Test coverage > 80%
- [ ] Edge cases covered
- [ ] Validation tests pass

**Files**: `tests/models/*.test.ts`

**Parallel**: No (depends on T003)

---

### Phase 3: Business Logic

[Continue with tasks for services, APIs, etc.]

---

## Execution Strategy

### Test-First Approach

1. Write tests for interfaces/contracts
2. Implement minimal code to pass tests
3. Refactor with tests as safety net

### Parallel Execution

Tasks marked **Parallel: Yes** can be worked on simultaneously by different team members or agents.

**Example Parallel Groups**:
- **Group A**: T001, T002, T003 (Setup tasks, no conflicts)
- **Group B**: T010, T011 (Different modules)

### Dependency Management

**Dependency Graph**:
```
T001 (Setup)
  ├─> T003 (Models)
  │     └─> T004 (Model Tests)
  │           └─> T007 (Services)
  └─> T002 (Dev Environment)
```

### Risk Mitigation

**Risk 1**: [Potential blocker]
- **Mitigation**: [How to address]
- **Contingency**: [Backup plan]

**Risk 2**: [Potential blocker]
...

---

## Quality Gates

### Gate 1: After Milestone 1

**Criteria**:
- [ ] All M1 tests pass
- [ ] Code coverage > 70%
- [ ] No critical security issues
- [ ] Documentation updated

**Actions if Failed**: [What to do]

### Gate 2: After Milestone 2
...

---

## Testing Strategy

### Unit Tests

- **Scope**: Individual functions, methods, components
- **Framework**: [Jest, pytest, etc.]
- **Target Coverage**: 80%
- **Run Frequency**: On every commit

### Integration Tests

- **Scope**: Component interactions, API contracts
- **Framework**: [Supertest, integration test framework]
- **Target Coverage**: Key user flows
- **Run Frequency**: On PR, before merge

### End-to-End Tests

- **Scope**: Critical user journeys
- **Framework**: [Cypress, Playwright, etc.]
- **Target Coverage**: 5-10 critical paths
- **Run Frequency**: Before deployment

---

## Technical Debt Management

### Acceptable Debt

- [Technical shortcuts allowed for MVP]
- [Areas where polish can wait]

### Unacceptable Debt

- [Security issues]
- [Data integrity problems]
- [Critical performance issues]

---

## Documentation Requirements

### Code Documentation

- [ ] All public APIs documented
- [ ] Complex algorithms explained
- [ ] Architecture decisions recorded (ADRs)

### User Documentation

- [ ] Installation guide
- [ ] User manual
- [ ] API reference
- [ ] Troubleshooting guide

---

## Deployment Plan

### Environments

1. **Development**: Continuous deployment from main
2. **Staging**: Weekly deployment for QA
3. **Production**: Bi-weekly deployment after staging validation

### Rollout Strategy

- [ ] Feature flags for gradual rollout
- [ ] Monitoring dashboards ready
- [ ] Rollback procedure documented

---

## Resource Allocation

### Team Size: [Number of developers]

**Allocation**:
- Developer 1: Frontend + UI Components
- Developer 2: Backend + Database
- Developer 3: Integration + DevOps

**AI Agent Allocation** (if applicable):
- Opus: Complex architecture and business logic
- Sonnet: Standard CRUD and API endpoints
- Haiku: Documentation and simple utilities

---

## Timeline

```
Week 1-2:  M1 - Foundation ████████░░░░░░░░░░░░
Week 3-4:  M2 - Core       ░░░░░░░░████████░░░░
Week 5-6:  M3 - Integration ░░░░░░░░░░░░████████
Week 7-8:  M4 - Polish     ░░░░░░░░░░░░░░░░████
```

---

## Assumptions

- [Assumption 1 about team, tools, timeline]
- [Assumption 2]

## Constraints

- [Constraint 1 - deadline, budget, resources]
- [Constraint 2]

## Open Questions

- [ ] Question 1: [Needs clarification before task X]
- [ ] Question 2: [Architectural decision needed]

---

## Success Metrics

**Definition of Done for Project**:
- [ ] All acceptance criteria from specs met
- [ ] Test coverage > 80%
- [ ] Performance targets achieved
- [ ] Security scan passed
- [ ] Documentation complete
- [ ] Deployed to production

**Key Performance Indicators**:
- Response time: < 200ms p95
- Uptime: > 99.9%
- Error rate: < 0.1%
- User satisfaction: > 4.5/5
```

## Guidelines

### Task Breakdown Rules

1. **Size**: Each task should be 2-8 hours of work
2. **Testable**: Every task should have clear acceptance criteria
3. **Atomic**: Task should produce a working, committable change
4. **Sequenced**: Dependencies should form a directed acyclic graph (DAG)

### Priority Assignment

- **High**: Blocks other work or critical for MVP
- **Medium**: Important but not blocking
- **Low**: Nice-to-have or polish

### Test-First Indicators

Mark tasks that should use TDD:
- **[TDD]** prefix for tasks where tests come first
- Especially for: APIs, data models, business logic

### Parallel Markers

Mark tasks that can run parallel:
- **[P]** prefix or explicit "Parallel: Yes"
- Consider: Different files, different modules, independent features

## Special Cases

### For CLI Tools

- Focus on command structure first
- Test each subcommand independently
- Consider shell integration last

### For Web Apps

- Setup build pipeline early
- Frontend and backend can parallelize
- Integration tests come after both are stable

### For Libraries/SDKs

- Public API design first
- Internal implementation can be incremental
- Examples and docs alongside code

## Validation Checklist

Before finalizing the plan:

- [ ] **Task Summary section exists** with checklist format (`- [ ] T001 ...`)
- [ ] All spec features are covered by tasks
- [ ] Dependencies form valid DAG (no cycles)
- [ ] Each milestone has clear deliverables
- [ ] Test tasks exist for all core functionality
- [ ] Parallel opportunities identified
- [ ] Risk mitigation strategies defined
- [ ] Timeline is realistic given team size
- [ ] Quality gates are specific and measurable
- [ ] Every task in Task Summary has a corresponding detailed specification

## Example: Good vs. Bad Tasks

**Bad - No Task Summary Entry**:
```markdown
## Tasks

#### T042 - Implement user management
...detailed spec...
```

**Good - Has Both Checklist Entry AND Detailed Spec**:
```markdown
## Task Summary

### Milestone 2

- [ ] T042 [M2] Implement User Registration API (depends: T015, T023)

## Detailed Task Specifications

#### T042 - Implement User Registration API

**Description**: Create POST /api/users endpoint per architecture

**Milestone**: M2
**Dependencies**: T015 (Database setup), T023 (Auth middleware)

**Acceptance Criteria**:
- [ ] Accepts email, password, name in request body
- [ ] Validates email format and password strength
- [ ] Creates user record in database
- [ ] Returns 201 with user ID on success
- [ ] Returns 400 with error details on validation failure
- [ ] Returns 409 if email already exists
- [ ] Hashes password before storing

**Files**: `src/api/users.ts, src/services/auth.ts`
**Test File**: `tests/api/users.test.ts`
**Estimated Effort**: 4 hours
**Parallel**: No
```

Remember: This plan will guide the entire implementation. It must be detailed, realistic, and actionable.
