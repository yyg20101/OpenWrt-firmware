#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

OPENWRT_DIR="${TMP_DIR}/openwrt"
WORK_DIR="${TMP_DIR}/work"
TARGET_DIR="${OPENWRT_DIR}/bin/targets/x86/64"

mkdir -p "${TARGET_DIR}" "${OPENWRT_DIR}/bin/packages/a/b" "${WORK_DIR}"

cat > "${OPENWRT_DIR}/.config" <<'EOF'
CONFIG_TARGET_x86_64=y
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_TARGET_KERNEL_PARTSIZE=128
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
EOF

touch \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined.img.gz" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined-efi.img.gz" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined.vmdk" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined-efi.vmdk"

touch \
  "${OPENWRT_DIR}/bin/packages/a/b/example.ipk" \
  "${OPENWRT_DIR}/bin/packages/a/b/luci-i18n-base-zh-cn_1_all.ipk"
cat > "${OPENWRT_DIR}/package-source-manifest.tsv" <<'EOF'
package	repository	ref	commit	mode
passwall	Openwrt-Passwall/openwrt-passwall	main	1234567890abcdef	pkg
table-safe	example/repo	feature|pipe	abcdef1234567890	name
EOF
cat > "${WORK_DIR}/build-environment-provenance.md" <<'EOF'
# Build Environment Provenance

| Field | Value |
|-------|-------|
| Init script URL | https://example.invalid/init.sh |
| Init script sha256 | abcdef123456 |
EOF

PROFILE_ID=x86_64_LEDE \
REPO_URL=https://github.com/coolsnowwolf/lede \
SOURCE_REPO=lede \
SOURCE_SLUG=coolsnowwolf_lede \
REPO_BRANCH=master \
GITHUB_WORKSPACE="${WORK_DIR}" \
bash "${ROOT_DIR}/scripts/ci/build-artifacts.sh" organize-firmware-files "${OPENWRT_DIR}" "${TMP_DIR}/env" "${TMP_DIR}/out"
FIRMWARE_PATH="$(awk -F= '$1 == "firmware_path" { print substr($0, index($0, "=") + 1) }' "${TMP_DIR}/out")"
bash "${ROOT_DIR}/scripts/ci/build-artifacts.sh" generate-sha256 "${FIRMWARE_PATH}"

PROFILE_ID=x86_64_fixture \
PROFILE_TITLE="x86_64 Fixture" \
SOURCE_REPO=fixture \
SOURCE_SLUG=fixture \
REPO_BRANCH=main \
FIRMWARE_TAG=X86-64 \
WRT_HASH=abcdef12 \
PROFILE_HASH=1234567890abcdef \
GITHUB_RUN_NUMBER=1 \
  bash "${ROOT_DIR}/scripts/ci/release-maintenance.sh" prepare-release-metadata "${WORK_DIR}" "${TMP_DIR}/env" "${FIRMWARE_PATH}" "${TMP_DIR}/release_out"

assert_file() {
  local file="$1"
  if [ ! -f "${file}" ]; then
    echo "ERROR: expected file missing: ${file}" >&2
    exit 1
  fi
}

assert_no_match() {
  local pattern="$1"
  local file="$2"
  if grep -Eq "${pattern}" "${file}"; then
    echo "ERROR: unexpected pattern '${pattern}' found in ${file}" >&2
    exit 1
  fi
}

assert_match() {
  local pattern="$1"
  local file="$2"
  if ! grep -Eq "${pattern}" "${file}"; then
    echo "ERROR: expected pattern '${pattern}' missing from ${file}" >&2
    exit 1
  fi
}

assert_file "${FIRMWARE_PATH}/Packages.tar.gz"
assert_file "${FIRMWARE_PATH}/build.config"
assert_file "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_file "${FIRMWARE_PATH}/sha256sums.txt"
assert_file "${FIRMWARE_PATH}/package-source-manifest.tsv"
assert_file "${FIRMWARE_PATH}/firmware-size-report.md"
assert_file "${FIRMWARE_PATH}/build-environment-provenance.md"
assert_file "${FIRMWARE_PATH}/compiled-luci-i18n-report.md"

if find "${FIRMWARE_PATH}" -maxdepth 1 -type f \( -name "*.vmdk" -o -name "*.vdi" -o -name "*.vhd" -o -name "*.vhdx" -o -name "*.qcow2" \) -print -quit | grep -q .; then
  echo "ERROR: VM-specific disk image artifact was not pruned." >&2
  exit 1
fi

