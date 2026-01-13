# AI Provider Model Capabilities and Mapping System

## Overview

This document analyzes the capabilities of major AI providers and designs a
flexible, capability-based model mapping system for the spec-to-ship workflow.

## 1. Major AI Provider Model Tiers

### Claude (Anthropic)

| Model      | Capability Tier | Strengths                                                                                           | Use Cases                                                                                   |
| ---------- | --------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Opus 4.5   | High            | - State-of-the-art reasoning<br>- Complex coding tasks<br>- Autonomous operation<br>- Deep analysis | - Architecture design<br>- Complex planning<br>- Code generation<br>- Requirements analysis |
| Sonnet 4.5 | Medium          | - Balanced performance<br>- Good reasoning<br>- Cost-effective<br>- Fast responses                  | - Technical writing<br>- Code review<br>- Debugging<br>- Documentation                      |
| Haiku 4.5  | Low             | - Fastest responses<br>- Lowest cost<br>- Simple tasks<br>- High throughput                         | - Text classification<br>- Simple formatting<br>- Quick lookups<br>- Basic validation       |

### OpenAI

| Model                   | Capability Tier | Strengths                                                              | Use Cases                                                                 |
| ----------------------- | --------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| GPT-5.2 / GPT-5.1 Codex | High            | - Advanced reasoning<br>- Superior coding<br>- Complex problem-solving | - Complex build tasks<br>- Architecture decisions<br>- Advanced debugging |
| o1 / o1-pro             | High            | - Deep reasoning<br>- Step-by-step thinking<br>- Problem decomposition | - Planning phase<br>- Complex architecture<br>- Dependency analysis       |
| GPT-4o                  | Medium          | - Multimodal<br>- Good balance<br>- Widely adopted                     | - Specs generation<br>- Code generation<br>- Documentation                |
| GPT-4o-mini / o1-mini   | Medium-Low      | - Faster responses<br>- Cost-effective<br>- Good for structured tasks  | - Simple coding<br>- Review tasks<br>- Gate validation                    |
| GPT-3.5 Turbo           | Low             | - Fastest<br>- Cheapest<br>- Basic tasks                               | - Text processing<br>- Simple formatting<br>- Basic queries               |

### Google (Gemini)

| Model            | Capability Tier | Strengths                                                                         | Use Cases                                                               |
| ---------------- | --------------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------- |
| Gemini 3 Pro     | High            | - Large context (1M tokens)<br>- Multimodal understanding<br>- Advanced reasoning | - Large codebase analysis<br>- Complex documentation<br>- System design |
| Gemini 3 Flash   | Medium          | - Fast and efficient<br>- Good reasoning<br>- Cost-effective                      | - Code generation<br>- Documentation<br>- Testing                       |
| Gemini 2.5 Pro   | Medium-High     | - Strong performance<br>- Good for agentic tasks                                  | - Build automation<br>- Autonomous coding                               |
| Gemini 2.5 Flash | Medium-Low      | - Fast responses<br>- Cost-effective                                              | - Simple coding tasks<br>- Validation                                   |

### OpenCode

OpenCode is not a model provider but an AI coding agent that:

- Supports 75+ LLM providers via AI SDK
- Provides a unified interface for terminal-based AI assistance
- Offers "OpenCode Zen" - curated models tested for coding tasks
- Supports local models via LM Studio and similar tools

Recommended models for OpenCode:

- GPT 5.2 / GPT 5.1 Codex
- Claude Opus 4.5 / Sonnet 4.5
- Minimax M2.1
- Gemini 3 Pro

## 2. Workflow Phase Complexity Analysis

### Clarify Phase

- **Requirements**: High reasoning, question generation, understanding ambiguous
  requirements
- **Complexity**: Medium-High
- **Capability Needed**: Medium to High

### Specs Phase

- **Requirements**: Technical writing, structured output, attention to detail
- **Complexity**: Medium
- **Capability Needed**: Medium

### Arch Phase

- **Requirements**: System design, complex reasoning, technical decisions,
  trade-offs
- **Complexity**: High
- **Capability Needed**: High

### Plan Phase

- **Requirements**: Task breakdown, dependency mapping, complex organization
- **Complexity**: High
- **Capability Needed**: High

### Build Phase

- **Requirements**: Code generation, debugging, problem-solving, iterative work
- **Complexity**: Variable (Simple to High)
- **Capability Needed**: Medium for simple tasks, High for complex

### Gate Phase

- **Requirements**: Validation, analysis, pattern recognition
- **Complexity**: Low-Medium
- **Capability Needed**: Low-Medium

## 3. Capability-Based Model Mapping System

### Abstract Capability Levels

```yaml
capability_levels:
  high: "Advanced reasoning, complex problem-solving, autonomous operation"
  medium: "Balanced performance, structured tasks, moderate complexity"
  low: "Fast responses, simple tasks, high throughput"
```

### Phase Capability Requirements

```yaml
phase_requirements:
  clarify: medium
  specs: medium
  arch: high
  plan: high
  build:
    primary: high
    secondary: medium
  gate: low
  feedback: low
```

