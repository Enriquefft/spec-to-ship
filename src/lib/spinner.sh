#!/usr/bin/env bash
# src/lib/spinner.sh - Minimal loading indicator for long operations

# Global state
_SPINNER_PID=""
_SPINNER_MESSAGE=""
_SPINNER_START_TIME=""
_SPINNER_PREV_TRAP_INT=""
_SPINNER_PREV_TRAP_TERM=""

# spinner_is_tty() - Check if stderr is a TTY
spinner_is_tty() {
    [[ -t 2 ]]
}

# spinner_start(message) - Start the spinner/indicator
# Arguments:
#   message - What operation is happening (e.g., "Thinking")
spinner_start() {
    local message="${1:-Working}"

    # Cleanup any existing spinner
    spinner_stop 2>/dev/null || true

    _SPINNER_MESSAGE="$message"
    _SPINNER_START_TIME="$(date +%s)"

    # Save existing traps
    _SPINNER_PREV_TRAP_INT="$(trap -p INT)"
    _SPINNER_PREV_TRAP_TERM="$(trap -p TERM)"

    if spinner_is_tty; then
        _spinner_tty_loop &
        _SPINNER_PID=$!
        # Setup cleanup trap
        trap '_spinner_cleanup_and_chain INT' INT
        trap '_spinner_cleanup_and_chain TERM' TERM
    else
        # Non-TTY: Log periodic updates in background
        _spinner_nontty_loop &
        _SPINNER_PID=$!
    fi
}

# spinner_stop() - Stop the spinner and clean up
spinner_stop() {
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi

    if spinner_is_tty && [[ -n "$_SPINNER_MESSAGE" ]]; then
        # Clear the spinner line
        printf '\r\033[K' >&2
    fi

    _SPINNER_MESSAGE=""
    _SPINNER_START_TIME=""

    # Restore previous traps
    if [[ -n "$_SPINNER_PREV_TRAP_INT" ]]; then
        eval "$_SPINNER_PREV_TRAP_INT"
    else
        trap - INT
    fi
    if [[ -n "$_SPINNER_PREV_TRAP_TERM" ]]; then
        eval "$_SPINNER_PREV_TRAP_TERM"
    else
        trap - TERM
    fi

    _SPINNER_PREV_TRAP_INT=""
    _SPINNER_PREV_TRAP_TERM=""
}

# _spinner_cleanup_and_chain(signal) - Clean up and call previous trap
_spinner_cleanup_and_chain() {
    local signal="$1"

    # Stop the spinner first
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi

    # Clear the line
    if spinner_is_tty; then
        printf '\r\033[K' >&2
    fi

    # Call previous trap handler if it existed
    case "$signal" in
        INT)
            if [[ -n "$_SPINNER_PREV_TRAP_INT" ]]; then
                eval "$_SPINNER_PREV_TRAP_INT"
            fi
            ;;
        TERM)
            if [[ -n "$_SPINNER_PREV_TRAP_TERM" ]]; then
                eval "$_SPINNER_PREV_TRAP_TERM"
            fi
            ;;
    esac
}

# _spinner_tty_loop() - Internal: animated dots for TTY
_spinner_tty_loop() {
    local dots=""
    local max_dots=5
    local interval=1
    local show_time_after=10

    while true; do
        local elapsed=$(($(date +%s) - _SPINNER_START_TIME))

        # Accumulate dots, reset after max
        dots="${dots}."
        if [[ ${#dots} -gt $max_dots ]]; then
            dots="."
        fi

        # Build display string
        local display
        if [[ $elapsed -ge $show_time_after ]]; then
            display="$_SPINNER_MESSAGE $dots (${elapsed}s)"
        else
            display="$_SPINNER_MESSAGE $dots"
        fi

        # Print on same line: indented, gray
        printf '\r\033[K    \033[0;90m%s\033[0m' "$display" >&2

        sleep "$interval"
    done
}

# _spinner_nontty_loop() - Internal: periodic logging for non-TTY
_spinner_nontty_loop() {
    local interval=30  # Log every 30 seconds in CI

    while true; do
        sleep "$interval"
        local elapsed=$(($(date +%s) - _SPINNER_START_TIME))
        # Simple progress message without colors for non-TTY
        echo "[INFO] [workflow] ...${_SPINNER_MESSAGE} (${elapsed}s)" >&2
    done
}
