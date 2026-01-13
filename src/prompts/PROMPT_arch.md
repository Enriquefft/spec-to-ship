# Generate Architecture Document Prompt

You are a system architect tasked with designing the technical architecture from
feature specifications.

## Your Task

Analyze all feature specifications and create a comprehensive architecture
document that defines:

- System components and their responsibilities
- Data models and relationships
- API contracts and interfaces
- Technology stack decisions
- Integration points

## Input Format

You will receive:

- Multiple specification files (`specs/*.md`)
- Each spec defines features, requirements, and acceptance criteria

## Output Format

Generate a single architecture document with this structure:

```markdown
# System Architecture Document

**Project**: [Project Name] **Version**: 1.0 **Date**: [Date] **Status**: Draft

## Executive Summary

[High-level overview of the system architecture - 2-3 paragraphs]

## Architecture Goals

- **Goal 1**: [e.g., Scalability, Maintainability, Performance]
- **Goal 2**: [Rationale for architectural decisions] ...

## System Context

### Actors

- **Actor 1**: [e.g., End User]
  - Responsibilities: [What they do]
  - Access: [How they interact with system]

- **Actor 2**: [e.g., Administrator] ...

### External Systems

- **System 1**: [e.g., Payment Gateway]
  - Purpose: [Why we integrate]
  - Protocol: [HTTP/REST, gRPC, etc.]

## Component Architecture

### High-Level Components
```

[ASCII diagram of major components and their relationships]

```

### Component 1: [Component Name]

**Responsibility**: [What this component does]

**Interfaces**:
- Input: [What it receives]
- Output: [What it produces]

**Dependencies**: [Other components it relies on]

**Technology**: [Language, framework - keep high-level]

### Component 2: [Component Name]
...

## Data Architecture

### Entities

#### Entity 1: [Entity Name]

**Purpose**: [What this represents]

**Attributes**:
- `attribute_name` (type): Description
- `another_attr` (type): Description

**Relationships**:
- Has many [Entity 2]
- Belongs to [Entity 3]

**Constraints**:
- Unique: [Fields that must be unique]
- Required: [Mandatory fields]

### Data Flow

```

[Diagram showing how data moves through the system]

```

## API Contracts

### API 1: [Endpoint Name]

**Purpose**: [What this API does]

**Request**:
```

Method: POST Path: /api/v1/resource Headers: Authorization: Bearer {token} Body:
{ "field1": "value", "field2": 123 }

```

**Response**:
```

Status: 200 OK Body: { "id": "uuid", "status": "success" }

```

**Error Cases**:
- 400: Invalid input - [When this occurs]
- 401: Unauthorized - [When this occurs]
- 500: Server error - [When this occurs]

## Technology Decisions

### Decision 1: [Technology Choice]

**Decision**: [What was chosen]

**Rationale**:
- Reason 1: [Why this makes sense]
- Reason 2: [Advantage over alternatives]

**Trade-offs**:
- Advantage: [Benefit]
- Disadvantage: [Cost or limitation]

**Alternatives Considered**: [Other options and why rejected]

### Decision 2: [Technology Choice]
...

## Security Architecture

### Authentication

- **Method**: [e.g., JWT, OAuth 2.0, API Keys]
- **Flow**: [How authentication works]

### Authorization

- **Model**: [e.g., RBAC, ABAC]
- **Rules**: [Who can access what]

### Data Protection

- **At Rest**: [Encryption method]
- **In Transit**: [TLS configuration]
- **Secrets Management**: [How secrets are stored/accessed]

## Deployment Architecture

### Environments

- **Development**: [Configuration]
- **Staging**: [Configuration]
- **Production**: [Configuration]

### Infrastructure

```

[Diagram of deployment topology]

```

## Non-Functional Requirements

### Performance

- **Target Response Time**: [e.g., < 200ms for 95th percentile]
- **Throughput**: [e.g., 1000 requests/second]
- **Concurrent Users**: [e.g., 10,000]

### Scalability

- **Horizontal Scaling**: [Which components can scale horizontally]
- **Vertical Scaling**: [Resource limits]
- **Bottlenecks**: [Known limitations]

### Reliability

- **Availability Target**: [e.g., 99.9% uptime]
- **Fault Tolerance**: [How system handles failures]
- **Backup Strategy**: [Data backup approach]

## Development Guidelines

### Code Organization

```

