#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
WORKFLOW="${ROOT_DIR}/.github/workflows/release-maintenance.yml"

if [ ! -f "${WORKFLOW}" ]; then
  echo "ERROR: missing Release Maintenance workflow: ${WORKFLOW}" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
workflow_path = root.join(".github/workflows/release-maintenance.yml")
workflow = YAML.load_file(workflow_path.to_s) || {}
triggers = workflow["on"] || workflow[true] || {}
inputs = triggers.dig("workflow_dispatch", "inputs") || {}

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

fail!("dry_run must default to true") unless inputs.dig("dry_run", "default") == true
fail!("tag_prefix must default to firmware- for broad dry-runs") unless inputs.dig("tag_prefix", "default") == "firmware-"
fail!("keep_latest must default to 2") unless inputs.dig("keep_latest", "default").to_s == "2"

permissions = workflow["permissions"] || {}
fail!("contents permission must be write for release cleanup") unless permissions["contents"] == "write"

body = workflow_path.read
fail!("real deletion must require a profile-specific firmware tag prefix") unless body.include?("profilePrefixPattern")
fail!("broad firmware- prefix must remain usable for dry-run") unless body.include?('default: "firmware-"')
fail!("release deletion must delete the Release") unless body.include?("deleteRelease")
fail!("release deletion must also attempt tag cleanup") unless body.include?("deleteRef")

puts "Release Maintenance workflow guard passed."
RUBY
