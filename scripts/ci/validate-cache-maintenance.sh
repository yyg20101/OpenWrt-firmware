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

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

fail!("dry_run must default to true") unless inputs.dig("dry_run", "default") == true
fail!("keep_latest must default to 2") unless inputs.dig("keep_latest", "default").to_s == "2"
fail!("prefix input must exist") unless inputs.key?("prefix")
fail!("ref input must exist") unless inputs.key?("ref")

permissions = workflow["permissions"] || {}
fail!("actions permission must be write for cache cleanup") unless permissions["actions"] == "write"
fail!("contents permission should remain read") unless permissions["contents"] == "read"

body = workflow_path.read
fail!("real deletion must require prefix or ref") unless body.include?("!dryRun && !prefix && !ref")
fail!("cache cleanup must use deleteActionsCacheById") unless body.include?("deleteActionsCacheById")
fail!("workflow_dispatch inputs must be forwarded to github-script env") unless body.include?("OLDER_THAN_DAYS: ${{ inputs.older_than_days }}")
fail!("dry_run must be parsed from forwarded env") unless body.include?("process.env.DRY_RUN")
fail!("cache cleanup must keep latest entries per cache group") unless body.include?("cacheGroupKey") && body.include?("groupCounts")
fail!("cache cleanup must not use global matched.slice retention") if body.include?("matched.slice(0, keepLatest)")
fail!("cache cleanup must log candidate counts") unless body.include?("Cleanup candidates: ${candidates.length}")

puts "Cache Maintenance workflow guard passed."
RUBY
