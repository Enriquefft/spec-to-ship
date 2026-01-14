#!/bin/bash
# workflow-tui.sh - Standalone TUI script in bash (fallback)

set -euo pipefail

# Configuration
TUI_WIDTH=80
TUI_HEIGHT=24
TOP_HEIGHT=10
BOTTOM_HEIGHT=$((TUI_HEIGHT - TOP_HEIGHT - 3))
LOG_FILE="${TMPDIR:-/tmp}/workflow-tui.log.$$"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly GRAY='\033[0;90m'
readonly BOLD='\033[1m'
readonly RESET='\033[0m'
readonly REVERSE='\033[7m'

# State
current_phase=""
tasks=()
messages=()
total_tokens=0
start_time=$(date +%s)
quit=false

# Clear screen and setup
tui_init() {
    tput clear 2>/dev/null || clear
    tput civis 2>/dev/null || stty -echo 2>/dev/null || true
    
    # Trap cleanup
    trap 'tui_cleanup' EXIT INT TERM
}

tui_cleanup() {
    tput cnorm 2>/dev/null || stty echo 2>/dev/null || true
    tput sgr0 2>/dev/null || echo -ne "$RESET"
    rm -f "$LOG_FILE"
    echo ""
    echo "TUI terminated"
}

# Draw border
draw_border() {
    local x=$1
    local y=$2
    local width=$3
    local height=$4
    local title="${5:-}"
    
    # Top border
    tput cup $y $x 2>/dev/null || printf "\033[%d;%dH" $((y + 1)) $((x + 1))
    printf "┌"
    for ((i = 1; i < width - 1; i++)); do
        printf "─"
    done
    printf "┐"
    
    # Title
    if [[ -n "$title" ]]; then
        tput cup $y $((x + 2)) 2>/dev/null || printf "\033[%d;%dH" $((y + 1)) $((x + 3))
        printf "${BOLD}%s${RESET}" "$title"
    fi
    
    # Sides
    for ((i = y + 1; i < y + height - 1; i++)); do
        tput cup $i $x 2>/dev/null || printf "\033[%d;%dH" $((i + 1)) $((x + 1))
        printf "│"
        tput cup $i $((x + width - 1)) 2>/dev/null || printf "\033[%d;%dH" $((i + 1)) $((x))
        printf "│"
    done
    
    # Bottom border
    tput cup $((y + height - 1)) $x 2>/dev/null || printf "\033[%d;%dH" $((y)) $((x + 1))
    printf "└"
    for ((i = 1; i < width - 1; i++)); do
        printf "─"
    done
    printf "┘"
}

# Draw content
tui_draw() {
    # Clear screen
    tput clear 2>/dev/null || clear
    
    # Draw top pane
    draw_border 2 1 $((TUI_WIDTH - 4)) $TOP_HEIGHT "Workflow Status"
    
    # Current phase
    tput cup 2 5 2>/dev/null || printf "\033[3;5H"
    printf "${CYAN}${BOLD}Phase: ${RESET}${BOLD}%s${RESET}" "${current_phase:-"Initializing"}"
    
    # Tasks
    local task_y=4
    for task in "${tasks[@]}"; do
        if [[ $task_y -lt $((TOP_HEIGHT - 1)) ]]; then
            tput cup $task_y 5 2>/dev/null || printf "\033[%d;%dH" $((task_y + 1)) 5
            printf "  %s" "$task"
            ((task_y++))
        fi
    done
    
    # Metrics
    local elapsed=$(($(date +%s) - start_time))
    local metrics="${BLUE}Tokens: ${total_tokens} | Time: ${elapsed}s${RESET}"
    tput cup $((TOP_HEIGHT - 1)) 5 2>/dev/null || printf "\033[%d;%dH" $((TOP_HEIGHT)) 5
    printf "$metrics"
    
    # Draw bottom pane
    draw_border 2 $((TOP_HEIGHT + 1)) $((TUI_WIDTH - 4)) $BOTTOM_HEIGHT "LLM Stream"
    
    # Messages
    local msg_y=$((TOP_HEIGHT + 3))
    for ((i = ${#messages[@]} - 1; i >= 0 && i >= ${#messages[@]} - BOTTOM_HEIGHT + 4; i--)); do
        if [[ $msg_y -lt $((TUI_HEIGHT - 2)) ]]; then
            tput cup $msg_y 5 2>/dev/null || printf "\033[%d;%dH" $((msg_y + 1)) 5
            # Truncate long messages
            local msg="${messages[$i]}"
            if [[ ${#msg} -gt $((TUI_WIDTH - 10)) ]]; then
                msg="${msg:0:$((TUI_WIDTH - 13))}..."
            fi
            printf "${GRAY}%s${RESET}" "$msg"
            ((msg_y++))
        fi
    done
    
    # Status line
    tput cup $TUI_HEIGHT 2 2>/dev/null || printf "\033[%d;%dH" $((TUI_HEIGHT)) 2
    printf "${REVERSE}Ctrl+C: Quit | No TUI compiled - running in bash mode${RESET}"
}

# Process stdin for messages
process_messages() {
    while IFS= read -r line; do
        # Simple JSON parsing (not robust but good enough for demo)
        if [[ "$line" =~ \"type\":\ \"phase_start\" ]]; then
            current_phase=$(echo "$line" | grep -o '"phase":"[^"]*' | cut -d'"' -f4)
        elif [[ "$line" =~ \"type\":\ \"llm_prompt\" ]]; then
            local content=$(echo "$line" | grep -o '"content":"[^"]*' | cut -d'"' -f4)
            content="${content:0:50}..."
            messages+=("Prompt: $content")
        elif [[ "$line" =~ \"type\":\ \"llm_response\" ]]; then
            local tokens=$(echo "$line" | grep -o '"tokens":[0-9]*' | cut -d':' -f2)
            total_tokens=$((total_tokens + tokens))
            messages+=("Response: $tokens tokens")
        fi
        
        # Keep messages array bounded
        if [[ ${#messages[@]} -gt 100 ]]; then
            messages=("${messages[@]: -100}")
        fi
    done
    
    # Redraw
    tui_draw
}

# Main loop
tui_init

# Start message processor in background
exec 3< <(cat)
tail -f <&3 | process_messages &
TAIL_PID=$!

# Input loop
while [[ "$quit" != "true" ]]; do
    # Simple non-blocking read for quit
    if read -t 0.1 -n 1 2>/dev/null; then
        if [[ "$REPLY" == $'\x03' ]] || [[ "$REPLY" == "q" ]]; then
            quit=true
        fi
    fi
done

# Cleanup
kill $TAIL_PID 2>/dev/null || true