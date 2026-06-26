#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/compile.log" <<'EOF'
Compile jobs: 4 (runner cores: 4, limit: auto)
[compile heartbeat] 2026-06-26T00:00:00Z build still running
               total        used        free      shared  buff/cache   available
Mem:            15Gi       3.2Gi       206Mi        57Mi        12Gi        12Gi
Swap:          1.0Gi        16Mi       1.0Gi
Filesystem                  Type  Size  Used Avail Use% Mounted on
/dev/mapper/buildvg-buildlv ext4   86G   37G   50G  43% /home/runner/work/repo/repo
[compile heartbeat] 2026-06-26T00:05:00Z build still running
Filesystem                  Type  Size  Used Avail Use% Mounted on
/dev/mapper/buildvg-buildlv ext4   86G   46G   41G  53% /home/runner/work/repo/repo
EOF

PROFILE_ID="x86_64_immortalWrt" \
PROFILE_TITLE="x86_64 ImmortalWrt" \
REPO_URL="https://github.com/immortalwrt/immortalwrt" \
REPO_BRANCH="openwrt-25.12" \
SOURCE_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
PROFILE_HASH="profilehash" \
COMPILE_STARTED_AT="2026-06-26T00:00:00Z" \
COMPILE_COMPLETED_AT="2026-06-26T00:10:00Z" \
COMPILE_DURATION_SECONDS="600" \
  bash "${ROOT_DIR}/scripts/ci/build-metrics.sh" generate "${TMP_DIR}" "${TMP_DIR}/openwrt" "${TMP_DIR}/metrics"

grep -q "| Compile jobs | 4 |" "${TMP_DIR}/metrics/build-metrics.md"
grep -q "| Heartbeat count | 2 |" "${TMP_DIR}/metrics/build-metrics.md"
grep -q "| Max heartbeat disk use | 53% |" "${TMP_DIR}/metrics/build-metrics.md"
jq -e '.compile_jobs == "4" and .heartbeat_count == "2" and .max_heartbeat_disk_use == "53%"' "${TMP_DIR}/metrics/build-metrics.json" >/dev/null

echo "Build metrics fixture test passed."
