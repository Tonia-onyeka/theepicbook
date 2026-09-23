#!/bin/bash

set -u

full_name="Anthonia Akwuohia"
provider="azure-devops"
ado_org="https://dev.azure.com/anthonia-devops-DMI/"
ado_project="EpicBook"

infra_pipeline_id="6"
app_pipeline_id="5"

gh_repo=""

base_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
report_dir="$base_dir/reports"
report_file="$report_dir/pipeline-health-report.txt"
infra_log_file="$report_dir/infra-last-run.log"
app_log_file="$report_dir/app-last-run.log"

checks=(
  check_dependency_failure
  check_build_failure
  check_test_failure
  check_auth_failure
  check_agent_failure
  check_terraform_failure
  check_deployment_failure
  check_unclassified_failure
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

sanitize_log() {
  awk '
    BEGIN {
      redacting_private_key = 0
    }

    /-----BEGIN .*PRIVATE KEY-----/ {
      print "[REDACTED PRIVATE KEY BLOCK]"
      redacting_private_key = 1
      next
    }

    redacting_private_key && /-----END .*PRIVATE KEY-----/ {
      redacting_private_key = 0
      next
    }

    redacting_private_key {
      next
    }

    {
      lower = tolower($0)

      if ((lower ~ /server=/ || lower ~ /data source=/ || lower ~ /host=/) &&
          (lower ~ /password=/ || lower ~ /pwd=/ || lower ~ /user id=/ ||
           lower ~ /userid=/ || lower ~ /connectionstring=/)) {
        print "[REDACTED SECRET CONNECTION STRING]"
        next
      }

      gsub(/Authorization:[[:space:]]*(Bearer|Basic)[^[:space:]]*/,
           "Authorization: [REDACTED]")

      gsub(/Bearer[[:space:]]+[A-Za-z0-9._~+\/=-]+/,
           "Bearer [REDACTED]")

      gsub(/(password|passwd|pwd|client_secret|clientsecret|pat|token|secret)[[:space:]]*=[[:space:]]*[^[:space:];,]+/,
           "\\1=[REDACTED]")

      gsub(/(password|passwd|pwd|client_secret|clientsecret|pat|token|secret)[[:space:]]*:[[:space:]]*[^[:space:];,]+/,
           "\\1: [REDACTED]")

      print
    }
  '
}

fetch_pipeline_log() {
  local pipeline_label="$1"
  local pipeline_id="$2"
  local log_file="$3"

  local run_id
  local run_status
  local run_result
  local source_branch
  local finish_time
  local pipeline_name
  local tmp_log
  local log_ids
  local log_id
  local api_status

  if ! command -v az >/dev/null 2>&1
  then
    write_line "[ERROR] Azure CLI (az) is not installed or not available."
    failure_count=$((failure_count + 1))
    return 3
  fi

  write_line ""
  write_line "----------------------------------------"
  write_line "$pipeline_label Pipeline"
  write_line "----------------------------------------"

     local branch_name

  if [ "$pipeline_label" = "Infrastructure" ]
  then
    branch_name="main"
  else
    branch_name="drill/pipeline-failure"
  fi

  run_id=$(az pipelines runs list \
    --organization "$ado_org" \
    --project "$ado_project" \
    --pipeline-ids "$pipeline_id" \
    --branch "$branch_name" \
    --top 1 \
    --query "[0].id" \
    -o tsv 2>/dev/null)
  api_status=$?

  if [ "$api_status" -ne 0 ]
  then
    write_line "[ERROR] Unable to retrieve $pipeline_label pipeline run metadata."
    failure_count=$((failure_count + 1))
    return 3
  fi

  if [ -z "$run_id" ]
  then
    write_line "[WARN] No run found for $pipeline_label Pipeline ID $pipeline_id."
    warning_count=$((warning_count + 1))
    return 1
  fi

  run_status=$(az pipelines runs show \
    --organization "$ado_org" \
    --project "$ado_project" \
    --id "$run_id" \
    --query "status" \
    -o tsv 2>/dev/null)
  api_status=$?

  if [ "$api_status" -ne 0 ]
  then
    write_line "[ERROR] Unable to retrieve status for $pipeline_label Run $run_id."
    failure_count=$((failure_count + 1))
    return 3
  fi

  run_result=$(az pipelines runs show \
    --organization "$ado_org" \
    --project "$ado_project" \
    --id "$run_id" \
    --query "result" \
    -o tsv 2>/dev/null)
  api_status=$?

  if [ "$api_status" -ne 0 ]
  then
    write_line "[ERROR] Unable to retrieve result for $pipeline_label Run $run_id."
    failure_count=$((failure_count + 1))
    return 3
  fi

  source_branch=$(az pipelines runs show \
    --organization "$ado_org" \
    --project "$ado_project" \
    --id "$run_id" \
    --query "sourceBranch" \
    -o tsv 2>/dev/null)

  finish_time=$(az pipelines runs show \
    --organization "$ado_org" \
    --project "$ado_project" \
    --id "$run_id" \
    --query "finishTime" \
    -o tsv 2>/dev/null)

  pipeline_name=$(az pipelines runs show \
    --organization "$ado_org" \
    --project "$ado_project" \
    --id "$run_id" \
    --query "definition.name" \
    -o tsv 2>/dev/null)

  write_line "Pipeline Name: ${pipeline_name:-Unknown}"
  write_line "Pipeline ID: $pipeline_id"
  write_line "Run ID: $run_id"
  write_line "Branch: ${source_branch:-Unknown}"
  write_line "Status: ${run_status:-Unknown}"
  write_line "Result: ${run_result:-Unknown}"
  write_line "Completion: ${finish_time:-Not completed}"

  run_status="$(printf '%s' "$run_status" | tr -d '\r\n' | xargs)"
  run_result="$(printf '%s' "$run_result" | tr -d '\r\n' | xargs)"

  current_pipeline_label="$pipeline_label"
  current_pipeline_id="$pipeline_id"
  current_run_id="$run_id"
  current_run_status="$run_status"
  current_run_result="$run_result"
  current_log_file="$log_file"
  current_category_matches=0

  case "${run_status,,}" in
    completed)
      case "${run_result,,}" in
        succeeded)
          write_line "[PASS] $pipeline_label completed successfully."
          pass_count=$((pass_count + 1))
          ;;
        failed)
          write_line "[FAIL] $pipeline_label completed with failure."
          failure_count=$((failure_count + 1))
          ;;
        partiallysucceeded|partially_succeeded)
          write_line "[WARN] $pipeline_label completed partially successfully."
          warning_count=$((warning_count + 1))
          ;;
        canceled|cancelled)
          write_line "[WARN] $pipeline_label run was canceled."
          warning_count=$((warning_count + 1))
          ;;
        "")
          write_line "[ERROR] $pipeline_label completed without a result."
          failure_count=$((failure_count + 1))
          return 3
          ;;
        *)
          write_line "[ERROR] Unknown Azure DevOps run result: $run_result"
          failure_count=$((failure_count + 1))
          return 3
          ;;
      esac
      ;;
    queued|inprogress|running|notstarted)
      write_line "[WARN] $pipeline_label is not completed. Current status: $run_status"
      warning_count=$((warning_count + 1))
      return 1
      ;;
    *)
      write_line "[ERROR] Unknown Azure DevOps run status: ${run_status:-empty}"
      failure_count=$((failure_count + 1))
      return 3
      ;;
  esac

  if [ "${run_status,,}" != "completed" ]
  then
    return 1
  fi

  : > "$log_file"

  tmp_log=$(mktemp)

  log_ids=$(az devops invoke \
    --organization "$ado_org" \
    --area build \
    --resource logs \
    --route-parameters project="$ado_project" buildId="$run_id" \
    --api-version "7.1" \
    --query "value[].id" \
    -o tsv 2>/dev/null)
  api_status=$?

  if [ "$api_status" -ne 0 ]
  then
    rm -f "$tmp_log"
    write_line "[ERROR] Unable to retrieve Build Log IDs for $pipeline_label Run $run_id."
    failure_count=$((failure_count + 1))
    return 3
  fi

  if [ -z "$log_ids" ]
  then
    rm -f "$tmp_log"
    write_line "[ERROR] No Build Log IDs were returned for $pipeline_label Run $run_id."
    failure_count=$((failure_count + 1))
    return 3
  fi

  while IFS= read -r log_id
  do
    [ -z "$log_id" ] && continue

    if ! az devops invoke \
      --organization "$ado_org" \
      --area build \
      --resource logs \
      --route-parameters project="$ado_project" buildId="$run_id" logId="$log_id" \
      --api-version "7.1" \
      --query "value[]" \
      -o tsv >> "$tmp_log" 2>/dev/null
    then
      rm -f "$tmp_log"
      write_line "[ERROR] Unable to retrieve Build Log ID $log_id for $pipeline_label."
      failure_count=$((failure_count + 1))
      return 3
    fi
  done <<< "$log_ids"

  if [ ! -s "$tmp_log" ]
  then
    rm -f "$tmp_log"
    write_line "[ERROR] Build Logs API returned no console log text for $pipeline_label."
    failure_count=$((failure_count + 1))
    return 3
  fi

  sanitize_log < "$tmp_log" > "$log_file"
  rm -f "$tmp_log"

  write_line "Sanitized console log saved: $log_file"

  return 0
}

