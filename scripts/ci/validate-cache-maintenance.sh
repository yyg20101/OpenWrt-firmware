#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
WORKFLOW="${ROOT_DIR}/.github/workflows/cache-maintenance.yml"

if [ ! -f "${WORKFLOW}" ]; then
  echo "ERROR: missing Cache Maintenance workflow: ${WORKFLOW}" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
workflow_path = root.join(".github/workflows/cache-maintenance.yml")
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
fail!("cache maintenance must run on a schedule") unless schedule.any? { |entry| entry["cron"].to_s.strip != "" }

permissions = workflow["permissions"] || {}
fail!("actions permission must be write for cache cleanup") unless permissions["actions"] == "write"
fail!("contents permission should remain read") unless permissions["contents"] == "read"

body = workflow_path.read
fail!("real deletion must require prefix or ref") unless body.include?("!dryRun && !prefix && !ref")
fail!("cache cleanup must use deleteActionsCacheById") unless body.include?("deleteActionsCacheById")
fail!("workflow inputs must have scheduled defaults") unless body.include?("OLDER_THAN_DAYS: ${{ inputs.older_than_days || '7' }}")
fail!("dry_run must be parsed from forwarded env") unless body.include?("process.env.DRY_RUN")
fail!("cache API list request must pass ref when provided") unless body.include?("listRequest.ref = ref")
fail!("cache API list request must use explicit REST pagination") unless body.include?('github.request("GET /repos/{owner}/{repo}/actions/caches"')
fail!("cache API list request must not use getActionsCacheList wrapper") if body.include?("getActionsCacheList")
fail!("cache cleanup must keep latest entries per cache group") unless body.include?("cacheGroupKey") && body.include?("groupCounts")
fail!("cache cleanup must not use global matched.slice retention") if body.include?("matched.slice(0, keepLatest)")
fail!("cache cleanup must log candidate counts") unless body.include?("Cleanup candidates: ${candidates.length}")
fail!("artifact cleanup must use explicit REST pagination") unless body.include?('github.request("GET /repos/{owner}/{repo}/actions/artifacts"')
fail!("artifact cleanup must delete artifacts by id") unless body.include?('github.request("DELETE /repos/{owner}/{repo}/actions/artifacts/{artifact_id}"')
fail!("artifact cleanup must protect newest firmware runs") unless body.include?("Protected firmware runs") && body.include?("newestFirmwareRuns")

puts "Cache Maintenance workflow guard passed."
RUBY
