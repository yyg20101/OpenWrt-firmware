#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_true() {
  case "${1:-}" in
    true | True | TRUE) return 0 ;;
    *) return 1 ;;
  esac
}

validate_bool() {
  case "${1:-}" in
    true | True | TRUE | false | False | FALSE) ;;
    *) die "$2 must be true or false, got ${1:-}" ;;
  esac
}

validate_uint() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || die "$2 must be a non-negative integer, got ${1:-}"
}

require_command gh
require_command jq
require_command ruby

REPOSITORY="${REPOSITORY:-${GITHUB_REPOSITORY:-}}"
DRY_RUN="${DRY_RUN:-true}"
ARTIFACT_OLDER_THAN_DAYS="${ARTIFACT_OLDER_THAN_DAYS:-2}"
ARTIFACT_KEEP_LATEST_RUNS="${ARTIFACT_KEEP_LATEST_RUNS:-1}"
CACHE_OLDER_THAN_DAYS="${CACHE_OLDER_THAN_DAYS:-7}"
CACHE_PREFIX="${CACHE_PREFIX:-}"
CACHE_REF="${CACHE_REF:-refs/heads/main}"
CACHE_KEEP_LATEST="${CACHE_KEEP_LATEST:-1}"
WORKFLOW_RUN_OLDER_THAN_DAYS="${WORKFLOW_RUN_OLDER_THAN_DAYS:-7}"
WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW="${WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW:-3}"
CURRENT_RUN_ID="${CURRENT_RUN_ID:-${GITHUB_RUN_ID:-}}"

[ -n "${REPOSITORY}" ] || die "REPOSITORY or GITHUB_REPOSITORY must be set"
validate_bool "${DRY_RUN}" "DRY_RUN"
validate_uint "${ARTIFACT_OLDER_THAN_DAYS}" "ARTIFACT_OLDER_THAN_DAYS"
validate_uint "${ARTIFACT_KEEP_LATEST_RUNS}" "ARTIFACT_KEEP_LATEST_RUNS"
validate_uint "${CACHE_OLDER_THAN_DAYS}" "CACHE_OLDER_THAN_DAYS"
validate_uint "${CACHE_KEEP_LATEST}" "CACHE_KEEP_LATEST"
validate_uint "${WORKFLOW_RUN_OLDER_THAN_DAYS}" "WORKFLOW_RUN_OLDER_THAN_DAYS"
validate_uint "${WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW}" "WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW"

if ! is_true "${DRY_RUN}" && [ -z "${CACHE_PREFIX}" ] && [ -z "${CACHE_REF}" ]; then
  die "refusing to delete caches without CACHE_PREFIX or CACHE_REF. Set a filter or run with DRY_RUN=true."
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

artifacts_json="${tmp_dir}/artifacts.json"
caches_json="${tmp_dir}/caches.json"
runs_json="${tmp_dir}/workflow-runs.json"
artifact_candidates="${tmp_dir}/artifact-candidates.jsonl"
cache_candidates="${tmp_dir}/cache-candidates.jsonl"
run_candidates="${tmp_dir}/workflow-run-candidates.jsonl"

echo "Listing GitHub Actions artifacts for ${REPOSITORY}..."
gh api --paginate "repos/${REPOSITORY}/actions/artifacts?per_page=100" --jq ".artifacts[]?" | jq -s "." > "${artifacts_json}"

echo "Listing GitHub Actions caches for ${REPOSITORY}..."
gh api --paginate "repos/${REPOSITORY}/actions/caches?per_page=100" --jq ".actions_caches[]?" | jq -s "." > "${caches_json}"

echo "Listing historical workflow runs for ${REPOSITORY}..."
gh api --paginate "repos/${REPOSITORY}/actions/runs?per_page=100" --jq ".workflow_runs[]?" | jq -s "." > "${runs_json}"

export ARTIFACTS_JSON="${artifacts_json}"
export CACHES_JSON="${caches_json}"
export WORKFLOW_RUNS_JSON="${runs_json}"
export ARTIFACT_CANDIDATES="${artifact_candidates}"
export CACHE_CANDIDATES="${cache_candidates}"
export WORKFLOW_RUN_CANDIDATES="${run_candidates}"
export DRY_RUN
export ARTIFACT_OLDER_THAN_DAYS
export ARTIFACT_KEEP_LATEST_RUNS
export CACHE_OLDER_THAN_DAYS
export CACHE_PREFIX
export CACHE_REF
export CACHE_KEEP_LATEST
export WORKFLOW_RUN_OLDER_THAN_DAYS
export WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW
export CURRENT_RUN_ID

ruby <<'RUBY'
require "json"
require "set"
require "time"

def read_json(path)
  JSON.parse(File.read(path))
end

def write_jsonl(path, rows)
  File.open(path, "w") do |file|
    rows.each { |row| file.puts(JSON.generate(row)) }
  end
end

def parse_time(value)
  Time.parse(value.to_s).utc
end

