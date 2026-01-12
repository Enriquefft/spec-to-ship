#!/usr/bin/env bash
# Centralized temporary file management
# Ensures all temp files are tracked and cleaned up properly

# shellcheck disable=SC2034  # Variables used by sourcing scripts

# Global array to track temp files
declare -a _TEMPFILES_TRACKED=()

# Flag to track if cleanup trap is registered
_TEMPFILES_TRAP_SET=false

# Create a tracked temporary file
# Usage: tempfile_create [suffix]
# Returns: Path to the temporary file
tempfile_create() {
    local suffix="${1:-}"
    local temp_file

    if [[ -n "$suffix" ]]; then
        temp_file="$(mktemp --suffix="$suffix")"
    else
        temp_file="$(mktemp)"
    fi

    _TEMPFILES_TRACKED+=("$temp_file")
    _tempfiles_ensure_trap

    echo "$temp_file"
}

# Create a tracked temporary directory
# Usage: tempdir_create [suffix]
# Returns: Path to the temporary directory
tempdir_create() {
    local suffix="${1:-}"
    local temp_dir

    if [[ -n "$suffix" ]]; then
        temp_dir="$(mktemp -d --suffix="$suffix")"
    else
        temp_dir="$(mktemp -d)"
    fi

    _TEMPFILES_TRACKED+=("$temp_dir")
    _tempfiles_ensure_trap

    echo "$temp_dir"
}

# Manually remove a specific tracked temp file/dir
# Usage: tempfile_remove <path>
tempfile_remove() {
    local target="$1"
    local i

    # Remove from tracking array
    for i in "${!_TEMPFILES_TRACKED[@]}"; do
        if [[ "${_TEMPFILES_TRACKED[$i]}" == "$target" ]]; then
            unset '_TEMPFILES_TRACKED[$i]'
            break
        fi
    done

    # Actually remove the file/dir
    if [[ -d "$target" ]]; then
        rm -rf "$target" 2>/dev/null || true
    elif [[ -f "$target" ]]; then
        rm -f "$target" 2>/dev/null || true
    fi
}

# Clean up all tracked temp files
# Usage: tempfiles_cleanup
tempfiles_cleanup() {
    local item

    for item in "${_TEMPFILES_TRACKED[@]}"; do
        [[ -z "$item" ]] && continue

        if [[ -d "$item" ]]; then
            rm -rf "$item" 2>/dev/null || true
        elif [[ -f "$item" ]]; then
            rm -f "$item" 2>/dev/null || true
        fi
    done

    _TEMPFILES_TRACKED=()
}

# Get count of tracked temp files
# Usage: tempfiles_count
tempfiles_count() {
    local count=0
    local item

    for item in "${_TEMPFILES_TRACKED[@]}"; do
        [[ -n "$item" ]] && ((count++))
    done

    echo "$count"
}

# List all tracked temp files (for debugging)
# Usage: tempfiles_list
tempfiles_list() {
    local item

    for item in "${_TEMPFILES_TRACKED[@]}"; do
        [[ -n "$item" ]] && echo "$item"
    done
}

# Internal: Ensure cleanup trap is set
_tempfiles_ensure_trap() {
    if [[ "$_TEMPFILES_TRAP_SET" == "false" ]]; then
        # Chain with existing EXIT trap if any
        local existing_trap
        existing_trap=$(trap -p EXIT | sed "s/trap -- '\\(.*\\)' EXIT/\\1/")

        if [[ -n "$existing_trap" ]]; then
            # shellcheck disable=SC2064
            trap "tempfiles_cleanup; $existing_trap" EXIT
        else
            trap 'tempfiles_cleanup' EXIT
        fi

        _TEMPFILES_TRAP_SET=true
    fi
}

# Atomic file update helper
# Creates a temp file, lets caller write to it, then atomically moves to target
# Usage: atomic_write <target_file> <command_to_generate_content>
# Example: atomic_write "/path/to/file" "sed 's/old/new/' /path/to/file"
atomic_write() {
    local target="$1"
    shift
    local temp_file

    temp_file="$(tempfile_create)"

    # Execute the content-generating command, writing to temp file
    if "$@" > "$temp_file"; then
        mv "$temp_file" "$target"
        tempfile_remove "$temp_file"  # Already moved, remove from tracking
        return 0
    else
        tempfile_remove "$temp_file"
        return 1
    fi
}

# Atomic file update with stdin
# Usage: echo "content" | atomic_write_stdin <target_file>
atomic_write_stdin() {
    local target="$1"
    local temp_file

    temp_file="$(tempfile_create)"

    if cat > "$temp_file"; then
        mv "$temp_file" "$target"
        tempfile_remove "$temp_file"
        return 0
    else
        tempfile_remove "$temp_file"
        return 1
    fi
}
