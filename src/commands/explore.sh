#!/usr/bin/env bash
# workflow explore - Analyze and understand existing codebases
set -euo pipefail

# Source libraries
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)}"
# shellcheck source=src/lib/common.sh
source "$LIB_DIR/common.sh"
# shellcheck source=src/lib/config.sh
source "$LIB_DIR/config.sh"
# shellcheck source=src/lib/git.sh
source "$LIB_DIR/git.sh"

# cmd_explore - Analyze codebase structure and patterns
cmd_explore() {
    local output_dir=""
    local focus=""
    local depth="standard"
    local format="markdown"

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --output|-o)
                if [[ -z "${2:-}" ]]; then
                    die "Option --output requires an argument"
                fi
                output_dir="$2"
                shift 2
                ;;
            --focus|-f)
                if [[ -z "${2:-}" ]]; then
                    die "Option --focus requires an argument"
                fi
                focus="$2"
                shift 2
                ;;
            --depth|-d)
                if [[ -z "${2:-}" ]]; then
                    die "Option --depth requires an argument"
                fi
                depth="$2"
                shift 2
                ;;
            --format)
                if [[ -z "${2:-}" ]]; then
                    die "Option --format requires an argument"
                fi
                format="$2"
                shift 2
                ;;
            --help)
                _explore_help
                return 0
                ;;
            --*)
                die "Unknown option: $1"
                ;;
            *)
                die "Unexpected argument: $1"
                ;;
        esac
    done

    # Validate depth
    case "$depth" in
        quick|standard|deep) ;;
        *)
            die "Invalid depth: $depth (must be: quick, standard, deep)"
            ;;
    esac

    # Get project root
    local project_root
    if project_root="$(git_root 2>/dev/null)"; then
        log_debug "Using git root as project root: $project_root"
    else
        project_root="$(pwd)"
        log_debug "Using current directory as project root: $project_root"
    fi

    # Set default output directory
    if [[ -z "$output_dir" ]]; then
        output_dir="$project_root/docs"
    fi
    mkdir -p "$output_dir"

    log_info "Exploring codebase: $project_root"
    log_info "Depth: $depth"
    if [[ -n "$focus" ]]; then
        log_info "Focus: $focus"
    fi
    echo ""

    # Run exploration
    local report=""

    # 1. Project structure
    log_info "Analyzing project structure..."
    report+="# Codebase Exploration Report"$'\n\n'
    report+="**Generated**: $(date -Iseconds)"$'\n'
    report+="**Project**: $project_root"$'\n'
    report+="**Depth**: $depth"$'\n\n'

    report+=$(_explore_structure "$project_root" "$depth")
    report+=$'\n\n'

    # 2. Technology detection
    log_info "Detecting technologies..."
    report+=$(_explore_technologies "$project_root")
    report+=$'\n\n'

    # 3. Code patterns (if standard or deep)
    if [[ "$depth" != "quick" ]]; then
        log_info "Analyzing code patterns..."
        report+=$(_explore_patterns "$project_root" "$focus")
        report+=$'\n\n'
    fi

    # 4. Dependencies
    log_info "Analyzing dependencies..."
    report+=$(_explore_dependencies "$project_root")
    report+=$'\n\n'

    # 5. Entry points and APIs (if deep)
    if [[ "$depth" == "deep" ]]; then
        log_info "Identifying entry points and APIs..."
        report+=$(_explore_apis "$project_root" "$focus")
        report+=$'\n\n'
    fi

    # 6. Git history insights (if available)
    if git_is_repo; then
        log_info "Analyzing git history..."
        report+=$(_explore_git_history "$project_root")
        report+=$'\n\n'
    fi

    # Write report
    local report_file="$output_dir/EXPLORATION.md"
    echo "$report" > "$report_file"

    echo ""
    log_info "${COLOR_GREEN}✓${COLOR_RESET} Exploration complete"
    log_info "Report: $report_file"

    # Summary stats
    local file_count dir_count
    file_count=$(find "$project_root" -type f -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.go" -o -name "*.rs" 2>/dev/null | wc -l)
    dir_count=$(find "$project_root" -type d -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | wc -l)

    echo ""
    echo "Summary:"
    echo "  Source files: $file_count"
    echo "  Directories:  $dir_count"
}

