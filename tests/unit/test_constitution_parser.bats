#!/usr/bin/env bats
# tests/unit/test_constitution_parser.bats - Constitution parser tests

load '../helpers/test_helper'

setup() {
    TEST_DIR=$(mktemp -d)
    mkdir -p "$TEST_DIR/.workflow"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "parse list format constitution" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Principles

1. **First Principle**: This is the first principle description
2. **Second Principle**: This is the second principle description
3. **Third Principle**: This is the third principle description

## Governance
Some governance text
CONST

    source src/lib/constitution.sh
    constitution_load "$TEST_DIR"
    
    [ ${#CONSTITUTION_PRINCIPLES[@]} -eq 3 ]
    [[ "${CONSTITUTION_PRINCIPLES[P1]}" =~ "First Principle" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P2]}" =~ "Second Principle" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P3]}" =~ "Third Principle" ]]
}

@test "parse heading format constitution" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Core Principles

### 1. Zero-Friction Development

**Rule**: Local development must work without any API keys

**Rationale**: Developers need rapid iteration

### 2. Type Safety First

**Rule**: All public APIs must be fully typed

### 3. Production Resilience

**Rule**: Every conversation must be recoverable

## Governance
Some text
CONST

    source src/lib/constitution.sh
    constitution_load "$TEST_DIR"
    
    [ ${#CONSTITUTION_PRINCIPLES[@]} -eq 3 ]
    [[ "${CONSTITUTION_PRINCIPLES[P1]}" =~ "Zero-Friction Development" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P1]}" =~ "Local development must work" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P2]}" =~ "Type Safety First" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P3]}" =~ "Production Resilience" ]]
}

@test "parse mixed heading variations" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Engineering Principles

### Security First

**Rule**: All endpoints must validate input

### Performance

**Rule**: P99 latency under 500ms

### Maintainability

**Rule**: Follow established patterns

## Governance
Text
CONST

    source src/lib/constitution.sh
    constitution_load "$TEST_DIR"
    
    [ ${#CONSTITUTION_PRINCIPLES[@]} -eq 3 ]
    [[ "${CONSTITUTION_PRINCIPLES[P1]}" =~ "Security First" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P2]}" =~ "Performance" ]]
    [[ "${CONSTITUTION_PRINCIPLES[P3]}" =~ "Maintainability" ]]
}

@test "validate minimum principle count" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Principles

1. **Only One**: Not enough principles

## Governance
Text
CONST

    source src/lib/constitution.sh
    run constitution_validate "$TEST_DIR"
    
    [ $status -eq 1 ]
    [[ "$output" =~ "Insufficient principles" ]]
}

@test "validate passes with 3+ principles" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Principles

1. **First**: Description with enough text to be valid
2. **Second**: Another description with enough text
3. **Third**: Yet another description with enough text

## Governance
Text
CONST

    source src/lib/constitution.sh
    run constitution_validate "$TEST_DIR"
    
    [ $status -eq 0 ]
    [[ "$output" =~ "Constitution validation passed" ]]
}

@test "validate requires governance section" {
    cat > "$TEST_DIR/.workflow/constitution.md" << 'CONST'
# Constitution

## Principles

1. **First**: Description text here for validation
2. **Second**: Description text here for validation
3. **Third**: Description text here for validation
CONST

    source src/lib/constitution.sh
    run constitution_validate "$TEST_DIR"
    
    [ $status -eq 1 ]
    [[ "$output" =~ "Missing Governance section" ]]
}
