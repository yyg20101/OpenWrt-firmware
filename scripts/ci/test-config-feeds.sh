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
mkdir -p "${OPENWRT_DIR}" "${WORK_DIR}/files/etc/uci-defaults" "${OPENWRT_DIR}/files/old"

echo "old" > "${OPENWRT_DIR}/files/old/stale"
echo "overlay" > "${WORK_DIR}/files/etc/uci-defaults/99-test"
echo "CONFIG_TEST=y" > "${WORK_DIR}/effective.config"

bash "${ROOT_DIR}/scripts/ci/config-feeds.sh" load-custom-configuration "${OPENWRT_DIR}" "${WORK_DIR}" ""

if [ ! -f "${OPENWRT_DIR}/files/etc/uci-defaults/99-test" ]; then
  echo "ERROR: files overlay was not copied into OpenWrt tree" >&2
  exit 1
fi

if [ ! -f "${WORK_DIR}/files/etc/uci-defaults/99-test" ]; then
  echo "ERROR: files overlay should be copied, not moved from workspace" >&2
  exit 1
fi

if [ -e "${OPENWRT_DIR}/files/old/stale" ]; then
  echo "ERROR: stale OpenWrt files overlay was not replaced" >&2
  exit 1
fi

if ! grep -q '^CONFIG_TEST=y$' "${OPENWRT_DIR}/.config"; then
  echo "ERROR: effective config was not restored" >&2
  exit 1
fi

echo "Config feeds fixture test passed."
