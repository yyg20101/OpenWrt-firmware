#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
WORKFLOW="${ROOT_DIR}/.github/workflows/cache-maintenance.yml"
MAINTENANCE_SCRIPT="${ROOT_DIR}/scripts/ci/actions-storage-maintenance.sh"

if [ ! -f "${WORKFLOW}" ]; then
  echo "ERROR: missing Cache Maintenance workflow: ${WORKFLOW}" >&2
  exit 1
fi
if [ ! -x "${MAINTENANCE_SCRIPT}" ]; then
  echo "ERROR: missing executable Actions storage maintenance script: ${MAINTENANCE_SCRIPT}" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
workflow_path = root.join(".github/workflows/cache-maintenance.yml")
script_path = root.join("scripts/ci/actions-storage-maintenance.sh")
workflow = YAML.load_file(workflow_path.to_s) || {}
triggers = workflow["on"] || workflow[true] || {}
inputs = triggers.dig("workflow_dispatch", "inputs") || {}
schedule = triggers["schedule"] || []

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

fail!("dry_run must default to true") unless inputs.dig("dry_run", "default") == true
fail!("keep_latest must default to 1") unless inputs.dig("keep_latest", "default").to_s == "1"
fail!("prefix input must exist") unless inputs.key?("prefix")
fail!("ref input must exist") unless inputs.key?("ref")
fail!("ref input must default to refs/heads/main") unless inputs.dig("ref", "default") == "refs/heads/main"
fail!("artifact_older_than_days input must exist") unless inputs.key?("artifact_older_than_days")
fail!("artifact_keep_latest_runs input must exist") unless inputs.key?("artifact_keep_latest_runs")
fail!("artifact_keep_latest_runs must default to 1") unless inputs.dig("artifact_keep_latest_runs", "default").to_s == "1"
fail!("workflow_run_older_than_days input must exist") unless inputs.key?("workflow_run_older_than_days")
fail!("workflow_run_older_than_days must default to 7") unless inputs.dig("workflow_run_older_than_days", "default").to_s == "7"
fail!("workflow_run_keep_latest_per_workflow input must exist") unless inputs.key?("workflow_run_keep_latest_per_workflow")
fail!("workflow_run_keep_latest_per_workflow must default to 3") unless inputs.dig("workflow_run_keep_latest_per_workflow", "default").to_s == "3"
fail!("cache maintenance must run on a schedule") unless schedule.any? { |entry| entry["cron"].to_s.strip != "" }

permissions = workflow["permissions"] || {}
fail!("actions permission must be write for cache cleanup") unless permissions["actions"] == "write"
fail!("contents permission should remain read") unless permissions["contents"] == "read"

body = workflow_path.read
script = script_path.read
fail!("real cache deletion must require prefix or ref") unless script.include?('! is_true "${DRY_RUN}" && [ -z "${CACHE_PREFIX}" ] && [ -z "${CACHE_REF}" ]')
fail!("cache cleanup workflow must call maintenance script") unless body.include?("bash scripts/ci/actions-storage-maintenance.sh")
fail!("workflow must pass GitHub token to maintenance script") unless body.include?("GH_TOKEN: ${{ github.token }}")
fail!("workflow must pass current run id to maintenance script") unless body.include?("CURRENT_RUN_ID: ${{ github.run_id }}")
fail!("workflow inputs must have scheduled cache defaults") unless body.include?("CACHE_OLDER_THAN_DAYS: ${{ inputs.older_than_days || '7' }}")
fail!("workflow inputs must have scheduled workflow run defaults") unless body.include?("WORKFLOW_RUN_OLDER_THAN_DAYS: ${{ inputs.workflow_run_older_than_days || '7' }}")
fail!("dry_run must be forwarded to maintenance script") unless body.include?("DRY_RUN: ${{ inputs.dry_run || 'false' }}")
fail!("cache cleanup must use explicit REST pagination") unless script.include?('actions/caches?per_page=100')
fail!("artifact cleanup must use explicit REST pagination") unless script.include?('actions/artifacts?per_page=100')
fail!("workflow run cleanup must use explicit REST pagination") unless script.include?('actions/runs?per_page=100')
fail!("script must delete caches by id") unless script.include?('actions/caches/${id}')
fail!("script must delete artifacts by id") unless script.include?('actions/artifacts/${id}')
fail!("script must delete workflow runs by id") unless script.include?('actions/runs/${id}')
fail!("script must protect newest firmware runs") unless script.include?("Protected firmware runs") && script.include?("newest_firmware_runs")
fail!("script must protect current workflow run") unless script.include?("CURRENT_RUN_ID") && script.include?("current_run_id")
fail!("script must keep latest runs per workflow") unless script.include?("WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW") && script.include?("workflow_group_counts")
fail!("cache cleanup must keep latest entries per cache group") unless script.include?("cache_group_key") && script.include?("group_counts")

puts "Cache Maintenance workflow guard passed."
RUBY