def cutoff(days)
  Time.now.utc - days.to_i * 24 * 60 * 60
end

def format_bytes(bytes)
  mib = bytes.to_f / 1024 / 1024
  if mib >= 1024
    format("%.2f GiB", mib / 1024)
  else
    format("%.2f MiB", mib)
  end
end

def cache_group_key(key)
  parts = key.to_s.split("-")
  return parts[0, 5].join("-") if parts[0] == "ccache" && parts[1] == "v2" && parts.length >= 6
  return parts[0, 6].join("-") if parts[0] == "build" && parts[1] == "accel" && parts[2] == "v2" && parts.length >= 7

  key.to_s
end

def workflow_group_key(run)
  value = run["workflow_id"] || run["path"] || run["name"] || "unknown"
  value.to_s
end

def markdown_table(headers, rows)
  return "" if rows.empty?

  lines = []
  lines << "| #{headers.join(' | ')} |"
  lines << "| #{headers.map { "---" }.join(' | ')} |"
  rows.each do |row|
    lines << "| #{row.join(' | ')} |"
  end
  lines.join("\n") + "\n"
end

artifacts = read_json(ENV.fetch("ARTIFACTS_JSON"))
caches = read_json(ENV.fetch("CACHES_JSON"))
runs = read_json(ENV.fetch("WORKFLOW_RUNS_JSON"))

dry_run = /^(true|True|TRUE)$/.match?(ENV.fetch("DRY_RUN"))
artifact_cutoff = cutoff(ENV.fetch("ARTIFACT_OLDER_THAN_DAYS"))
artifact_keep_latest_runs = ENV.fetch("ARTIFACT_KEEP_LATEST_RUNS").to_i
cache_cutoff = cutoff(ENV.fetch("CACHE_OLDER_THAN_DAYS"))
cache_prefix = ENV.fetch("CACHE_PREFIX", "")
cache_ref = ENV.fetch("CACHE_REF", "")
cache_keep_latest = ENV.fetch("CACHE_KEEP_LATEST").to_i
workflow_run_cutoff = cutoff(ENV.fetch("WORKFLOW_RUN_OLDER_THAN_DAYS"))
workflow_run_keep_latest = ENV.fetch("WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW").to_i
current_run_id = ENV.fetch("CURRENT_RUN_ID", "").to_s

newest_firmware_runs = []
artifacts
  .select { |artifact| artifact["name"].to_s.start_with?("firmware-") }
  .sort_by { |artifact| parse_time(artifact["created_at"]) }
  .reverse
  .each do |artifact|
    run_id = artifact.dig("workflow_run", "id")
    next unless run_id
    next if newest_firmware_runs.include?(run_id)

    newest_firmware_runs << run_id
    break if newest_firmware_runs.length >= artifact_keep_latest_runs
  end
protected_firmware_runs = newest_firmware_runs.to_set

artifact_candidates = artifacts.select do |artifact|
  run_id = artifact.dig("workflow_run", "id")
  name = artifact["name"].to_s
  created_at = parse_time(artifact["created_at"])
  firmware = name.start_with?("firmware-")
  smoke = name.start_with?("smoke-")

  if firmware
    !protected_firmware_runs.include?(run_id)
  elsif !smoke && protected_firmware_runs.include?(run_id)
    false
  else
    created_at <= artifact_cutoff
  end
end.sort_by { |artifact| parse_time(artifact["created_at"]) }

matched_caches = caches.select do |cache|
  key = cache["key"].to_s
  ref = cache["ref"].to_s
  (cache_prefix.empty? || key.start_with?(cache_prefix)) && (cache_ref.empty? || ref == cache_ref)
end

protected_cache_ids = Set.new
group_counts = Hash.new(0)
matched_caches
  .sort_by { |cache| parse_time(cache["last_accessed_at"]) }
  .reverse
  .each do |cache|
    group = cache_group_key(cache["key"])
    if group_counts[group] < cache_keep_latest
      protected_cache_ids << cache["id"]
    end
    group_counts[group] += 1
  end

cache_candidates = matched_caches.select do |cache|
  !protected_cache_ids.include?(cache["id"]) && parse_time(cache["last_accessed_at"]) <= cache_cutoff
end.sort_by { |cache| parse_time(cache["last_accessed_at"]) }

protected_run_ids = protected_firmware_runs.map(&:to_s).to_set
protected_run_ids << current_run_id unless current_run_id.empty?
workflow_group_counts = Hash.new(0)
runs
  .sort_by { |run| parse_time(run["created_at"]) }
  .reverse
  .each do |run|
    group = workflow_group_key(run)
    if workflow_group_counts[group] < workflow_run_keep_latest
      protected_run_ids << run["id"].to_s
    end
    workflow_group_counts[group] += 1
  end

workflow_run_candidates = runs.select do |run|
  run_id = run["id"].to_s
  run["status"].to_s == "completed" &&
    !protected_run_ids.include?(run_id) &&
    parse_time(run["created_at"]) <= workflow_run_cutoff
