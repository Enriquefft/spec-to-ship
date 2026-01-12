# Generate Specifications Prompt

You are a technical writer tasked with generating detailed feature specifications from a structured PRD.

## Your Task

For each Activity in the provided Structured PRD, generate a separate specification file that can be implemented independently.

## Input Format

You will receive a Structured PRD with:
- Audiences
- Jobs To Be Done
- Activities (with acceptance criteria)

## Output Format

Generate one specification file per Activity with this structure:

```markdown
# Feature Specification: [Activity Name]

**Priority**: [High / Medium / Low]
**Status**: Draft
**Created**: [Date]

## Overview

[Brief description of what this feature does and why it's valuable]

## User Stories

### Story 1: [User Story Title]

As a [user type],
I want to [action],
So that [benefit].

**Acceptance Criteria**:
- [ ] Criterion 1
- [ ] Criterion 2
- [ ] Criterion 3

### Story 2: [User Story Title]
...

## Functional Requirements

### Core Requirements

- **FR-001**: [Requirement description with specific behavior]
- **FR-002**: [Requirement description]
...

### Edge Cases

- **EC-001**: [Edge case scenario and expected behavior]
- **EC-002**: [Edge case scenario]
...

## Non-Functional Requirements

- **NFR-001**: [Performance, security, scalability, etc.]
- **NFR-002**: [Quality attribute]
...

## Success Criteria

How will we measure success?

- **SC-001**: [Measurable outcome]
- **SC-002**: [Measurable outcome]
...

## Dependencies

- `other-spec-filename.md` - [Description of dependency relationship]
- `another-spec.md` - [Description]
- [External systems or services needed]

**Note**: When referencing other features from the same PRD, use their kebab-case spec filenames

## Out of Scope

- [What this feature will NOT include]
- [Explicitly excluded functionality]

## Open Questions

- [Unresolved decisions]
- [Items needing clarification]

## Acceptance Scenarios

### Scenario 1: [Happy Path]

**Given**: [Initial state]
**When**: [Action performed]
**Then**: [Expected result]

### Scenario 2: [Error Case]
...
```

## Guidelines

1. **One file per Activity**: Each activity becomes a separate spec file
2. **Filename convention**: Use kebab-case: `activity-name.md`
3. **Be specific**: Requirements should be testable and unambiguous
4. **No implementation details**: Avoid mentioning languages, frameworks, or technical solutions
5. **User-centric**: Focus on user value and observable behavior
6. **Complete**: Include normal flows, edge cases, and error handling
7. **Measurable**: Success criteria must be quantifiable
8. **Traceable**: Each requirement should map to acceptance criteria

## Example Transformation

**From Structured PRD Activity**:
```
### Activity 1: Submit Expense Report

**Priority**: High

**Acceptance Criteria**:
- [ ] User can upload receipts
- [ ] System validates expense data
- [ ] Manager receives notification
```

**To Specification File** (`submit-expense-report.md`):
```markdown
# Feature Specification: Submit Expense Report

## User Stories

### Story 1: Upload Receipt

As an employee,
I want to upload receipt images with my expense report,
So that finance can verify my expenses.

**Acceptance Criteria**:
- [ ] Supports JPEG, PNG, PDF formats up to 10MB
- [ ] Shows upload progress indicator
- [ ] Validates file format before upload
- [ ] Displays thumbnail after successful upload

### Story 2: Validate Expenses
...

## Functional Requirements

- **FR-001**: System SHALL accept expense amount in USD currency
- **FR-002**: System SHALL validate expense date is within last 90 days
- **FR-003**: System SHALL require receipt attachment for expenses > $25
- **FR-004**: System SHALL send email notification to manager within 5 minutes

## Edge Cases

- **EC-001**: If receipt upload fails, system SHALL save form data and allow retry
- **EC-002**: If expense exceeds policy limit, system SHALL flag for special approval

## Success Criteria

- **SC-001**: 95% of expense reports submitted without errors
- **SC-002**: Managers notified within 5 minutes 99% of the time
```

## Key Differences from PRD

- **PRD**: High-level activities and outcomes
- **Spec**: Detailed requirements and acceptance criteria
- **PRD**: "What" and "Why"
- **Spec**: "What" in detail, still avoiding "How"

## Validation Checklist

Before outputting each specification, verify:

- [ ] All acceptance criteria from PRD are expanded
- [ ] User stories cover primary flows
- [ ] Functional requirements are testable
- [ ] Edge cases are identified
- [ ] Success criteria are measurable
- [ ] No implementation details leaked
- [ ] Dependencies are listed
- [ ] Scope is clearly bounded

## Special Instructions

- **Parallel Implementation**: Specs should be implementable independently where possible
- **Consistent Terminology**: Use terms from Structured PRD consistently
- **Clear Priorities**: Maintain priority from original Activities
- **Traceability**: Reference original Activity in spec metadata
- **Explicit Dependencies**: When one spec depends on another, reference it using kebab-case filename (e.g., `upload-receipt.md`)

Remember: These specs will be used by architects and engineers to design and build the system. They must be complete, clear, and unambiguous.
