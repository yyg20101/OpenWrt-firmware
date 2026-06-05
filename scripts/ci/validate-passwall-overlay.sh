#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
PACKAGE_BASE="${ROOT_DIR}/scripts/common/Packages.sh"
PACKAGE_OVERLAY="${ROOT_DIR}/scripts/common/package"

require_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "${pattern}" "${file}"; then
    echo "ERROR: ${file} must contain: ${pattern}" >&2
    exit 1
  fi
}

require_not_contains() {
  local file="$1"
  local pattern="$2"
  if grep -Fq "${pattern}" "${file}"; then
    echo "ERROR: ${file} must not contain: ${pattern}" >&2
    exit 1
  fi
}

require_contains "${PACKAGE_BASE}" 'AUTO_LATEST_TAG="${AUTO_LATEST_TAG:-false}"'
require_contains "${PACKAGE_BASE}" "latest-required"
require_contains "${PACKAGE_BASE}" "UPDATE_PACKAGE_LATEST_TAG()"
require_contains "${PACKAGE_BASE}" 'UPDATE_PACKAGE "$1" "$2" "$3" "${4:-}" "${5:-}" "latest-required"'

require_contains "${PACKAGE_OVERLAY}" 'lede|immortalwrt|openwrt-6.x)'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "passwall-packages" "Openwrt-Passwall/openwrt-passwall-packages" "main" "all"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE_LATEST_TAG "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg" "luci-app-passwall"'
require_not_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall"'

echo "PassWall overlay policy validated."