fetch_latest_run_log() {
  fetch_pipeline_log "Infrastructure" "$infra_pipeline_id" "$infra_log_file"
  local infra_rc=$?

  fetch_pipeline_log "Application" "$app_pipeline_id" "$app_log_file"
  local app_rc=$?

  if [ "$infra_rc" -eq 3 ] || [ "$app_rc" -eq 3 ]
  then
    return 3
  elif [ "$infra_rc" -eq 2 ] || [ "$app_rc" -eq 2 ]
  then
    return 2
  elif [ "$infra_rc" -eq 1 ] || [ "$app_rc" -eq 1 ]
  then
    return 1
  fi

  return 0
}

check_dependency_failure() {
  if grep -qiE "npm ERR!|ENOENT|ERESOLVE|pip install.*error|ModuleNotFoundError|package not found" "$current_log_file" 2>/dev/null
  then
    mark_failure "Dependency install failure detected in pipeline log"
  else
    mark_pass "No dependency install failure detected"
  fi
}

check_build_failure() {
  if grep -qiE "build failed|compilation error|SyntaxError|TS[0-9]{4}|webpack.*failed|exit code 1" "$current_log_file" 2>/dev/null
  then
    mark_failure "Build or compile failure detected in pipeline log"
  else
    mark_pass "No build or compile failure detected"
  fi
}

