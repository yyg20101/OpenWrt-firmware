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
	@true
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
CONFIG_PACKAGE_kmod-nft-offload=y
CONFIG_PACKAGE_luci-app-samba4=y
# CONFIG_PACKAGE_autosamba is not set
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

expect_pass
expect_fail_without "CONFIG_PACKAGE_uhttpd" "requires CONFIG_PACKAGE_uhttpd=y"
expect_fail_without "CONFIG_PACKAGE_uhttpd-mod-ubus" "requires CONFIG_PACKAGE_uhttpd-mod-ubus=y"
expect_fail_without "CONFIG_PACKAGE_rpcd-mod-luci" "requires CONFIG_PACKAGE_rpcd-mod-luci=y"
expect_fail_without_theme
expect_fail_without_performance_overlay

echo "Config audit fixture test passed."
