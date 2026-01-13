# Product Requirements Document: Task Management CLI

## Overview

We need a simple command-line task management tool that helps developers track
their daily work items. The tool should be fast, work offline, and integrate
with git repositories.

## Problem Statement

Developers often lose track of small tasks and context switches throughout the
day. Existing tools are either too heavy (requiring servers/databases) or too
simple (plain text files with no structure).

## Target Users

- Software developers working from command line
- Teams using git for version control
- Individual contributors who need personal task tracking

## Core Requirements

### Must Have

1. Add, list, and complete tasks from command line
2. Store tasks in local git repository (`.tasks/` directory)
3. Mark tasks with priority levels (high, medium, low)
4. Filter tasks by status (pending, in-progress, done)
5. Work completely offline

### Nice to Have

1. Task tagging system
2. Time tracking per task
3. Export tasks to markdown report
4. Integration with GitHub issues

## Success Criteria

- User can manage 50+ tasks without performance issues
- All operations complete in under 500ms
- Data stored in human-readable format (YAML or JSON)
- Works on Linux, macOS, and Windows (via WSL)

## Out of Scope

- Cloud sync
- Mobile apps
- Team collaboration features
- Calendar integration