# _explore_structure - Analyze directory structure
_explore_structure() {
    local project_root="$1"
    local depth="$2"

    local output="## Project Structure"$'\n\n'

    # Use tree if available, otherwise find
    if command -v tree &>/dev/null; then
        local tree_depth=2
        [[ "$depth" == "deep" ]] && tree_depth=4
        [[ "$depth" == "quick" ]] && tree_depth=1

        output+='```'$'\n'
        output+=$(tree -L "$tree_depth" -I 'node_modules|.git|__pycache__|*.pyc|.venv|venv|target|dist|build' "$project_root" 2>/dev/null || echo "Unable to generate tree")
        output+=$'\n```\n'
    else
        output+='```'$'\n'
        output+=$(find "$project_root" -type d -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/__pycache__/*' | head -50 | sort)
        output+=$'\n```\n'
    fi

    echo "$output"
}

# _explore_technologies - Detect technologies and frameworks
_explore_technologies() {
    local project_root="$1"

    local output="## Technologies Detected"$'\n\n'

    # Language detection
    output+="### Languages"$'\n\n'

    local -A lang_counts
    lang_counts=()

    # Count files by extension
    while IFS= read -r ext; do
        [[ -n "$ext" ]] && ((lang_counts["$ext"]++)) || true
    done < <(find "$project_root" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o -name "*.php" \) -not -path '*/.git/*' -not -path '*/node_modules/*' 2>/dev/null | sed 's/.*\.//' | sort)

    for ext in "${!lang_counts[@]}"; do
        local lang_name
        case "$ext" in
            sh) lang_name="Bash/Shell" ;;
            py) lang_name="Python" ;;
            js) lang_name="JavaScript" ;;
            ts|tsx) lang_name="TypeScript" ;;
            go) lang_name="Go" ;;
            rs) lang_name="Rust" ;;
            java) lang_name="Java" ;;
            rb) lang_name="Ruby" ;;
            php) lang_name="PHP" ;;
            *) lang_name="$ext" ;;
        esac
        output+="- $lang_name (${lang_counts[$ext]} files)"$'\n'
    done

    # Framework detection
    output+=$'\n'"### Frameworks & Tools"$'\n\n'

    # Node.js
    if [[ -f "$project_root/package.json" ]]; then
        output+="- **Node.js** (package.json found)"$'\n'
        # Detect specific frameworks
        if grep -q '"react"' "$project_root/package.json" 2>/dev/null; then
            output+="  - React"$'\n'
        fi
        if grep -q '"vue"' "$project_root/package.json" 2>/dev/null; then
            output+="  - Vue.js"$'\n'
        fi
        if grep -q '"express"' "$project_root/package.json" 2>/dev/null; then
            output+="  - Express.js"$'\n'
        fi
        if grep -q '"next"' "$project_root/package.json" 2>/dev/null; then
            output+="  - Next.js"$'\n'
        fi
    fi

    # Python
    if [[ -f "$project_root/requirements.txt" ]] || [[ -f "$project_root/pyproject.toml" ]] || [[ -f "$project_root/setup.py" ]]; then
        output+="- **Python project**"$'\n'
        if [[ -f "$project_root/requirements.txt" ]]; then
            if grep -q 'django' "$project_root/requirements.txt" 2>/dev/null; then
                output+="  - Django"$'\n'
            fi
            if grep -q 'flask' "$project_root/requirements.txt" 2>/dev/null; then
                output+="  - Flask"$'\n'
            fi
            if grep -q 'fastapi' "$project_root/requirements.txt" 2>/dev/null; then
                output+="  - FastAPI"$'\n'
            fi
        fi
    fi

    # Go
    if [[ -f "$project_root/go.mod" ]]; then
        output+="- **Go module** (go.mod found)"$'\n'
    fi

    # Rust
    if [[ -f "$project_root/Cargo.toml" ]]; then
        output+="- **Rust/Cargo** (Cargo.toml found)"$'\n'
    fi

    # Docker
    if [[ -f "$project_root/Dockerfile" ]] || [[ -f "$project_root/docker-compose.yml" ]]; then
        output+="- **Docker**"$'\n'
    fi

    # Nix
    if [[ -f "$project_root/flake.nix" ]] || [[ -f "$project_root/shell.nix" ]]; then
        output+="- **Nix**"$'\n'
    fi

    echo "$output"
}

# _explore_patterns - Analyze code patterns
_explore_patterns() {
    local project_root="$1"
    local focus="$2"

    local output="## Code Patterns"$'\n\n'

    # Find main entry points
    output+="### Entry Points"$'\n\n'

    # Common entry point patterns
    local -a entry_points=()

    # Shell scripts
    while IFS= read -r file; do
        [[ -n "$file" ]] && entry_points+=("$file")
    done < <(find "$project_root" -maxdepth 2 -type f -name "*.sh" -executable 2>/dev/null | head -10)

    # Main files
    for pattern in "main.py" "app.py" "index.js" "index.ts" "main.go" "main.rs" "Main.java"; do
        while IFS= read -r file; do
            [[ -n "$file" ]] && entry_points+=("$file")
        done < <(find "$project_root" -name "$pattern" -not -path '*/node_modules/*' 2>/dev/null | head -5)
    done

    for ep in "${entry_points[@]}"; do
        local rel_path="${ep#$project_root/}"
        output+="- \`$rel_path\`"$'\n'
    done

    # Find exported functions/classes
    output+=$'\n'"### Key Functions/Classes"$'\n\n'

    if [[ -n "$focus" ]] && [[ -d "$project_root/$focus" ]]; then
        # Focus on specific directory
        output+="*Focused on: $focus*"$'\n\n'
        output+=$(grep -rh "^function \|^[a-z_]*() {" "$project_root/$focus" 2>/dev/null | head -20 | sed 's/^/- `/' | sed 's/$/`/')
    else
        # General scan
        output+=$(grep -rh "^function \|^[a-z_]*() {" "$project_root/src" 2>/dev/null | head -20 | sed 's/^/- `/' | sed 's/$/`/' || echo "No functions found in src/")
    fi

    echo "$output"
}

# _explore_dependencies - Analyze dependencies
_explore_dependencies() {
    local project_root="$1"

    local output="## Dependencies"$'\n\n'

    # Node.js dependencies
    if [[ -f "$project_root/package.json" ]]; then
        output+="### Node.js Dependencies"$'\n\n'
        output+='```json'$'\n'
        # Extract dependencies section
        if command -v jq &>/dev/null; then
            output+=$(jq '.dependencies // {}' "$project_root/package.json" 2>/dev/null || echo "{}")
        else
            output+=$(grep -A 50 '"dependencies"' "$project_root/package.json" | head -30)
        fi
        output+=$'\n```\n'
    fi

    # Python dependencies
    if [[ -f "$project_root/requirements.txt" ]]; then
        output+="### Python Dependencies"$'\n\n'
        output+='```'$'\n'
        output+=$(head -30 "$project_root/requirements.txt")
        output+=$'\n```\n'
    fi

    # Go dependencies
    if [[ -f "$project_root/go.mod" ]]; then
        output+="### Go Dependencies"$'\n\n'
        output+='```'$'\n'
        output+=$(grep -E "^\t" "$project_root/go.mod" | head -20)
        output+=$'\n```\n'
    fi

    echo "$output"
}

# _explore_apis - Find API endpoints and interfaces
_explore_apis() {
    local project_root="$1"
    local focus="$2"

    local output="## APIs & Interfaces"$'\n\n'

    local search_dir="$project_root"
    [[ -n "$focus" ]] && search_dir="$project_root/$focus"

    # HTTP endpoints (common patterns)
    output+="### HTTP Endpoints"$'\n\n'

    # Express.js patterns
    local express_routes
    express_routes=$(grep -rh "app\.\(get\|post\|put\|delete\|patch\)" "$search_dir" 2>/dev/null | head -15)
    if [[ -n "$express_routes" ]]; then
        output+='```javascript'$'\n'
        output+="$express_routes"
        output+=$'\n```\n'
    fi

    # Flask/FastAPI patterns
    local python_routes
    python_routes=$(grep -rh "@app\.\(route\|get\|post\|put\|delete\)" "$search_dir" 2>/dev/null | head -15)
    if [[ -n "$python_routes" ]]; then
        output+='```python'$'\n'
        output+="$python_routes"
        output+=$'\n```\n'
    fi

    # CLI commands (for this project type)
    output+="### CLI Commands"$'\n\n'
    local commands
    commands=$(find "$search_dir" -path "*/commands/*.sh" -type f 2>/dev/null | xargs -I{} basename {} .sh 2>/dev/null | sort)
    if [[ -n "$commands" ]]; then
        output+="Available commands:"$'\n'
        while IFS= read -r cmd; do
            output+="- \`$cmd\`"$'\n'
        done <<< "$commands"
    fi

    echo "$output"
}

# _explore_git_history - Analyze git history
_explore_git_history() {
    local project_root="$1"

    local output="## Git History Insights"$'\n\n'

    # Recent commits
    output+="### Recent Activity"$'\n\n'
    output+='```'$'\n'
    output+=$(cd "$project_root" && git log --oneline -10 2>/dev/null || echo "No git history")
    output+=$'\n```\n'

    # Contributors
    output+="### Top Contributors"$'\n\n'
    output+=$(cd "$project_root" && git shortlog -sn --no-merges 2>/dev/null | head -5 | sed 's/^/- /')
    output+=$'\n'

    # Most changed files
    output+=$'\n'"### Frequently Changed Files"$'\n\n'
    output+=$(cd "$project_root" && git log --pretty=format: --name-only 2>/dev/null | sort | uniq -c | sort -rn | head -10 | awk '{print "- `" $2 "` (" $1 " changes)"}')
    output+=$'\n'

    echo "$output"
}

# _explore_help - Show help
_explore_help() {
    cat <<'EOF'
USAGE:
    workflow explore [OPTIONS]

DESCRIPTION:
    Analyze and understand an existing codebase. Generates a comprehensive
    exploration report including structure, technologies, patterns, and more.

OPTIONS:
    --output, -o DIR     Output directory for report (default: docs/)
    --focus, -f PATH     Focus analysis on specific subdirectory
    --depth, -d LEVEL    Analysis depth: quick, standard, deep (default: standard)
    --format FORMAT      Output format: markdown (default: markdown)
    --help               Show this help message

DEPTH LEVELS:
    quick       Basic structure and technology detection (~5 seconds)
    standard    + Code patterns and dependencies (~15 seconds)
    deep        + API analysis and detailed patterns (~30 seconds)

EXAMPLES:
    # Quick exploration
    workflow explore --depth quick

    # Standard exploration (default)
    workflow explore

    # Deep dive focused on src/lib
    workflow explore --depth deep --focus src/lib

    # Output to specific directory
    workflow explore --output ./analysis

OUTPUT:
    Creates EXPLORATION.md with:
    - Project structure tree
    - Detected technologies and frameworks
    - Code patterns and entry points
    - Dependencies list
    - API endpoints (deep mode)
    - Git history insights

EOF
}
