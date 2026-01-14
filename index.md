# Source Code Index

## src/
```
src/
├── workflow                          # Main entry point for the Spec-to-Ship CLI tool
├── commands/                         # CLI command implementations
│   ├── arch.sh                      # Generate architecture document from specs
│   ├── build.sh                     # Execute autonomous build loop
│   ├── clarify.sh                   # Transform rough PRD into structured format
│   ├── config.sh                    # Manage workflow configuration
│   ├── constitution.sh              # Generate project governance principles
│   ├── ci.sh                        # CI/CD integration commands
│   ├── diff.sh                      # Show changes since last milestone
│   ├── explore.sh                   # Analyze existing codebase
│   ├── gate.sh                      # Run milestone validation
│   ├── init.sh                      # Initialize project with Spec-to-Ship structure
│   ├── plan.sh                      # Generate implementation plan
│   ├── provider.sh                  # Manage AI providers
│   ├── specs.sh                     # Generate spec files from structured PRD
│   └── status.sh                    # Show current workflow state
├── lib/                             # Core library modules
│   ├── activity.sh                  # Transparent LLM activity logging
│   ├── adaptive.sh                  # Adaptive model selection and retry logic
│   ├── agent.sh                     # Agent coordination and execution
│   ├── audit.sh                     # Audit trail and compliance tracking
│   ├── brownfield.sh                # Brownfield project analysis utilities
│   ├── cache.sh                     # Context caching and optimization
│   ├── checklist.sh                # Task checklist management
│   ├── cicd.sh                      # CI/CD pipeline integration
│   ├── claude.sh                    # Claude API client implementation
│   ├── common.sh                    # Shared utilities for logging, colors, and error handling
│   ├── config.sh                    # Configuration loading and validation
│   ├── constitution.sh             # Project constitution generation utilities
│   ├── context.sh                   # Context management for LLM interactions
│   ├── git.sh                       # Git operations and atomic commits
│   ├── hitl.sh                      # Human-in-the-loop interaction handling
│   ├── interaction.sh               # User interaction and prompt handling
│   ├── plan.sh                      # Implementation plan parsing and management
│   ├── provider.sh                  # AI provider abstraction layer
│   ├── providers/                   # AI provider implementations
│   │   ├── claude.sh                # Claude API provider
│   │   ├── copilot.sh               # GitHub Copilot provider
│   │   ├── gemini.sh                # Google Gemini provider
│   │   ├── opencode.sh              # OpenCode provider
│   │   └── opencode_fixed.sh        # Fixed OpenCode provider implementation
│   ├── spinner.sh                   # CLI spinner animations
│   ├── state.sh                     # Workflow state management
│   ├── tempfiles.sh                 # Temporary file management
│   ├── tools.sh                     # Tool integration and execution
│   └── versioning.sh                # Version and milestone tracking
└── prompts/                         # LLM prompt templates
    ├── PROMPT_arch.md               # Architecture generation prompt
    ├── PROMPT_build.md              # Build phase execution prompt
    ├── PROMPT_clarify.md            # Requirements clarification prompt
    ├── PROMPT_constitution.md      # Constitution generation prompt
    ├── PROMPT_plan.md               # Implementation planning prompt
    ├── PROMPT_plan_compact.md       # Compact planning prompt
    ├── PROMPT_specs.md              # Specification generation prompt
    ├── system_agent.md              # System agent behavior prompt
    └── PROMPT_constitution.md       # Project constitution prompt
```

## File Descriptions

### Main Entry Point
- **workflow**: Main CLI entry point that routes to subcommands and handles global options

### Commands (src/commands/)
- **arch.sh**: Generates system architecture documentation from specification files
- **build.sh**: Executes the autonomous build loop with task management and validation
- **clarify.sh**: Transforms rough PRD documents into structured requirements format
- **config.sh**: Manages workflow configuration settings and validation
- **constitution.sh**: Generates project governance principles and constitution
- **ci.sh**: Provides CI/CD pipeline integration commands and utilities
- **diff.sh**: Shows changes made since the last milestone or commit
- **explore.sh**: Analyzes existing codebases for brownfield development
- **gate.sh**: Runs milestone validation and generates gate reports
- **init.sh**: Initializes new projects with Spec-to-Ship directory structure
- **plan.sh**: Generates detailed implementation plans from specs and architecture
- **provider.sh**: Manages AI provider configurations and testing
- **specs.sh**: Generates specification files from structured PRD documents
- **status.sh**: Displays current workflow state and progress information

### Core Libraries (src/lib/)
- **activity.sh**: Provides transparent logging of LLM activities and operations
- **adaptive.sh**: Implements adaptive model selection and retry escalation logic
- **agent.sh**: Coordinates agent execution and manages agent lifecycle
- **audit.sh**: Maintains audit trails and ensures compliance tracking
- **brownfield.sh**: Utilities for analyzing and working with existing codebases
- **cache.sh**: Manages context caching for optimized LLM interactions
- **checklist.sh**: Handles task checklist creation and validation
- **cicd.sh**: Integrates with CI/CD pipelines and deployment workflows
- **claude.sh**: Claude API client with streaming and tool support
- **common.sh**: Shared utilities including logging, colors, and error handling
- **config.sh**: Loads, validates, and manages configuration settings
- **constitution.sh**: Utilities for generating project constitutions
- **context.sh**: Manages context collection for LLM prompts
- **git.sh**: Git operations including atomic commits and repository management
- **hitl.sh**: Human-in-the-loop interaction handling and prompts
- **interaction.sh**: User interaction utilities and prompt handling
- **plan.sh**: Parses and manages implementation plans and milestones
- **provider.sh**: Abstraction layer for multiple AI providers
- **providers/**: Directory containing specific AI provider implementations
- **spinner.sh**: CLI spinner animations for long-running operations
- **state.sh**: Workflow state persistence and management
- **tempfiles.sh**: Temporary file creation and cleanup utilities
- **tools.sh**: Tool integration and execution framework
- **versioning.sh**: Version tracking and milestone management

### AI Providers (src/lib/providers/)
- **claude.sh**: Anthropic Claude API provider implementation
- **copilot.sh**: GitHub Copilot provider integration
- **gemini.sh**: Google Gemini API provider
- **opencode.sh**: OpenCode provider implementation
- **opencode_fixed.sh**: Fixed version of OpenCode provider with bug fixes

### Prompts (src/prompts/)
- **PROMPT_arch.md**: Template for generating system architecture documents
- **PROMPT_build.md**: Template for build phase task execution
- **PROMPT_clarify.md**: Template for requirements clarification
- **PROMPT_constitution.md**: Template for project constitution generation
- **PROMPT_plan.md**: Template for implementation planning
- **PROMPT_plan_compact.md**: Compact version of planning prompt
- **PROMPT_specs.md**: Template for specification generation
- **system_agent.md**: System prompt defining agent behavior and constraints