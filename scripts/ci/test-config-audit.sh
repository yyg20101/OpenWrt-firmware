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
mkdir -p "${OPENWRT_DIR}" "${WORK_DIR}"
mkdir -p "${WORK_DIR}/files/etc/uci-defaults"
touch "${WORK_DIR}/files/etc/uci-defaults/99-performance-defaults"

cat > "${OPENWRT_DIR}/Makefile" <<'EOF'
.PHONY: defconfig
defconfig:
	@if [ -n "$${DEFCONFIG_DROP_OPTION:-}" ]; then \
		sed -i.bak "/^$${DEFCONFIG_DROP_OPTION}=y$$/d" .config; \
		rm -f .config.bak; \
	fi
EOF

mkdir -p "${OPENWRT_DIR}/scripts"
cat > "${OPENWRT_DIR}/scripts/diffconfig.sh" <<'EOF'
#!/usr/bin/env sh
cat .config
EOF
chmod +x "${OPENWRT_DIR}/scripts/diffconfig.sh"

write_config() {
  local file="$1"

  cat > "${file}" <<'EOF'
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_KERNEL_PARTSIZE=128
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
CONFIG_TARGET_ROOTFS_EXT4FS=y
CONFIG_GRUB_IMAGES=y
CONFIG_GRUB_EFI_IMAGES=y
# CONFIG_VMDK_IMAGES is not set
# CONFIG_VDI_IMAGES is not set
# CONFIG_VHDX_IMAGES is not set
# CONFIG_QCOW2_IMAGES is not set
CONFIG_PACKAGE_irqbalance=y
CONFIG_PACKAGE_luci-app-irqbalance=y
CONFIG_PACKAGE_amd64-microcode=y
CONFIG_PACKAGE_intel-microcode=y
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_kmod-e1000e=y
CONFIG_PACKAGE_kmod-igb=y
CONFIG_PACKAGE_kmod-igc=y
CONFIG_PACKAGE_kmod-ixgbe=y
CONFIG_PACKAGE_kmod-r8125=y
CONFIG_PACKAGE_kmod-r8169=y
CONFIG_PACKAGE_kmod-ata-ahci=y
CONFIG_PACKAGE_kmod-nvme=y
CONFIG_PACKAGE_luci-app-samba4=y
# CONFIG_PACKAGE_autosamba is not set
CONFIG_PACKAGE_luci-app-alist=y
CONFIG_PACKAGE_luci-app-msd_lite=y
CONFIG_PACKAGE_luci-app-passwall=y
CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray=y
CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy=y
CONFIG_PACKAGE_wireguard-tools=y
CONFIG_PACKAGE_luci-proto-wireguard=y
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-tcp-bbr=y
CONFIG_PACKAGE_kmod-sched=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-ifb=y
CONFIG_PACKAGE_sqm-scripts=y
CONFIG_PACKAGE_luci-app-sqm=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-base=y
CONFIG_LUCI_LANG_zh_Hans=y
CONFIG_PACKAGE_luci-i18n-base-zh-cn=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_PACKAGE_rpcd=y
CONFIG_PACKAGE_rpcd-mod-luci=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_uhttpd-mod-ubus=y
# CONFIG_TARGET_MULTI_PROFILE is not set
# CONFIG_TARGET_PER_DEVICE_ROOTFS is not set
EOF
}

expect_pass() {
  write_config "${OPENWRT_DIR}/.config"
  bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-pass" >/dev/null
  if ! grep -q "CONFIG_PACKAGE_luci-app-alist" "${WORK_DIR}/config-audit/summary.txt"; then
    echo "ERROR: requested LuCI app summary omitted luci-app-alist" >&2
    exit 1
  fi
  if ! grep -q "CONFIG_PACKAGE_luci-app-msd_lite" "${WORK_DIR}/config-audit/summary.txt"; then
    echo "ERROR: requested LuCI app summary omitted luci-app-msd_lite" >&2
    exit 1
  fi
  if grep -q "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Xray" "${WORK_DIR}/config-audit/summary.txt"; then
    echo "ERROR: PassWall feature toggles must not be treated as standalone LuCI apps" >&2
    exit 1
  fi
  if grep -q "CONFIG_PACKAGE_luci-app-passwall_Nftables_Transparent_Proxy" "${WORK_DIR}/config-audit/summary.txt"; then
    echo "ERROR: PassWall transparent proxy toggles must not be treated as standalone LuCI apps" >&2
    exit 1
  fi
}

