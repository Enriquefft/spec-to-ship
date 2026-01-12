#!/usr/bin/env bash
# Session caching layer for expensive computed values
# Provides both in-memory and file-based caching with TTL support

# shellcheck disable=SC2034  # Variables used by sourcing scripts

# In-memory cache storage (associative arrays)
declare -A _CACHE_VALUES=()
declare -A _CACHE_TIMESTAMPS=()
declare -A _CACHE_FILE_MTIMES=()  # For file-dependent cache invalidation

# Default TTL in seconds (5 minutes)
CACHE_DEFAULT_TTL=300

# Cache directory for file-based caching
CACHE_DIR=""

# Initialize cache directory
# Usage: cache_init [directory]
cache_init() {
    local dir="${1:-}"

    if [[ -z "$dir" ]]; then
        local git_root
        git_root="$(git rev-parse --show-toplevel 2>/dev/null)" || git_root="."
        dir="${git_root}/.workflow/cache"
    fi

    CACHE_DIR="$dir"
    mkdir -p "$CACHE_DIR" 2>/dev/null || true
}

# Get value from cache
# Usage: cache_get <key> [ttl_seconds]
# Returns: 0 if hit (value on stdout), 1 if miss
cache_get() {
    local key="$1"
    local ttl="${2:-$CACHE_DEFAULT_TTL}"
    local now timestamp age

    # Check if key exists
    if [[ ! -v "_CACHE_VALUES[$key]" ]]; then
        return 1
    fi

    # Check TTL
    now=$(date +%s)
    timestamp="${_CACHE_TIMESTAMPS[$key]:-0}"
    age=$((now - timestamp))

    if ((age > ttl)); then
        # Expired
        cache_invalidate "$key"
        return 1
    fi

    echo "${_CACHE_VALUES[$key]}"
    return 0
}