check_test_failure() {
  if grep -qiE "tests? failed|AssertionError|FAIL |[0-9]+ failing|expect\(received\)" "$current_log_file" 2>/dev/null
  then
    mark_failure "Test failure detected in pipeline log"
  else
    mark_pass "No test failure detected"
  fi
}

check_auth_failure() {
  if grep -qiE "401 Unauthorized|403 Forbidden|TF400813|invalid_grant|token has expired|permission denied \(publickey\)|Bad credentials" "$current_log_file" 2>/dev/null
  then
    mark_failure "Authentication or permission failure detected in pipeline log"
  else
    mark_pass "No authentication or permission failure detected"
  fi
}

check_agent_failure() {
  if grep -qiE "no agent found|agent.*offline|timed out waiting for an agent|job.*timed out|runner.*offline" "$current_log_file" 2>/dev/null
  then
    mark_warning "Agent or runner availability issue detected in pipeline log"
  else
    mark_pass "No agent or runner availability issue detected"
  fi
}

check_terraform_failure() {
  local pattern='terraform.*(error|failed|failure)|Error:.*(terraform|resource|provider)|terraform.*(apply|plan|init|validate).*failed'

  if [ ! -s "$current_log_file" ]
  then
    return 0
  fi

  if grep -qiE "$pattern" "$current_log_file"
  then
    current_category_matches=$((current_category_matches + 1))
    mark_failure "$current_pipeline_label: Terraform infrastructure/provisioning failure detected."
    write_line "Evidence:"
    grep -iE "$pattern" "$current_log_file" | head -5 | while IFS= read -r line
    do
      write_line "  $line"
    done
  fi
}

check_deployment_failure() {
  local pattern='ansible-playbook.*(failed|failure)|fatal:.*=>|FAILED!|nginx.*(failed|failure|error)|systemctl.*nginx.*failed|application.*(failed|failure|error)|deployment.*(failed|failure|error)|epicbook.*(failed|failure|error)'

  if [ ! -s "$current_log_file" ]
  then
    return 0
  fi

  if grep -qiE "$pattern" "$current_log_file"
  then
    current_category_matches=$((current_category_matches + 1))
    mark_failure "$current_pipeline_label: Ansible/Nginx/application deployment failure detected."
    write_line "Evidence:"
    grep -iE "$pattern" "$current_log_file" | head -5 | while IFS= read -r line
    do
      write_line "  $line"
    done
  fi
}

check_unclassified_failure() {
  if [ "${current_run_result,,}" = "failed" ] && [ "$current_category_matches" -eq 0 ]
  then
    mark_failure "$current_pipeline_label: Unclassified Pipeline Failure."
    write_line "Evidence: No supported failure-category pattern was found in the sanitized retrieved logs."
  fi
}

check_ado_run_result() {
  case "${current_run_result,,}" in
    succeeded)
      mark_pass "$current_pipeline_label Azure DevOps run result is 'succeeded'"
      ;;
    partiallysucceeded|partially_succeeded)
      mark_warning "$current_pipeline_label Azure DevOps run result is 'partiallySucceeded'"
      ;;
    failed)
      mark_failure "$current_pipeline_label Azure DevOps run result is 'failed'"
      ;;
    canceled|cancelled)
      mark_warning "$current_pipeline_label Azure DevOps run result is 'canceled'"
      ;;
    *)
      mark_failure "$current_pipeline_label Azure DevOps run result is unknown or missing"
      ;;
  esac
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
  write_line "Sanitized Log File: $current_log_file"

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
