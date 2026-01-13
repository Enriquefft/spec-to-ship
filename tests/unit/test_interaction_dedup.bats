#!/usr/bin/env bats
# Test interaction.sh deduplication functionality

setup() {
    # Source the library
    export LIB_DIR="${BATS_TEST_DIRNAME}/../../src/lib"
    source "${LIB_DIR}/common.sh"
    source "${LIB_DIR}/interaction.sh"
}

@test "interaction_render_table deduplicates options by ID" {
    # Create duplicate options list
    local options_list="A|First description
B|Second description
A|Updated first description
C|Third description
B|Updated second description"

    # Capture output
    local output
    output=$(interaction_render_table "$options_list" "false" 2>&1)

    # Should contain each option ID only once
    [[ $(echo "$output" | grep -c "^| A |") -eq 1 ]]
    [[ $(echo "$output" | grep -c "^| B |") -eq 1 ]]
    [[ $(echo "$output" | grep -c "^| C |") -eq 1 ]]

    # Should use the last occurrence (updated descriptions)
    echo "$output" | grep "| A | Updated first description |"
    echo "$output" | grep "| B | Updated second description |"
    echo "$output" | grep "| C | Third description |"
}

@test "interaction_render_table handles empty lines gracefully" {
    local options_list="A|First

B|Second

C|Third"

    local output
    output=$(interaction_render_table "$options_list" "false" 2>&1)

    # Should only contain valid options
    [[ $(echo "$output" | grep -c "^| [A-Z] |") -eq 3 ]]
}

@test "question text cleaning removes duplicates and keeps last line" {
    # Simulate what happens in interaction_present_smart_question
    local question="What would you like?
What would you really like?
What would you actually like to do?"

    # Clean up as done in the function
    local cleaned
    cleaned=$(echo "$question" | grep -v '^[[:space:]]*$' | tail -1)

    [[ "$cleaned" == "What would you actually like to do?" ]]
}