# Set value in cache
# Usage: cache_set <key> <value> [depends_on_file...]
cache_set() {
    local key="$1"
    local value="$2"
    shift 2
    local deps=("$@")
    local now file mtime

    now=$(date +%s)
    _CACHE_VALUES[$key]="$value"
    _CACHE_TIMESTAMPS[$key]="$now"

    # Track file dependencies for smart invalidation
    if ((${#deps[@]} > 0)); then
        local mtimes=""
        for file in "${deps[@]}"; do
            if [[ -f "$file" ]]; then
                mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
                mtimes+="${file}:${mtime};"
            fi
        done
        _CACHE_FILE_MTIMES[$key]="$mtimes"
    fi
}

# Invalidate specific cache entry
# Usage: cache_invalidate <key>
cache_invalidate() {
    local key="$1"

    unset "_CACHE_VALUES[$key]" 2>/dev/null || true
    unset "_CACHE_TIMESTAMPS[$key]" 2>/dev/null || true
    unset "_CACHE_FILE_MTIMES[$key]" 2>/dev/null || true
}

# Clear all cache entries
# Usage: cache_clear_all
cache_clear_all() {
    _CACHE_VALUES=()
    _CACHE_TIMESTAMPS=()
    _CACHE_FILE_MTIMES=()

    # Also clear file-based cache if initialized
    if [[ -n "$CACHE_DIR" && -d "$CACHE_DIR" ]]; then
        rm -rf "${CACHE_DIR:?}"/* 2>/dev/null || true
    fi
}

# Check if cached value is still valid based on file dependencies
# Usage: cache_is_valid <key>
# Returns: 0 if valid, 1 if invalid (file changed)
cache_is_valid() {
    local key="$1"
    local stored_mtimes file mtime current_mtime

    # No value cached
    if [[ ! -v "_CACHE_VALUES[$key]" ]]; then
        return 1
    fi

    # Check file dependencies
    stored_mtimes="${_CACHE_FILE_MTIMES[$key]:-}"
    if [[ -z "$stored_mtimes" ]]; then
        return 0  # No deps, always valid until TTL
    fi

    # Parse and check each file's mtime
    while IFS=':' read -r file mtime; do
        [[ -z "$file" ]] && continue
        # Remove trailing semicolon from mtime
        mtime="${mtime%;}"

        if [[ -f "$file" ]]; then
            current_mtime=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null || echo "0")
            if [[ "$current_mtime" != "$mtime" ]]; then
                return 1  # File changed, invalidate
            fi
        else
            return 1  # File doesn't exist anymore
        fi
    done <<< "${stored_mtimes//;/$'\n'}"

    return 0
}

# Get or compute value (memoization helper)
# Usage: cache_get_or_compute <key> <command> [ttl] [depends_on_file...]
# Example: result=$(cache_get_or_compute "gap_analysis" "_analyze_code_gap" 600 "src/")
cache_get_or_compute() {
    local key="$1"
    local compute_cmd="$2"
    local ttl="${3:-$CACHE_DEFAULT_TTL}"
    shift 3
    local deps=("$@")
    local value

    # Check cache validity including file deps
    if cache_is_valid "$key"; then
        if value=$(cache_get "$key" "$ttl"); then
            echo "$value"
            return 0
        fi
    fi

    # Compute new value
    value=$($compute_cmd)
    cache_set "$key" "$value" "${deps[@]}"
    echo "$value"
}

# File-based cache for larger values or cross-session persistence
# Usage: cache_file_get <key>
cache_file_get() {
    local key="$1"
    local cache_file ttl_file now timestamp age

    [[ -z "$CACHE_DIR" ]] && cache_init

    cache_file="${CACHE_DIR}/${key}.cache"
    ttl_file="${CACHE_DIR}/${key}.ttl"

    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi

    # Check TTL
    if [[ -f "$ttl_file" ]]; then
        now=$(date +%s)
        timestamp=$(cat "$ttl_file" 2>/dev/null || echo "0")
        age=$((now - timestamp))

        if ((age > CACHE_DEFAULT_TTL)); then
            rm -f "$cache_file" "$ttl_file" 2>/dev/null
            return 1
        fi
    fi

    cat "$cache_file"
    return 0
}

# File-based cache set
# Usage: cache_file_set <key> <value>
cache_file_set() {
    local key="$1"
    local value="$2"
    local cache_file ttl_file

    [[ -z "$CACHE_DIR" ]] && cache_init

    cache_file="${CACHE_DIR}/${key}.cache"
    ttl_file="${CACHE_DIR}/${key}.ttl"

    echo "$value" > "$cache_file"
    date +%s > "$ttl_file"
}

# File-based cache invalidation
# Usage: cache_file_invalidate <key>
cache_file_invalidate() {
    local key="$1"

    [[ -z "$CACHE_DIR" ]] && return 0

    rm -f "${CACHE_DIR}/${key}.cache" "${CACHE_DIR}/${key}.ttl" 2>/dev/null || true
}

# Cache statistics (for debugging)
# Usage: cache_stats
cache_stats() {
    local count=0 key

    for key in "${!_CACHE_VALUES[@]}"; do
        ((count++))
    done

    echo "In-memory entries: $count"

    if [[ -n "$CACHE_DIR" && -d "$CACHE_DIR" ]]; then
        local file_count
        file_count=$(find "$CACHE_DIR" -name "*.cache" 2>/dev/null | wc -l)
        echo "File-based entries: $file_count"
    fi
}

# Sorted array cache helper
# Caches sorted version of array keys
# Usage: cache_sorted_keys <cache_key> <array_name>
# Example: sorted=($(cache_sorted_keys "sorted_tasks" "PLAN_TASKS"))
cache_sorted_keys() {
    local cache_key="$1"
    local array_name="$2"
    local -n arr_ref="$array_name"
    local cached_keys

    if cached_keys=$(cache_get "$cache_key" 3600); then
        echo "$cached_keys"
        return 0
    fi

    # Compute sorted keys
    local sorted_keys
    sorted_keys=$(printf '%s\n' "${!arr_ref[@]}" | sort)
    cache_set "$cache_key" "$sorted_keys"
    echo "$sorted_keys"
}
