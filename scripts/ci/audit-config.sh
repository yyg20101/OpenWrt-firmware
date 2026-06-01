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

require_luci_theme() {
  if ! awk '
    /^CONFIG_PACKAGE_luci-theme-[A-Za-z0-9_.+-]+=y$/ {
      found=1
    }
    END {
      exit found ? 0 : 1
    }
  ' "${OPENWRT_PATH}/.config"; then
    echo "ERROR: ${PROFILE_ID} requires at least one LuCI theme selected after defconfig" >&2
    exit 1
  fi
}

require_file() {
  local path="$1"
  local description="$2"

  if [ ! -f "${path}" ]; then
    echo "ERROR: ${PROFILE_ID} requires ${description}: ${path}" >&2
    exit 1
  fi
}

performance_defaults_overlay="${WORKSPACE}/files/etc/uci-defaults/99-performance-defaults"
require_file "${performance_defaults_overlay}" "runtime performance defaults overlay"

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
  require_value CONFIG_PACKAGE_luci-app-irqbalance y
  require_value CONFIG_PACKAGE_amd64-microcode y
  require_value CONFIG_PACKAGE_intel-microcode y
  require_value CONFIG_PACKAGE_kmod-nft-offload y
  require_value CONFIG_PACKAGE_kmod-e1000e y
  require_value CONFIG_PACKAGE_kmod-igb y
  require_value CONFIG_PACKAGE_kmod-igc y
  require_value CONFIG_PACKAGE_kmod-ixgbe y
  require_value CONFIG_PACKAGE_kmod-r8125 y
  require_value CONFIG_PACKAGE_kmod-r8169 y
  require_value CONFIG_PACKAGE_kmod-ata-ahci y
  require_value CONFIG_PACKAGE_kmod-nvme y
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
require_luci_theme

forbidden_enabled CONFIG_TARGET_MULTI_PROFILE
forbidden_enabled CONFIG_TARGET_PER_DEVICE_ROOTFS

{
  echo "Profile: ${PROFILE_ID}"
  echo "Target x86_64: $(config_value CONFIG_TARGET_x86_64 || true)"
  echo "Samba4: $(config_value CONFIG_PACKAGE_luci-app-samba4 || true)"
  echo "autosamba: $(config_value CONFIG_PACKAGE_autosamba || true)"
  echo "WireGuard kmod: $(config_value CONFIG_PACKAGE_kmod-wireguard || true)"
  echo "irqbalance: $(config_value CONFIG_PACKAGE_irqbalance || true)"
  echo "LuCI irqbalance: $(config_value CONFIG_PACKAGE_luci-app-irqbalance || true)"
  echo "AMD microcode: $(config_value CONFIG_PACKAGE_amd64-microcode || true)"
  echo "Intel microcode: $(config_value CONFIG_PACKAGE_intel-microcode || true)"
  echo "x86 NIC e1000e: $(config_value CONFIG_PACKAGE_kmod-e1000e || true)"
  echo "x86 NIC igb: $(config_value CONFIG_PACKAGE_kmod-igb || true)"
  echo "x86 NIC igc: $(config_value CONFIG_PACKAGE_kmod-igc || true)"
  echo "x86 NIC ixgbe: $(config_value CONFIG_PACKAGE_kmod-ixgbe || true)"
  echo "x86 NIC r8125: $(config_value CONFIG_PACKAGE_kmod-r8125 || true)"
  echo "x86 NIC r8169: $(config_value CONFIG_PACKAGE_kmod-r8169 || true)"
  echo "x86 virtio core: $(config_value CONFIG_PACKAGE_kmod-virtio || true)"
  echo "x86 virtio net: $(config_value CONFIG_PACKAGE_kmod-virtio-net || true)"
  echo "x86 virtio pci: $(config_value CONFIG_PACKAGE_kmod-virtio-pci || true)"
  echo "x86 virtio random: $(config_value CONFIG_PACKAGE_kmod-virtio-random || true)"
  echo "x86 AHCI: $(config_value CONFIG_PACKAGE_kmod-ata-ahci || true)"
  echo "x86 NVMe: $(config_value CONFIG_PACKAGE_kmod-nvme || true)"
  echo "TCP BBR: $(config_value CONFIG_PACKAGE_kmod-tcp-bbr || true)"
  echo "SQM scripts: $(config_value CONFIG_PACKAGE_sqm-scripts || true)"
  echo "CAKE scheduler: $(config_value CONFIG_PACKAGE_kmod-sched-cake || true)"
  echo "Performance defaults overlay: present"
  echo "LuCI meta: $(config_value CONFIG_PACKAGE_luci || true)"
  echo "LuCI bootstrap theme: $(config_value CONFIG_PACKAGE_luci-theme-bootstrap || true)"
  echo "uHTTPd: $(config_value CONFIG_PACKAGE_uhttpd || true)"
  echo "uHTTPd ubus: $(config_value CONFIG_PACKAGE_uhttpd-mod-ubus || true)"
  echo "rpcd luci: $(config_value CONFIG_PACKAGE_rpcd-mod-luci || true)"
  echo "LuCI themes:"
  awk -F= '/^CONFIG_PACKAGE_luci-theme-[A-Za-z0-9_.+-]+=y$/ { print "  " $1 }' "${OPENWRT_PATH}/.config" | sort
} > "${WORKSPACE}/config-audit/summary.txt"

echo "Config audit passed for ${PROFILE_ID}."
