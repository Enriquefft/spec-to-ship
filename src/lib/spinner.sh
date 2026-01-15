#!/usr/bin/env bash
# src/lib/spinner.sh - Minimal loading indicator for long operations

# Global state
_SPINNER_PID=""
_SPINNER_PREV_TRAP_INT=""
_SPINNER_PREV_TRAP_TERM=""

# spinner_start(message) - Start the spinner/indicator
# Arguments:
#   message - What operation is happening (e.g., "Thinking")
spinner_start() {
    local message="${1:-Working}"
    local start_time
    start_time="$(date +%s)"

    # Cleanup any existing spinner
    spinner_stop 2>/dev/null || true

    # Save existing traps
    _SPINNER_PREV_TRAP_INT="$(trap -p INT)"
    _SPINNER_PREV_TRAP_TERM="$(trap -p TERM)"

    # Check if stderr is a TTY
    if [[ -t 2 ]]; then
        # TTY mode: animated spinner
        # Pass message and start_time as arguments to avoid variable inheritance issues
        _spinner_tty_loop "$message" "$start_time" &
        _SPINNER_PID=$!
        # Setup cleanup trap
        trap '_spinner_cleanup INT' INT
        trap '_spinner_cleanup TERM' TERM
    else
        # Non-TTY: periodic log messages
        _spinner_nontty_loop "$message" "$start_time" &
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

    # Clear the spinner line if TTY
    if [[ -t 2 ]]; then
        printf '\r\033[K' >&2
    fi

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

# _spinner_cleanup(signal) - Clean up spinner on signal
_spinner_cleanup() {
    local signal="$1"

    # Stop the spinner
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
    fi

    # Clear the line
    if [[ -t 2 ]]; then
        printf '\r\033[K' >&2
    fi

    # Call previous trap handler
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

# _spinner_tty_loop(message, start_time) - Animated spinner for TTY
_spinner_tty_loop() {
    local message="$1"
    local start_time="$2"
    local dots=""
    local max_dots=5
    local show_time_after=10

    # Print immediately so user sees something
    echo >&2  # newline after previous log message
    printf '    \033[1;33m⏳ %s\033[0m' "$message" >&2

    while true; do
        sleep 0.5

        local now
        now="$(date +%s)"
        local elapsed=$((now - start_time))

        # Accumulate dots
        dots="${dots}."
        if [[ ${#dots} -gt $max_dots ]]; then
            dots="."
        fi

        # Build display string
        local display
        if [[ $elapsed -ge $show_time_after ]]; then
            display="⏳ $message$dots (${elapsed}s)"
        else
            display="⏳ $message$dots"
        fi

        # Print on same line: yellow, bold
        printf '\r\033[K    \033[1;33m%s\033[0m' "$display" >&2
    done
}

# _spinner_nontty_loop(message, start_time) - Periodic logging for non-TTY (CI)
_spinner_nontty_loop() {
    local message="$1"
    local start_time="$2"
    local interval=30

    while true; do
        sleep "$interval"
        local now
        now="$(date +%s)"
        local elapsed=$((now - start_time))
        echo "[INFO] [workflow] ...$message (${elapsed}s)" >&2
    done
}
