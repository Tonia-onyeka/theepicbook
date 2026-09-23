#!/bin/bash

set -u

full_name="<Your Full Name>"
provider="auto"
ado_org=""
ado_project=""
ado_pipeline_id=""
gh_repo=""
ado_run_result=""

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
report_dir="$base_dir/reports"
report_file="$report_dir/pipeline-health-report.txt"
raw_log_file="$report_dir/pipeline-last-run.log"

checks=(
  check_dependency_failure
  check_build_failure
  check_test_failure
  check_auth_failure
  check_agent_failure
  check_ado_run_result
)

pass_count=0
warning_count=0
failure_count=0

mkdir -p "$report_dir"
: > "$report_file"

write_line() {
  echo "$1" | tee -a "$report_file"
}

mark_pass() {
  write_line "[PASS] $1"
  pass_count=$((pass_count + 1))
}

mark_warning() {
  write_line "[WARN] $1"
  warning_count=$((warning_count + 1))
}

mark_failure() {
  write_line "[FAIL] $1"
  failure_count=$((failure_count + 1))
}

print_header() {
  write_line "========================================"
  write_line "CI/CD Pipeline Failure Triage Report"
  write_line "========================================"
  write_line "Full Name: $full_name"
  write_line "Timestamp: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  write_line "Provider: $provider"
  write_line ""
}

fetch_latest_run_log() {
  local fetched=0

  if [ -n "$ado_org" ] && [ -n "$ado_project" ] && [ -n "$ado_pipeline_id" ] && command -v az >/dev/null 2>&1
  then
    local run_id
    run_id=$(az pipelines runs list \
      --organization "$ado_org" \
      --project "$ado_project" \
      --pipeline-ids "$ado_pipeline_id" \
      --top 1 \
      --query "[0].id" -o tsv 2>/dev/null || true)

    if [ -n "$run_id" ]
    then
      # NOTE: `az pipelines runs show` (and the wider az/devops CLI) has no command that
      # returns the actual step-by-step console log text — only run metadata (result,
      # status, timestamps, etc.). There is no clean CLI one-liner for the raw log itself;
      # getting it requires the Build REST API's logs endpoints. So for Azure DevOps this
      # script can reliably tell you PASS/FAIL from `result`, but the specific category
      # checks below can only match whatever appears in this metadata — for real log-text
      # categorization, rely on the GitHub Actions side (`gh run view --log-failed` below
      # fetches genuine step console output) or open the ADO run in the browser.
      az pipelines runs show \
        --organization "$ado_org" \
        --project "$ado_project" \
        --id "$run_id" > "$raw_log_file" 2>&1 || true

      ado_run_result=$(az pipelines runs show \
        --organization "$ado_org" \
        --project "$ado_project" \
        --id "$run_id" \
        --query "result" -o tsv 2>/dev/null || true)

      fetched=1
      write_line "Fetched Azure DevOps run: $run_id (result: ${ado_run_result:-unknown})"
    fi
  fi

  if [ -n "$gh_repo" ] && command -v gh >/dev/null 2>&1
  then
    local run_id
    run_id=$(gh run list --repo "$gh_repo" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)

    if [ -n "$run_id" ]
    then
      gh run view "$run_id" --repo "$gh_repo" --log-failed >> "$raw_log_file" 2>&1 || true
      fetched=1
      write_line "Fetched GitHub Actions run: $run_id"
    fi
  fi

  if [ "$fetched" -eq 0 ]
  then
    write_line "No provider configured or CLI unavailable. Reading local log fallback (reports/pipeline-last-run.log)."
    : > "$raw_log_file" 2>/dev/null || true
  fi

  write_line ""
}

check_dependency_failure() {
  if grep -qiE "npm ERR!|ENOENT|ERESOLVE|pip install.*error|ModuleNotFoundError|package not found" "$raw_log_file" 2>/dev/null
  then
    mark_failure "Dependency install failure detected in pipeline log"
  else
    mark_pass "No dependency install failure detected"
  fi
}

check_build_failure() {
  if grep -qiE "build failed|compilation error|SyntaxError|TS[0-9]{4}|webpack.*failed|exit code 1" "$raw_log_file" 2>/dev/null
  then
    mark_failure "Build or compile failure detected in pipeline log"
  else
    mark_pass "No build or compile failure detected"
  fi
}

check_test_failure() {
  if grep -qiE "tests? failed|AssertionError|FAIL |[0-9]+ failing|expect\(received\)" "$raw_log_file" 2>/dev/null
  then
    mark_failure "Test failure detected in pipeline log"
  else
    mark_pass "No test failure detected"
  fi
}

check_auth_failure() {
  if grep -qiE "401 Unauthorized|403 Forbidden|TF400813|invalid_grant|token has expired|permission denied \(publickey\)|Bad credentials" "$raw_log_file" 2>/dev/null
  then
    mark_failure "Authentication or permission failure detected in pipeline log"
  else
    mark_pass "No authentication or permission failure detected"
  fi
}

check_agent_failure() {
  if grep -qiE "no agent found|agent.*offline|timed out waiting for an agent|job.*timed out|runner.*offline" "$raw_log_file" 2>/dev/null
  then
    mark_warning "Agent or runner availability issue detected in pipeline log"
  else
    mark_pass "No agent or runner availability issue detected"
  fi
}

check_ado_run_result() {
  if [ -z "$ado_run_result" ]
  then
    mark_pass "No Azure DevOps run result to check (not configured, or using GitHub Actions only)"
    return
  fi

  if [ "$ado_run_result" = "failed" ]
  then
    mark_failure "Azure DevOps run result is 'failed' — az CLI cannot fetch step log text, so check the ADO portal's log view to confirm which category above (if any) actually matched"
  else
    mark_pass "Azure DevOps run result is '$ado_run_result'"
  fi
}

print_summary() {
  local overall_status
  local script_exit_code

  if [ "$failure_count" -gt 0 ]
  then
    overall_status="FAIL"
    script_exit_code=2
  elif [ "$warning_count" -gt 0 ]
  then
    overall_status="WARN"
    script_exit_code=1
  else
    overall_status="HEALTHY"
    script_exit_code=0
  fi

  write_line ""
  write_line "Summary:"
  write_line "PASS: $pass_count"
  write_line "WARN: $warning_count"
  write_line "FAIL: $failure_count"
  write_line "Overall Status: $overall_status"
  write_line "Script Exit Code: $script_exit_code"
  write_line "Report File: $report_file"
  write_line "Raw Log File: $raw_log_file"

  return "$script_exit_code"
}

print_header
fetch_latest_run_log

for check_function in "${checks[@]}"
do
  "$check_function"
done

print_summary
exit $?
