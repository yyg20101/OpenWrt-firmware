#!/usr/bin/env bash
set -euo pipefail

generate_metrics() {
  local workspace="$1"
  local openwrt_path="$2"
  local output_dir="$3"
  local compile_log="${workspace}/compile.log"
  local metrics_md="${output_dir}/build-metrics.md"
  local metrics_json="${output_dir}/build-metrics.json"
  local compile_jobs="unknown"
  local heartbeat_count="0"
  local max_disk_use="unknown"
  local compile_duration="${COMPILE_DURATION_SECONDS:-unknown}"

  mkdir -p "${output_dir}"

  if [ -f "${compile_log}" ]; then
    compile_jobs="$(sed -n 's/^Compile jobs: \([0-9][0-9]*\).*/\1/p' "${compile_log}" | head -n 1)"
    compile_jobs="${compile_jobs:-unknown}"
    heartbeat_count="$(grep -c '^\[compile heartbeat\]' "${compile_log}" || true)"
    max_disk_use="$(
      awk '$6 ~ /^[0-9]+%$/ { value = $6; gsub(/%/, "", value); if (value > max) max = value } END { if (max == "") print "unknown"; else print max "%" }' "${compile_log}"
    )"
  fi

  cat > "${metrics_md}" <<EOF
# Build Metrics

| Field | Value |
|-------|-------|
| Profile | ${PROFILE_TITLE:-unknown} (${PROFILE_ID:-unknown}) |
| Source | ${REPO_URL:-unknown} |
| Branch | ${REPO_BRANCH:-unknown} |
| Source commit | ${SOURCE_COMMIT:-unknown} |
| Profile hash | ${PROFILE_HASH:-unknown} |
| Compile jobs | ${compile_jobs} |
| Compile started at | ${COMPILE_STARTED_AT:-unknown} |
| Compile completed at | ${COMPILE_COMPLETED_AT:-unknown} |
| Compile duration seconds | ${compile_duration} |
| Heartbeat count | ${heartbeat_count} |
| Max heartbeat disk use | ${max_disk_use} |
| OpenWrt path | ${openwrt_path} |
EOF

  jq -n \
    --arg profile_id "${PROFILE_ID:-unknown}" \
    --arg profile_title "${PROFILE_TITLE:-unknown}" \
    --arg source_repo "${REPO_URL:-unknown}" \
    --arg branch "${REPO_BRANCH:-unknown}" \
    --arg source_commit "${SOURCE_COMMIT:-unknown}" \
    --arg profile_hash "${PROFILE_HASH:-unknown}" \
    --arg compile_jobs "${compile_jobs}" \
    --arg compile_started_at "${COMPILE_STARTED_AT:-unknown}" \
    --arg compile_completed_at "${COMPILE_COMPLETED_AT:-unknown}" \
    --arg compile_duration_seconds "${compile_duration}" \
    --arg heartbeat_count "${heartbeat_count}" \
    --arg max_heartbeat_disk_use "${max_disk_use}" \
    '{
      profile_id: $profile_id,
      profile_title: $profile_title,
      source_repo: $source_repo,
      branch: $branch,
      source_commit: $source_commit,
      profile_hash: $profile_hash,
      compile_jobs: $compile_jobs,
      compile_started_at: $compile_started_at,
      compile_completed_at: $compile_completed_at,
      compile_duration_seconds: $compile_duration_seconds,
      heartbeat_count: $heartbeat_count,
      max_heartbeat_disk_use: $max_heartbeat_disk_use
    }' > "${metrics_json}"
}

case "${1:-}" in
  generate)
    generate_metrics "${2:?workspace is required}" "${3:?openwrt path is required}" "${4:?output dir is required}"
    ;;
  *)
    echo "Usage: $0 generate <workspace> <openwrt-path> <output-dir>" >&2
    exit 1
    ;;
esac
