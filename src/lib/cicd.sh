#!/usr/bin/env bash
# src/lib/cicd.sh - CI/CD integration hooks and utilities

# Source dependencies
: "${LIB_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# shellcheck source=src/lib/common.sh
source "${LIB_DIR}/common.sh"
# shellcheck source=src/lib/constitution.sh
source "${LIB_DIR}/constitution.sh"
# shellcheck source=src/lib/checklist.sh
source "${LIB_DIR}/checklist.sh"

# ==============================================================================
# CI/CD Validation
# ==============================================================================

# cicd_validate(project_root) - Run all CI/CD validations
# Returns: 0 if all pass, non-zero with failure count
cicd_validate() {
    local project_root="${1:-.}"
    local failures=0

    echo "Running CI/CD validations..."
    echo ""

    # Constitution check
    echo -n "Constitution: "
    if constitution_validate "$project_root" >/dev/null 2>&1; then
        echo "✓ PASS"
    else
        echo "✗ FAIL"
        ((failures++))
    fi

    # Checklist check (if exists)
    local spec_dir="$project_root/specs"
    if [[ -d "$spec_dir" ]]; then
        local latest_spec_dir
        latest_spec_dir=$(find "$spec_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
        if [[ -n "$latest_spec_dir" ]]; then
            echo -n "Checklist: "
            if checklist_validate "$latest_spec_dir" "$project_root" >/dev/null 2>&1; then
                echo "✓ PASS"
            else
                echo "✗ FAIL"
                ((failures++))
            fi
        fi
    fi

    # Plan exists check
    echo -n "Plan exists: "
    if [[ -f "$project_root/docs/IMPLEMENTATION_PLAN.md" ]]; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (no IMPLEMENTATION_PLAN.md)"
        ((failures++))
    fi

    # Architecture exists check
    echo -n "Architecture exists: "
    if [[ -f "$project_root/docs/ARCHITECTURE.md" ]]; then
        echo "✓ PASS"
    else
        echo "✗ FAIL (no ARCHITECTURE.md)"
        ((failures++))
    fi

    echo ""
    if [[ $failures -eq 0 ]]; then
        echo "All validations passed ✓"
        return 0
    else
        echo "Validations failed: $failures"
        return $failures
    fi
}

# cicd_gate(project_root, gate_name) - Run specific quality gate
cicd_gate() {
    local project_root="${1:-.}"
    local gate_name="${2:-all}"

    case "$gate_name" in
        constitution)
            constitution_validate "$project_root"
            ;;
        checklist)
            local spec_dir="$project_root/specs"
            local latest_spec_dir
            latest_spec_dir=$(find "$spec_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
            if [[ -n "$latest_spec_dir" ]]; then
                checklist_validate "$latest_spec_dir" "$project_root"
            else
                log_warn "No spec directory found for checklist validation"
                return 0
            fi
            ;;
        plan)
            [[ -f "$project_root/docs/IMPLEMENTATION_PLAN.md" ]]
            ;;
        architecture)
            [[ -f "$project_root/docs/ARCHITECTURE.md" ]]
            ;;
        all)
            cicd_validate "$project_root"
            ;;
        *)
            log_error "Unknown gate: $gate_name"
            return 1
            ;;
    esac
}

# ==============================================================================
# CI/CD Reports
# ==============================================================================

