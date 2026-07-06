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

fail!("mode input must exist") unless inputs.key?("mode")
fail!("workflow_dispatch must expose only mode input") unless inputs.keys == ["mode"]
fail!("mode must be required") unless inputs.dig("mode", "required") == true
fail!("mode must default to preview") unless inputs.dig("mode", "default") == "preview"
fail!("mode must be a choice input") unless inputs.dig("mode", "type") == "choice"
fail!("mode options must be preview and cleanup") unless inputs.dig("mode", "options") == ["preview", "cleanup"]

forbidden_inputs = %w[
  older_than_days
  prefix
  ref
  keep_latest
  artifact_older_than_days
  artifact_keep_latest_runs
  workflow_run_older_than_days
  workflow_run_keep_latest_per_workflow
  dry_run
]
forbidden_inputs.each do |input|
  fail!("#{input} input must not be exposed in workflow_dispatch") if inputs.key?(input)
end
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
fail!("preview mode must map to dry-run") unless body.include?("DRY_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.mode == 'preview' && 'true' || 'false' }}")
fail!("workflow must keep fixed artifact age default") unless body.include?('ARTIFACT_OLDER_THAN_DAYS: "2"')
fail!("workflow must keep fixed protected firmware run default") unless body.include?('ARTIFACT_KEEP_LATEST_RUNS: "1"')
fail!("workflow must keep fixed cache age default") unless body.include?('CACHE_OLDER_THAN_DAYS: "7"')
fail!("workflow must keep fixed cache prefix default") unless body.include?('CACHE_PREFIX: ""')
fail!("workflow must keep fixed cache ref default") unless body.include?("CACHE_REF: refs/heads/main")
fail!("workflow must keep fixed cache group retention default") unless body.include?('CACHE_KEEP_LATEST: "1"')
fail!("workflow must keep fixed workflow run age default") unless body.include?('WORKFLOW_RUN_OLDER_THAN_DAYS: "7"')
fail!("workflow must keep fixed workflow run retention default") unless body.include?('WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW: "3"')
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
