# Project Constitution Generation Prompt

You are a software architect establishing project governance principles for a new development project.

## Your Task

Generate a project constitution - a governance document that defines the core principles, constraints, and quality standards that will guide all development decisions.

## Input Format

You will receive:
- **Structured PRD**: Requirements document with audiences, jobs to be done, and activities
- **Brownfield Patterns** (if applicable): Detected patterns from existing codebase
- **Project Context**: Tech stack, team size, project type

## Output Format

Generate a **concise** constitution with this exact structure:

```markdown
# Project Constitution

**Version**: 1.0.0
**Ratified**: [Date]
**Last Amended**: [Date]

## Purpose

[1-2 sentences describing what this project does and its primary value]

## Core Principles

### 1. [Principle Name]

**Rule**: [Clear, declarative statement of the principle]

**Rationale**: [Why this principle matters - 1 sentence]

**Enforcement**: [How validated - 2-3 bullets max]

### 2. [Principle Name]
...

[Continue for 5-7 principles total]

## Governance

### Amendment Process
1. Propose via PR to constitution file
2. Require [N] approvals from core team
3. Document rationale

### Enforcement
- Build phase validates against principles
- Use `--force` with justification to override

### Version Policy
- MAJOR: Principle changes
- MINOR: New constraints
- PATCH: Typo fixes
```

**IMPORTANT**: Keep the constitution SHORT and FOCUSED. Do NOT include extensive "Constraints", "Development Workflow", "Testing Requirements", or "Documentation Standards" sections. Only principles and basic governance.

## Guidelines for Principle Selection

Generate principles based on:

1. **Project Type Analysis**:
   - CLI tool → reliability, error handling, documentation
   - Web app → security, performance, accessibility
   - Library → API stability, backwards compatibility
   - Data pipeline → idempotency, observability

2. **From PRD Signals**:
   - Security mentions → security-first principle
   - Performance requirements → performance budgets
   - Multi-tenant → isolation, data protection
   - User-facing → UX consistency, error messages

3. **From Brownfield Patterns** (if provided):
   - Preserve existing naming conventions
   - Maintain directory structure
   - Continue test framework usage
   - Follow established error handling

## Recommended Principle Categories

Choose 5-7 from these categories based on project needs:

| Category | Example Principle |
|----------|-------------------|
| **Code Quality** | All public functions must have docstrings |
| **Testing** | Minimum 80% test coverage for new code |
| **Dependencies** | Maximum 3 new dependencies per feature |
| **Security** | No secrets in code, all inputs validated |
| **Performance** | API responses under 200ms at p95 |
| **Documentation** | All public APIs documented before merge |
| **Breaking Changes** | Require migration path for any breaking change |
| **Error Handling** | All errors must be user-friendly and actionable |
| **Observability** | All operations must emit structured logs |
| **Accessibility** | UI must meet WCAG 2.1 AA standards |

## Key Requirements

1. **Be Concise**: Keep principles short and clear (1 sentence rationale, 2-3 bullet enforcement)
2. **Be Specific**: Principles must be measurable and enforceable
3. **Be Realistic**: Set achievable standards for the team
4. **Be Relevant**: Tailor to this specific project's needs
5. **Prioritize**: 5-7 principles max to ensure focus
6. **Focus**: ONLY principles & governance - no extensive workflow/constraint sections

## Output Instructions

CRITICAL REQUIREMENTS:
1. Output ONLY the markdown document - NO explanations, NO commentary
2. Start directly with `# Project Constitution`
3. Do NOT write things like "Here is the constitution" or "I've generated"
4. Do NOT explain what you did - just provide the raw markdown
5. Fill in all placeholders with actual content
6. Use today's date for Ratified and Last Amended
7. **KEEP IT SHORT**: Aim for ~200 lines maximum
8. **NO EXTRA SECTIONS**: Do NOT add "Constraints", "Development Workflow", "Testing Requirements", "Documentation Standards", "Code Review", or "Security" sections beyond what's in the template above

## Example Transformation

**From PRD Signals**:
- "WhatsApp integration" → Security principle (message encryption, auth)
- "Multi-tenant" → Data isolation principle
- "Voice calls" → Performance principle (latency budgets)
- "Production deployment" → Reliability principle (error handling, monitoring)

**To Constitution Principle** (SHORT VERSION):
```markdown
### 1. Security First

**Rule**: All user data encrypted at rest/transit. No secrets in code.

**Rationale**: WhatsApp handles sensitive conversations requiring strict data protection.

**Enforcement**:
- Pre-commit hooks scan for secrets
- Security checklist in code review
- Build fails on secret detection
```

Note: Keep enforcement to 2-3 bullets. Keep rationale to 1 sentence.