end.sort_by { |run| parse_time(run["created_at"]) }

write_jsonl(ENV.fetch("ARTIFACT_CANDIDATES"), artifact_candidates)
write_jsonl(ENV.fetch("CACHE_CANDIDATES"), cache_candidates)
write_jsonl(ENV.fetch("WORKFLOW_RUN_CANDIDATES"), workflow_run_candidates)

artifact_bytes = artifact_candidates.sum { |artifact| artifact["size_in_bytes"].to_i }
cache_bytes = cache_candidates.sum { |cache| cache["size_in_bytes"].to_i }

puts "Dry run: #{dry_run}"
puts "Artifacts listed: #{artifacts.length}"
puts "Protected firmware runs: #{newest_firmware_runs.empty? ? '(none)' : newest_firmware_runs.join(', ')}"
puts "Artifact cleanup candidates: #{artifact_candidates.length}"
puts "Artifact bytes to delete: #{format_bytes(artifact_bytes)}"
puts "Caches listed: #{caches.length}"
puts "Matched caches: #{matched_caches.length}"
puts "Matched cache groups: #{group_counts.length}"
puts "Cache cleanup candidates: #{cache_candidates.length}"
puts "Cache bytes to delete: #{format_bytes(cache_bytes)}"
puts "Workflow runs listed: #{runs.length}"
puts "Workflow run groups: #{workflow_group_counts.length}"
puts "Workflow run cleanup candidates: #{workflow_run_candidates.length}"

summary_path = ENV["GITHUB_STEP_SUMMARY"]
if summary_path && !summary_path.empty?
  artifact_rows = artifact_candidates.first(50).map do |artifact|
    [
      artifact["id"].to_s,
      artifact["name"].to_s,
      format_bytes(artifact["size_in_bytes"].to_i),
      artifact["created_at"].to_s,
    ]
  end
  cache_rows = cache_candidates.first(50).map do |cache|
    [
      cache["id"].to_s,
      cache["key"].to_s,
      cache["ref"].to_s,
      format_bytes(cache["size_in_bytes"].to_i),
      cache["last_accessed_at"].to_s,
    ]
  end
  run_rows = workflow_run_candidates.first(50).map do |run|
    [
      run["id"].to_s,
      (run["display_title"] || run["name"]).to_s,
      run["event"].to_s,
      run["conclusion"].to_s,
      run["created_at"].to_s,
    ]
  end

  File.open(summary_path, "a") do |summary|
    summary.puts "## Actions storage maintenance"
    summary.puts
    summary.puts "- Dry run: #{dry_run}"
    summary.puts "- Protected firmware runs: #{newest_firmware_runs.empty? ? '(none)' : newest_firmware_runs.join(', ')}"
    summary.puts "- Artifact cleanup candidates: #{artifact_candidates.length} / #{format_bytes(artifact_bytes)}"
    summary.puts "- Cache cleanup candidates: #{cache_candidates.length} / #{format_bytes(cache_bytes)}"
    summary.puts "- Workflow run cleanup candidates: #{workflow_run_candidates.length}"
    summary.puts
    summary.puts "### Artifact candidates"
    summary.puts artifact_rows.empty? ? "No artifacts matched." : markdown_table(["ID", "Name", "Size", "Created"], artifact_rows)
    summary.puts
    summary.puts "### Cache candidates"
    summary.puts cache_rows.empty? ? "No caches matched." : markdown_table(["ID", "Key", "Ref", "Size", "Last accessed"], cache_rows)
    summary.puts
    summary.puts "### Workflow run candidates"
    summary.puts run_rows.empty? ? "No workflow runs matched." : markdown_table(["ID", "Title", "Event", "Conclusion", "Created"], run_rows)
  end
end
RUBY

delete_candidates() {
  local kind="$1"
  local file="$2"
  local endpoint
  local id
  local label

  while IFS= read -r row || [ -n "${row}" ]; do
    [ -n "${row}" ] || continue
    id="$(jq -r ".id" <<< "${row}")"
    label="$(jq -r ".name // .key // .display_title // (.id | tostring)" <<< "${row}")"

    case "${kind}" in
      artifact) endpoint="repos/${REPOSITORY}/actions/artifacts/${id}" ;;
      cache) endpoint="repos/${REPOSITORY}/actions/caches/${id}" ;;
      workflow-run) endpoint="repos/${REPOSITORY}/actions/runs/${id}" ;;
      *) die "unknown deletion kind: ${kind}" ;;
    esac

    if is_true "${DRY_RUN}"; then
      echo "Would delete ${kind} ${id}: ${label}"
    else
      echo "Deleting ${kind} ${id}: ${label}"
      gh api --method DELETE "${endpoint}" >/dev/null
    fi
  done < "${file}"
}

delete_candidates artifact "${artifact_candidates}"
delete_candidates cache "${cache_candidates}"
delete_candidates workflow-run "${run_candidates}"