assert_match '^Packages\.tar\.gz$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_match '^firmware-size-report\.md$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_match '^build-environment-provenance\.md$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_match '^compiled-luci-i18n-report\.md$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_match '^sha256sums\.txt$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_no_match '\.vmdk$|\.vdi$|\.vhd$|\.vhdx$|\.qcow2$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_no_match 'Packages\.tar\.gz|build\.config|package-source-manifest\.tsv|firmware-size-report\.md|build-environment-provenance\.md|\.vmdk|\.vdi|\.vhd|\.vhdx|\.qcow2' "${FIRMWARE_PATH}/sha256sums.txt"
assert_match 'Rootfs partsize.*1024 MiB' "${FIRMWARE_PATH}/firmware-size-report.md"
assert_match '^packages/$' <(tar -tzf "${FIRMWARE_PATH}/Packages.tar.gz")
assert_match '^packages/example\.ipk$' <(tar -tzf "${FIRMWARE_PATH}/Packages.tar.gz")
assert_match '^packages/luci-i18n-base-zh-cn_1_all\.ipk$' <(tar -tzf "${FIRMWARE_PATH}/Packages.tar.gz")
assert_match 'Packages.tar.gz luci-i18n-base-zh-cn.*found' "${FIRMWARE_PATH}/compiled-luci-i18n-report.md"
assert_match '## Size Report' "${WORK_DIR}/release-body.md"
assert_match 'Rootfs partsize.*1024 MiB' "${WORK_DIR}/release-body.md"
assert_match '## Package Sources' "${WORK_DIR}/release-body.md"
assert_match 'Openwrt-Passwall/openwrt-passwall' "${WORK_DIR}/release-body.md"
assert_match 'feature\\\|pipe' "${WORK_DIR}/release-body.md"
assert_match '## Build Environment' "${WORK_DIR}/release-body.md"
assert_match 'https://example.invalid/init.sh' "${WORK_DIR}/release-body.md"
assert_match '^release_name<<' "${TMP_DIR}/release_out"
assert_match '^x86_64 Fixture / fixture:main$' "${TMP_DIR}/release_out"
assert_match '^release_tag<<' "${TMP_DIR}/release_out"
assert_match '^firmware-x86_64_fixture-fixture-main$' "${TMP_DIR}/release_out"
assert_no_match 'abcdef12|run1' "${TMP_DIR}/release_out"

MISSING_OPENWRT_DIR="${TMP_DIR}/openwrt-missing-i18n"
MISSING_TARGET_DIR="${MISSING_OPENWRT_DIR}/bin/targets/x86/64"
mkdir -p "${MISSING_TARGET_DIR}" "${MISSING_OPENWRT_DIR}/bin/packages/a/b"
cat > "${MISSING_OPENWRT_DIR}/.config" <<'EOF'
CONFIG_TARGET_x86_64=y
CONFIG_GRUB_EFI_IMAGES=y
CONFIG_TARGET_KERNEL_PARTSIZE=128
CONFIG_TARGET_ROOTFS_PARTSIZE=1024
EOF
touch \
  "${MISSING_TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined.img.gz" \
  "${MISSING_TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined-efi.img.gz" \
  "${MISSING_OPENWRT_DIR}/bin/packages/a/b/example.ipk"

if PROFILE_ID=x86_64_LEDE \
  REPO_URL=https://github.com/coolsnowwolf/lede \
  SOURCE_REPO=lede \
  SOURCE_SLUG=coolsnowwolf_lede \
  REPO_BRANCH=master \
  GITHUB_WORKSPACE="${WORK_DIR}" \
  bash "${ROOT_DIR}/scripts/ci/build-artifacts.sh" organize-firmware-files "${MISSING_OPENWRT_DIR}" "${TMP_DIR}/missing-env" "${TMP_DIR}/missing-out" >"${TMP_DIR}/missing-i18n.log" 2>&1; then
  echo "ERROR: official firmware artifact validation passed without luci-i18n-base-zh-cn package output" >&2
  exit 1
fi
assert_match 'missing luci-i18n-base-zh-cn' "${TMP_DIR}/missing-i18n.log"

mkdir -p "${OPENWRT_DIR}/package/feeds/test/failure"
cat > "${OPENWRT_DIR}/Makefile" <<'EOF'
.PHONY: package/feeds/test/failure/compile
package/feeds/test/failure/compile:
	@echo "verbose rebuild fixture"
EOF
cat > "${TMP_DIR}/compile.log" <<'EOF'
first compile line
package/feeds/test/failure failed to build
last compile line
EOF

bash "${ROOT_DIR}/scripts/ci/build-artifacts.sh" dump-failure-context "${OPENWRT_DIR}" "${TMP_DIR}" >/dev/null
assert_file "${TMP_DIR}/failure-context/compile.log"
assert_file "${TMP_DIR}/failure-context/compile-tail.log"
assert_file "${TMP_DIR}/failure-context/build.config"
assert_file "${TMP_DIR}/failure-context/target-config.txt"
assert_file "${TMP_DIR}/failure-context/package-config.txt"
assert_file "${TMP_DIR}/failure-context/failed-package.txt"
assert_file "${TMP_DIR}/failure-context/verbose-rebuild.log"
assert_match 'Failed package: package/feeds/test/failure' "${TMP_DIR}/failure-context/failed-package.txt"
assert_match 'verbose rebuild fixture' "${TMP_DIR}/failure-context/verbose-rebuild.log"

echo "Artifact and release fixture test passed."
