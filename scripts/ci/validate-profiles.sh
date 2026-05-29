#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"
bash "${ROOT_DIR}/scripts/ci/profiles.sh" validate "" "" "${ROOT_DIR}"

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"
require "open3"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
workflow_path = root.join(".github/workflows/firmware-ci.yml")

stdout, stderr, status = Open3.capture3(
  "bash",
  root.join("scripts/ci/profiles.sh").to_s,
  "target-options",
  "",
  "",
  root.to_s
)
unless status.success?
  warn stderr
  warn "ERROR: failed to generate expected firmware-ci target options"
  exit status.exitstatus || 1
end

expected_options = stdout.lines.map(&:strip).reject(&:empty?)

workflow = YAML.load_file(workflow_path.to_s) || {}
triggers = workflow["on"] || workflow[true] || {}
target_input = triggers.dig("workflow_dispatch", "inputs", "target") || {}
actual_options = Array(target_input["options"])

missing_options = expected_options - actual_options
stale_options = actual_options - expected_options

if missing_options.any? || stale_options.any?
  warn "ERROR: firmware-ci target options are out of sync with devices/profiles.yml"
  warn "Missing options: #{missing_options.join(", ")}" if missing_options.any?
  warn "Stale options: #{stale_options.join(", ")}" if stale_options.any?
  exit 1
end

puts "Validated #{actual_options.length} firmware-ci target option(s)"
RUBY
