#!/usr/bin/env bash
# src/lib/versioning.sh - Plan versioning and history tracking

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"

# ==============================================================================
# Version Directory Management
# ==============================================================================

# Version storage location
VERSION_DIR=""

# versioning_init(project_root) - Initialize versioning directory
versioning_init() {
    local project_root="${1:-.}"

    VERSION_DIR="$project_root/.workflow/versions"

    # Create version directory if needed
    mkdir -p "$VERSION_DIR"

    log_debug "Version directory initialized: $VERSION_DIR"
}

# ==============================================================================
# Plan Versioning
# ==============================================================================

# versioning_snapshot_plan(plan_file, reason) - Create a versioned snapshot of the plan
versioning_snapshot_plan() {
    local plan_file="$1"
    local reason="${2:-manual}"

    if [[ ! -f "$plan_file" ]]; then
        log_error "Plan file not found: $plan_file"
        return 1
    fi

    if [[ -z "$VERSION_DIR" ]]; then
        log_error "Versioning not initialized. Call versioning_init first."
        return 1
    fi

    # Generate version ID (timestamp-based)
    local version_id
    version_id=$(date +%Y%m%d_%H%M%S)

    local plan_basename
    plan_basename=$(basename "$plan_file" .md)

    local snapshot_file="$VERSION_DIR/${plan_basename}_v${version_id}.md"
    local metadata_file="$VERSION_DIR/${plan_basename}_v${version_id}.meta"

    # Copy plan file
    cp "$plan_file" "$snapshot_file"

    # Create metadata
    cat > "$metadata_file" <<EOF
VERSION_ID=$version_id
CREATED_AT=$(date -Iseconds)
REASON=$reason
SOURCE_FILE=$plan_file
SOURCE_HASH=$(md5sum "$plan_file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
USER=${USER:-unknown}
EOF

    log_info "Plan snapshot created: v$version_id ($reason)"
    echo "$version_id"
}

# versioning_list_plans(plan_name) - List all versions of a plan
versioning_list_plans() {
    local plan_name="${1:-IMPLEMENTATION_PLAN}"

    if [[ -z "$VERSION_DIR" ]] || [[ ! -d "$VERSION_DIR" ]]; then
        echo "No versions found"
        return 1
    fi

    echo "Plan versions for: $plan_name"
    echo ""
    printf "%-20s %-25s %s\n" "VERSION" "CREATED" "REASON"
    printf "%-20s %-25s %s\n" "-------" "-------" "------"

    # Find all version files
    local found=false
    for meta_file in "$VERSION_DIR"/${plan_name}_v*.meta; do
        if [[ -f "$meta_file" ]]; then
            found=true
            local version_id created reason
            version_id=$(grep "^VERSION_ID=" "$meta_file" | cut -d= -f2)
            created=$(grep "^CREATED_AT=" "$meta_file" | cut -d= -f2)
            reason=$(grep "^REASON=" "$meta_file" | cut -d= -f2)

            # Format created date for display
            local created_display
            created_display=$(date -d "$created" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$created")

            printf "%-20s %-25s %s\n" "v$version_id" "$created_display" "$reason"
        fi
    done

    if [[ "$found" != "true" ]]; then
        echo "No versions found"
        return 1
    fi
}

# versioning_get_plan(version_id, plan_name) - Get a specific version of a plan
versioning_get_plan() {
    local version_id="$1"
    local plan_name="${2:-IMPLEMENTATION_PLAN}"

    # Remove 'v' prefix if present
    version_id="${version_id#v}"

    local snapshot_file="$VERSION_DIR/${plan_name}_v${version_id}.md"

    if [[ -f "$snapshot_file" ]]; then
        echo "$snapshot_file"
        return 0
    fi

    log_error "Version not found: v$version_id"
    return 1
}

# versioning_restore_plan(version_id, plan_file, plan_name) - Restore a plan from version
versioning_restore_plan() {
    local version_id="$1"
    local plan_file="$2"
    local plan_name="${3:-IMPLEMENTATION_PLAN}"

    # Remove 'v' prefix if present
    version_id="${version_id#v}"

    local snapshot_file="$VERSION_DIR/${plan_name}_v${version_id}.md"

    if [[ ! -f "$snapshot_file" ]]; then
        log_error "Version not found: v$version_id"
        return 1
    fi

    # Create backup of current plan first
    if [[ -f "$plan_file" ]]; then
        versioning_snapshot_plan "$plan_file" "pre-restore-backup"
    fi

    # Restore
    cp "$snapshot_file" "$plan_file"

    log_info "Plan restored from v$version_id"
}

# versioning_diff_plans(version1, version2, plan_name) - Show diff between two versions
versioning_diff_plans() {
    local version1="$1"
    local version2="$2"
    local plan_name="${3:-IMPLEMENTATION_PLAN}"

    # Remove 'v' prefix if present
    version1="${version1#v}"
    version2="${version2#v}"

    local file1="$VERSION_DIR/${plan_name}_v${version1}.md"
    local file2="$VERSION_DIR/${plan_name}_v${version2}.md"

    if [[ ! -f "$file1" ]]; then
        log_error "Version not found: v$version1"
        return 1
    fi

    if [[ ! -f "$file2" ]]; then
        log_error "Version not found: v$version2"
        return 1
    fi

    # Use diff if available, otherwise simple comparison
    if command -v diff &>/dev/null; then
        diff -u "$file1" "$file2" || true
    else
        echo "Install 'diff' for detailed comparison"
        echo "Files differ: $file1 vs $file2"
    fi
}

# ==============================================================================
# Auto-versioning Hooks
# ==============================================================================

# versioning_should_snapshot(plan_file) - Check if plan should be snapshotted
# Returns 0 if snapshot needed (file changed since last snapshot)
versioning_should_snapshot() {
    local plan_file="$1"
    local plan_name
    plan_name=$(basename "$plan_file" .md)

    if [[ -z "$VERSION_DIR" ]] || [[ ! -d "$VERSION_DIR" ]]; then
        return 0  # No versions exist, should snapshot
    fi

    # Get current hash
    local current_hash
    current_hash=$(md5sum "$plan_file" 2>/dev/null | cut -d' ' -f1)

    # Get latest version hash
    local latest_meta
    latest_meta=$(ls -t "$VERSION_DIR"/${plan_name}_v*.meta 2>/dev/null | head -1)

    if [[ -z "$latest_meta" ]]; then
        return 0  # No versions exist, should snapshot
    fi

    local latest_hash
    latest_hash=$(grep "^SOURCE_HASH=" "$latest_meta" | cut -d= -f2)

    if [[ "$current_hash" != "$latest_hash" ]]; then
        return 0  # Hashes differ, should snapshot
    fi

    return 1  # No changes
}

# versioning_auto_snapshot(plan_file, reason) - Snapshot if changed
versioning_auto_snapshot() {
    local plan_file="$1"
    local reason="${2:-auto}"

    if versioning_should_snapshot "$plan_file"; then
        versioning_snapshot_plan "$plan_file" "$reason"
    else
        log_debug "Plan unchanged, skipping snapshot"
    fi
}

# ==============================================================================
# Cleanup
# ==============================================================================

# versioning_cleanup(max_versions, plan_name) - Keep only N most recent versions
versioning_cleanup() {
    local max_versions="${1:-10}"
    local plan_name="${2:-IMPLEMENTATION_PLAN}"

    if [[ -z "$VERSION_DIR" ]] || [[ ! -d "$VERSION_DIR" ]]; then
        return 0
    fi

    # Get list of versions sorted by date (newest first)
    local versions
    mapfile -t versions < <(ls -t "$VERSION_DIR"/${plan_name}_v*.md 2>/dev/null)

    local count=${#versions[@]}

    if [[ $count -le $max_versions ]]; then
        log_debug "Version count ($count) within limit ($max_versions)"
        return 0
    fi

    # Remove old versions
    local removed=0
    for ((i=max_versions; i<count; i++)); do
        local version_file="${versions[$i]}"
        local meta_file="${version_file%.md}.meta"

        rm -f "$version_file" "$meta_file"
        ((removed++))
    done

    log_info "Cleaned up $removed old version(s)"
}