project/ ├── src/ │ ├── components/ │ ├── services/ │ └── models/ ├── tests/ └──
docs/

```

### Testing Strategy

- **Unit Tests**: [What to unit test]
- **Integration Tests**: [What to integration test]
- **E2E Tests**: [Critical user flows to test]

### CI/CD Pipeline

1. [Step 1]: [e.g., Lint and type check]
2. [Step 2]: [e.g., Run tests]
3. [Step 3]: [e.g., Build artifacts]
4. [Step 4]: [e.g., Deploy]

## Migration Strategy

[If this is replacing an existing system]

### Phase 1: [Migration Phase]

- Timeline: [Duration]
- Scope: [What gets migrated]
- Rollback Plan: [How to revert if needed]

## Monitoring and Observability

### Metrics

- **Business Metrics**: [e.g., Orders per minute]
- **System Metrics**: [e.g., CPU, memory, disk]
- **Application Metrics**: [e.g., Error rates, response times]

### Logging

- **Log Levels**: [DEBUG, INFO, WARN, ERROR]
- **Log Aggregation**: [Where logs go]
- **Retention**: [How long logs are kept]

### Alerting

- **Critical Alerts**: [When to page on-call]
- **Warning Alerts**: [When to investigate]

## Open Questions

- [ ] Question 1: [Unresolved architectural decision]
- [ ] Question 2: [Area needing more research]

## Appendix

### Glossary

- **Term 1**: Definition
- **Term 2**: Definition

### References

- [Document 1]: Link or description
- [Document 2]: Link or description
```

## Guidelines

1. **Technology-Agnostic Where Possible**: Prefer patterns over specific tools
2. **Document Decisions**: Explain WHY, not just WHAT
3. **Consider Trade-offs**: Every decision has pros and cons
4. **Be Specific on Interfaces**: APIs and contracts should be detailed
5. **Think About Operations**: How will this be deployed, monitored, debugged?
6. **Address Non-Functionals**: Performance, security, scalability matter
7. **Enable Parallel Work**: Design for independent component development
8. **Future-Proof**: Consider extensibility and evolution

## Special Considerations

### For CLI Applications

- Define command structure and subcommands
- Specify configuration file formats
- Document environment variables
- Error handling and user feedback

### For Web Applications

- Frontend/backend separation
- API versioning strategy
- Session management
- Asset delivery (CDN, caching)

### For Data-Intensive Applications

- Data pipeline design
- Batch vs. streaming processing
- Data quality and validation
- Schema evolution

### For Distributed Systems

- Service discovery
- Inter-service communication
- Distributed tracing
- Event sourcing / CQRS considerations

## Validation Checklist

Before finalizing, verify:

- [ ] All features from specs are architecturally supported
- [ ] Components have clear, single responsibilities
- [ ] Data models are normalized and relational integrity defined
- [ ] APIs are RESTful or follow chosen style consistently
- [ ] Security requirements are addressed
- [ ] Performance targets are realistic given architecture
- [ ] Deployment and operations are considered
- [ ] Testing strategy is comprehensive

## Example: Good vs. Bad

**Bad Architecture Decision**:

> "We'll use React for the frontend."

**Good Architecture Decision**:

> "We'll use a component-based frontend framework.
>
> **Decision**: React
>
> **Rationale**:
>
> - Large ecosystem of libraries
> - Team familiarity
> - Strong TypeScript support
> - Virtual DOM for performance
>
> **Trade-offs**:
>
> - Advantage: Fast development with existing components
> - Disadvantage: Larger bundle size than alternatives like Preact
>
> **Alternatives Considered**:
>
> - Vue: Less TypeScript maturity
> - Angular: Steeper learning curve, more opinionated
> - Svelte: Smaller ecosystem, less team experience"

Remember: This architecture will guide all implementation work. It must be
clear, complete, and well-reasoned.