### Provider Model Mappings

```yaml
provider_mappings:
  anthropic:
    high: "opus-4.5"
    medium: "sonnet-4.5"
    low: "haiku-4.5"

  openai:
    high: ["gpt-5.2", "gpt-5.1-codex", "o1", "o1-pro"]
    medium: ["gpt-4o", "gpt-4o-mini", "o1-mini"]
    low: ["gpt-3.5-turbo"]

  google:
    high: ["gemini-3-pro", "gemini-2.5-pro"]
    medium: ["gemini-3-flash", "gemini-2.5-flash"]
    low: ["gemini-1.5-flash"]

  opencode:
    high: ["gpt-5.2", "gpt-5.1-codex", "claude-opus-4.5"]
    medium: ["claude-sonnet-4.5", "gemini-3-pro", "minimax-m2.1"]
    low: ["gpt-4o-mini", "gemini-3-flash"]
```

### Configuration Structure

```yaml
# .workflow/config.sh (extended)
# Provider selection
PROVIDER="anthropic"  # Default provider
FALLBACK_PROVIDERS=["openai", "google"]  # Fallback chain

# Capability-based model selection
MODEL_CLARIFY="medium"
MODEL_SPECS="medium"
MODEL_ARCH="high"
MODEL_PLAN="high"
MODEL_BUILD_PRIMARY="high"
MODEL_BUILD_SECONDARY="medium"
MODEL_GATE="low"
MODEL_FEEDBACK="low"

# Provider-specific overrides (optional)
PROVIDER_OVERRIDES:
  anthropic:
    high: "opus-4.5"
    medium: "sonnet-4.5"
    low: "haiku-4.5"
  openai:
    high: "o1-pro"
    medium: "gpt-4o"
    low: "gpt-4o-mini"
```

## 4. Implementation Design

### Model Resolution Logic

```bash
# Pseudocode for model selection
function resolve_model_for_phase(phase, provider=null) {
    # Get required capability for phase
    capability = PHASE_REQUIREMENTS[phase]

    # Handle build phase special case
    if phase == "build" {
        capability = task_complexity ? "high" : "medium"
    }

    # Check provider-specific overrides first
    if provider && PROVIDER_OVERRIDES[provider][capability] {
        return PROVIDER_OVERRIDES[provider][capability]
    }

    # Fall back to provider's default mapping
    return PROVIDER_MAPPINGS[provider][capability][0]  # First model in list
}
```

### Provider Abstraction Layer

```bash
# Generic API call abstraction
function call_model(provider, model, prompt, options={}) {
    switch provider {
        case "anthropic":
            return call_anthropic(model, prompt, options)
        case "openai":
            return call_openai(model, prompt, options)
        case "google":
            return call_google(model, prompt, options)
        case "opencode":
            return call_opencode(model, prompt, options)
        default:
            error "Unsupported provider: $provider"
    }
}
```

### Fallback Strategy

```bash
function execute_with_fallback(phase, prompt, options={}) {
    providers = [PROVIDER] + FALLBACK_PROVIDERS

    for provider in providers {
        model = resolve_model_for_phase(phase, provider)

        try {
            result = call_model(provider, model, prompt, options)
            log_info "Successfully executed $phase using $provider/$model"
            return result
        } catch error {
            log_warn "Failed to execute $phase with $provider/$model: $error"
            continue
        }
    }

    error "All providers failed for phase: $phase"
}
```

## 5. Migration Path

### Phase 1: Extend Current Configuration

- Add provider field to config
- Add capability-based model selection
- Maintain backward compatibility

### Phase 2: Implement Provider Abstraction

- Create provider interface
- Implement provider-specific adapters
- Add fallback mechanism

### Phase 3: Advanced Features

- Dynamic model selection based on task complexity
- Cost optimization based on usage patterns
- Performance tracking and automatic tuning

## 6. Benefits

1. **Flexibility**: Easy to switch between providers or use multiple
2. **Future-Proof**: New providers/models can be added without code changes
3. **Cost Optimization**: Use appropriate capability level for each phase
4. **Resilience**: Fallback providers ensure continuity
5. **Consistency**: Abstract capability levels maintain workflow intent

## 7. Example Configurations

### Cost-Optimized Setup

```yaml
PROVIDER: "openai"
MODEL_ARCH: "high" # Uses GPT-4o for complex tasks
MODEL_SPECS: "medium" # Uses GPT-4o-mini for documentation
MODEL_GATE: "low" # Uses GPT-3.5 for validation
```

### Performance-Optimized Setup

```yaml
PROVIDER: "anthropic"
FALLBACK_PROVIDERS: ["openai"]
# All phases use optimal Claude models
```

### Hybrid Setup

```yaml
PROVIDER: "anthropic"
PROVIDER_OVERRIDES:
  anthropic:
    high: "opus-4.5"
    medium: "sonnet-4.5"
  openai:
    high: "o1-pro" # Use OpenAI for planning
```

This system provides a robust foundation for managing AI model capabilities
across providers while maintaining the workflow's specific requirements for each
phase.
