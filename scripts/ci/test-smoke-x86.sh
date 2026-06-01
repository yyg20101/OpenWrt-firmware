#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

OPENWRT_DIR="${TMP_DIR}/openwrt"
WORK_DIR="${TMP_DIR}/workspace"
FIRMWARE_DIR="${TMP_DIR}/firmware"

mkdir -p "${OPENWRT_DIR}" "${WORK_DIR}" "${FIRMWARE_DIR}"

RAW_PATH="${TMP_DIR}/base.raw" ruby <<'RUBY'
path = ENV.fetch("RAW_PATH")
data = "\x00".b * 512
data.setbyte(510, 0x55)
data.setbyte(511, 0xaa)
File.binwrite(path, data)
RUBY
gzip -c "${TMP_DIR}/base.raw" > "${FIRMWARE_DIR}/openwrt-x86-64-generic-squashfs-combined.img.gz"

bash "${ROOT_DIR}/scripts/ci/smoke-x86.sh" "${OPENWRT_DIR}" "${FIRMWARE_DIR}" "${WORK_DIR}" "x86_64_fixture" >/dev/null

for required in summary.txt partition-table.txt image.raw qemu.log; do
  if [ ! -f "${WORK_DIR}/smoke-x86/${required}" ]; then
    echo "ERROR: missing smoke-x86 artifact: ${required}" >&2
    exit 1
  fi
done

grep -q 'Mode: static' "${WORK_DIR}/smoke-x86/summary.txt"
grep -q 'Partition table: MBR' "${WORK_DIR}/smoke-x86/partition-table.txt"
grep -q 'Static checks: passed' "${WORK_DIR}/smoke-x86/summary.txt"

echo "x86 smoke fixture test passed."