expect_fail_without() {
  local option="$1"
  local message="$2"

  write_config "${OPENWRT_DIR}/.config"
  sed -i.bak "s/^${option}=y$/# ${option} is not set/" "${OPENWRT_DIR}/.config"
  rm -f "${OPENWRT_DIR}/.config.bak"
  if bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-${option}" >"${TMP_DIR}/audit.log" 2>&1; then
    echo "ERROR: audit passed without ${option}" >&2
    exit 1
  fi
  if ! grep -q "${message}" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected audit failure containing '${message}'" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
}

expect_fail_without_theme() {
  write_config "${OPENWRT_DIR}/.config"
  sed -i.bak '/^CONFIG_PACKAGE_luci-theme-.*=y$/d' "${OPENWRT_DIR}/.config"
  rm -f "${OPENWRT_DIR}/.config.bak"
  if bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-theme" >"${TMP_DIR}/audit.log" 2>&1; then
    echo "ERROR: audit passed without a LuCI theme" >&2
    exit 1
  fi
  if ! grep -q "requires at least one LuCI theme" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected missing-theme audit failure" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
}

expect_fail_without_luci_language() {
  write_config "${OPENWRT_DIR}/.config"
  sed -i.bak '/^CONFIG_LUCI_LANG_zh_Hans=y$/d' "${OPENWRT_DIR}/.config"
  rm -f "${OPENWRT_DIR}/.config.bak"
  if bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-luci-language" >"${TMP_DIR}/audit.log" 2>&1; then
    echo "ERROR: audit passed without a LuCI Simplified Chinese language selection" >&2
    exit 1
  fi
  if ! grep -q "requires CONFIG_LUCI_LANG_zh_Hans=y" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected missing-LuCI-language audit failure" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
}

expect_fail_without_performance_overlay() {
  write_config "${OPENWRT_DIR}/.config"
  rm -f "${WORK_DIR}/files/etc/uci-defaults/99-performance-defaults"
  if bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-performance-overlay" >"${TMP_DIR}/audit.log" 2>&1; then
    echo "ERROR: audit passed without runtime performance defaults overlay" >&2
    exit 1
  fi
  if ! grep -q "requires runtime performance defaults overlay" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected missing-performance-overlay audit failure" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
  mkdir -p "${WORK_DIR}/files/etc/uci-defaults"
  touch "${WORK_DIR}/files/etc/uci-defaults/99-performance-defaults"
}

expect_fail_when_defconfig_drops_luci_app() {
  local option="$1"

  write_config "${OPENWRT_DIR}/.config"
  if DEFCONFIG_DROP_OPTION="${option}" bash "${ROOT_DIR}/scripts/ci/audit-config.sh" "${OPENWRT_DIR}" "${WORK_DIR}" "fixture-drop-${option}" >"${TMP_DIR}/audit.log" 2>&1; then
    echo "ERROR: audit passed after defconfig dropped ${option}" >&2
    exit 1
  fi
  if ! grep -q "lost requested LuCI application package" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected requested LuCI app loss failure" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
  if ! grep -q "${option} requested=y effective=unset" "${TMP_DIR}/audit.log"; then
    echo "ERROR: expected audit failure to name ${option}" >&2
    cat "${TMP_DIR}/audit.log" >&2
    exit 1
  fi
}

expect_pass
expect_fail_when_defconfig_drops_luci_app "CONFIG_PACKAGE_luci-app-alist"
expect_fail_when_defconfig_drops_luci_app "CONFIG_PACKAGE_luci-app-msd_lite"
expect_fail_without "CONFIG_PACKAGE_uhttpd" "requires CONFIG_PACKAGE_uhttpd=y"
expect_fail_without "CONFIG_PACKAGE_uhttpd-mod-ubus" "requires CONFIG_PACKAGE_uhttpd-mod-ubus=y"
expect_fail_without "CONFIG_PACKAGE_rpcd-mod-luci" "requires CONFIG_PACKAGE_rpcd-mod-luci=y"
expect_fail_without "CONFIG_PACKAGE_luci-i18n-base-zh-cn" "requires CONFIG_PACKAGE_luci-i18n-base-zh-cn=y"
expect_fail_without "CONFIG_PACKAGE_luci-app-irqbalance" "requires CONFIG_PACKAGE_luci-app-irqbalance=y"
expect_fail_without "CONFIG_PACKAGE_intel-microcode" "requires CONFIG_PACKAGE_intel-microcode=y"
expect_fail_without "CONFIG_PACKAGE_kmod-e1000e" "requires CONFIG_PACKAGE_kmod-e1000e=y"
expect_fail_without "CONFIG_PACKAGE_kmod-nvme" "requires CONFIG_PACKAGE_kmod-nvme=y"
expect_fail_without_theme
expect_fail_without_luci_language
expect_fail_without_performance_overlay

echo "Config audit fixture test passed."