# cicd_report_json(project_root) - Generate JSON report for CI systems
cicd_report_json() {
    local project_root="${1:-.}"

    local constitution_status="pass"
    local checklist_status="pass"
    local plan_status="pass"
    local arch_status="pass"

    # Run checks
    constitution_validate "$project_root" >/dev/null 2>&1 || constitution_status="fail"

    local spec_dir="$project_root/specs"
    local latest_spec_dir
    latest_spec_dir=$(find "$spec_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
    if [[ -n "$latest_spec_dir" ]]; then
        checklist_validate "$latest_spec_dir" "$project_root" >/dev/null 2>&1 || checklist_status="fail"
    else
        checklist_status="skip"
    fi

    [[ -f "$project_root/docs/IMPLEMENTATION_PLAN.md" ]] || plan_status="fail"
    [[ -f "$project_root/docs/ARCHITECTURE.md" ]] || arch_status="fail"

    # Calculate overall status
    local overall="pass"
    [[ "$constitution_status" == "fail" ]] && overall="fail"
    [[ "$checklist_status" == "fail" ]] && overall="fail"
    [[ "$plan_status" == "fail" ]] && overall="fail"
    [[ "$arch_status" == "fail" ]] && overall="fail"

    # Generate JSON
    cat <<EOF
{
  "timestamp": "$(date -Iseconds)",
  "project": "$project_root",
  "overall": "$overall",
  "gates": {
    "constitution": "$constitution_status",
    "checklist": "$checklist_status",
    "plan": "$plan_status",
    "architecture": "$arch_status"
  }
}
EOF
}

# cicd_report_markdown(project_root) - Generate Markdown report for PRs
cicd_report_markdown() {
    local project_root="${1:-.}"

    local report=""
    report+="## Workflow Quality Report"$'\n\n'
    report+="| Gate | Status |"$'\n'
    report+="|------|--------|"$'\n'

    # Constitution
    if constitution_validate "$project_root" >/dev/null 2>&1; then
        report+="| Constitution | ✅ Pass |"$'\n'
    else
        report+="| Constitution | ❌ Fail |"$'\n'
    fi

    # Checklist
    local spec_dir="$project_root/specs"
    local latest_spec_dir
    latest_spec_dir=$(find "$spec_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -1)
    if [[ -n "$latest_spec_dir" ]]; then
        if checklist_validate "$latest_spec_dir" "$project_root" >/dev/null 2>&1; then
            report+="| Checklist | ✅ Pass |"$'\n'
        else
            report+="| Checklist | ❌ Fail |"$'\n'
        fi
    else
        report+="| Checklist | ⏭️ Skip |"$'\n'
    fi

    # Plan
    if [[ -f "$project_root/docs/IMPLEMENTATION_PLAN.md" ]]; then
        report+="| Plan | ✅ Exists |"$'\n'
    else
        report+="| Plan | ❌ Missing |"$'\n'
    fi

    # Architecture
    if [[ -f "$project_root/docs/ARCHITECTURE.md" ]]; then
        report+="| Architecture | ✅ Exists |"$'\n'
    else
        report+="| Architecture | ❌ Missing |"$'\n'
    fi

    report+=$'\n'"*Generated by workflow at $(date -Iseconds)*"

    echo "$report"
}

# ==============================================================================
# GitHub Actions Integration
# ==============================================================================

# cicd_github_output(name, value) - Set GitHub Actions output
cicd_github_output() {
    local name="$1"
    local value="$2"

    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "$name=$value" >> "$GITHUB_OUTPUT"
    else
        echo "::set-output name=$name::$value"
    fi
}

# cicd_github_summary(content) - Add to GitHub Actions job summary
cicd_github_summary() {
    local content="$1"

    if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        echo "$content" >> "$GITHUB_STEP_SUMMARY"
    fi
}

# cicd_github_annotation(level, message, file, line) - Create GitHub annotation
cicd_github_annotation() {
    local level="$1"  # error, warning, notice
    local message="$2"
    local file="${3:-}"
    local line="${4:-}"

    local location=""
    [[ -n "$file" ]] && location=" file=$file"
    [[ -n "$line" ]] && location+=",line=$line"

    echo "::$level$location::$message"
}

# cicd_run_github_check(project_root) - Run checks and report to GitHub
cicd_run_github_check() {
    local project_root="${1:-.}"

    # Run validation
    local failures=0
    cicd_validate "$project_root" || failures=$?

    # Set outputs
    if [[ $failures -eq 0 ]]; then
        cicd_github_output "status" "success"
        cicd_github_output "message" "All quality gates passed"
    else
        cicd_github_output "status" "failure"
        cicd_github_output "message" "$failures quality gate(s) failed"
    fi

    # Add summary
    local summary
    summary=$(cicd_report_markdown "$project_root")
    cicd_github_summary "$summary"

    return $failures
}

# ==============================================================================
# GitLab CI Integration
# ==============================================================================

# cicd_gitlab_artifact(project_root, output_file) - Generate GitLab CI artifact
cicd_gitlab_artifact() {
    local project_root="${1:-.}"
    local output_file="${2:-workflow-report.json}"

    cicd_report_json "$project_root" > "$output_file"
    echo "Artifact generated: $output_file"
}

# ==============================================================================
# Generic CI Hooks
# ==============================================================================

# cicd_pre_commit(project_root) - Pre-commit hook
cicd_pre_commit() {
    local project_root="${1:-.}"

    log_info "Running pre-commit checks..."

    # Quick validation only
    if ! constitution_validate "$project_root" >/dev/null 2>&1; then
        log_error "Constitution validation failed"
        return 1
    fi

    log_info "Pre-commit checks passed"
    return 0
}

# cicd_pre_push(project_root) - Pre-push hook
cicd_pre_push() {
    local project_root="${1:-.}"

    log_info "Running pre-push checks..."

    # Full validation
    if ! cicd_validate "$project_root"; then
        log_error "Pre-push validation failed"
        return 1
    fi

    log_info "Pre-push checks passed"
    return 0
}

# cicd_install_hooks(project_root) - Install git hooks
cicd_install_hooks() {
    local project_root="${1:-.}"
    local hooks_dir="$project_root/.git/hooks"

    if [[ ! -d "$hooks_dir" ]]; then
        log_error "Not a git repository or hooks directory not found"
        return 1
    fi

    # Pre-commit hook
    cat > "$hooks_dir/pre-commit" <<'HOOK'
#!/usr/bin/env bash
# Workflow pre-commit hook
workflow_cmd="$(git rev-parse --show-toplevel)/src/workflow"
if [[ -x "$workflow_cmd" ]]; then
    "$workflow_cmd" ci pre-commit || exit 1
fi
HOOK
    chmod +x "$hooks_dir/pre-commit"

    # Pre-push hook
    cat > "$hooks_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
# Workflow pre-push hook
workflow_cmd="$(git rev-parse --show-toplevel)/src/workflow"
if [[ -x "$workflow_cmd" ]]; then
    "$workflow_cmd" ci pre-push || exit 1
fi
HOOK
    chmod +x "$hooks_dir/pre-push"

    log_info "Git hooks installed in $hooks_dir"
}
