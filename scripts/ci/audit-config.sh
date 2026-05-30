#!/usr/bin/env bash
set -euo pipefail

OPENWRT_PATH="${1:-${OPENWRT_PATH:-}}"
WORKSPACE="${2:-${GITHUB_WORKSPACE:-$(pwd)}}"
PROFILE_ID="${3:-${PROFILE_ID:-unknown}}"

if [ -z "${OPENWRT_PATH}" ] || [ ! -f "${OPENWRT_PATH}/.config" ]; then
  echo "ERROR: OpenWrt .config not found: ${OPENWRT_PATH}/.config" >&2
  exit 1
fi

config_value() {
  local option="$1"
  awk -v option="${option}" '
    $0 == "# " option " is not set" { value="n"; next }
    index($0, option "=") == 1 { value=substr($0, length(option) + 2); next }
    END { if (value != "") print value }
  ' "${OPENWRT_PATH}/.config"
}

require_value() {
  local option="$1"
  local expected="$2"
  local actual

  actual="$(config_value "${option}")"
  if [ "${actual}" != "${expected}" ]; then
    echo "ERROR: ${PROFILE_ID} requires ${option}=${expected}, got ${actual:-unset}" >&2
    exit 1
  fi
}

forbidden_enabled() {
  local option="$1"
  local actual

  actual="$(config_value "${option}")"
  if [ "${actual}" = "y" ]; then
    echo "ERROR: ${PROFILE_ID} must not enable ${option}" >&2
    exit 1
  fi
}

mkdir -p "${WORKSPACE}/config-audit"
cp "${OPENWRT_PATH}/.config" "${WORKSPACE}/config-audit/requested.config"
if (cd "${OPENWRT_PATH}" && make defconfig >/dev/null); then
  cp "${OPENWRT_PATH}/.config" "${WORKSPACE}/config-audit/defconfig.config"
  if (cd "${OPENWRT_PATH}" && ./scripts/diffconfig.sh > "${WORKSPACE}/config-audit/diffconfig" 2>/dev/null); then
    :
  else
    echo "WARNING: unable to generate diffconfig." >&2
  fi
else
  echo "WARNING: make defconfig failed during audit; keeping pre-defconfig effective config only." >&2
fi

cp "${OPENWRT_PATH}/.config" "${WORKSPACE}/config-audit/effective.config"

if [ "$(config_value CONFIG_TARGET_x86_64)" = "y" ]; then
  require_value CONFIG_TARGET_KERNEL_PARTSIZE 128
  require_value CONFIG_TARGET_ROOTFS_PARTSIZE 1024
  require_value CONFIG_TARGET_ROOTFS_EXT4FS y
  require_value CONFIG_GRUB_IMAGES y
  require_value CONFIG_GRUB_EFI_IMAGES y
  require_value CONFIG_PACKAGE_irqbalance y
  require_value CONFIG_PACKAGE_kmod-nft-offload y
  forbidden_enabled CONFIG_VMDK_IMAGES
  forbidden_enabled CONFIG_VDI_IMAGES
  forbidden_enabled CONFIG_VHDX_IMAGES
  forbidden_enabled CONFIG_QCOW2_IMAGES
fi

if [ "$(config_value CONFIG_PACKAGE_luci-app-samba4)" = "y" ]; then
  forbidden_enabled CONFIG_PACKAGE_autosamba
fi

if [ "$(config_value CONFIG_PACKAGE_wireguard-tools)" = "y" ] || [ "$(config_value CONFIG_PACKAGE_luci-proto-wireguard)" = "y" ]; then
  require_value CONFIG_PACKAGE_kmod-wireguard y
fi

require_value CONFIG_PACKAGE_kmod-tcp-bbr y
require_value CONFIG_PACKAGE_kmod-sched y
require_value CONFIG_PACKAGE_kmod-sched-cake y
require_value CONFIG_PACKAGE_kmod-ifb y
require_value CONFIG_PACKAGE_sqm-scripts y
require_value CONFIG_PACKAGE_luci-app-sqm y
require_value CONFIG_PACKAGE_luci y
require_value CONFIG_PACKAGE_luci-base y
require_value CONFIG_PACKAGE_rpcd y
require_value CONFIG_PACKAGE_rpcd-mod-luci y
require_value CONFIG_PACKAGE_uhttpd y
require_value CONFIG_PACKAGE_uhttpd-mod-ubus y

forbidden_enabled CONFIG_TARGET_MULTI_PROFILE
forbidden_enabled CONFIG_TARGET_PER_DEVICE_ROOTFS

{
  echo "Profile: ${PROFILE_ID}"
  echo "Target x86_64: $(config_value CONFIG_TARGET_x86_64 || true)"
  echo "Samba4: $(config_value CONFIG_PACKAGE_luci-app-samba4 || true)"
  echo "autosamba: $(config_value CONFIG_PACKAGE_autosamba || true)"
  echo "WireGuard kmod: $(config_value CONFIG_PACKAGE_kmod-wireguard || true)"
  echo "irqbalance: $(config_value CONFIG_PACKAGE_irqbalance || true)"
  echo "TCP BBR: $(config_value CONFIG_PACKAGE_kmod-tcp-bbr || true)"
  echo "SQM scripts: $(config_value CONFIG_PACKAGE_sqm-scripts || true)"
  echo "CAKE scheduler: $(config_value CONFIG_PACKAGE_kmod-sched-cake || true)"
  echo "LuCI meta: $(config_value CONFIG_PACKAGE_luci || true)"
  echo "uHTTPd: $(config_value CONFIG_PACKAGE_uhttpd || true)"
  echo "uHTTPd ubus: $(config_value CONFIG_PACKAGE_uhttpd-mod-ubus || true)"
  echo "rpcd luci: $(config_value CONFIG_PACKAGE_rpcd-mod-luci || true)"
} > "${WORKSPACE}/config-audit/summary.txt"

echo "Config audit passed for ${PROFILE_ID}."
