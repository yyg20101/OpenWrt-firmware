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
EOF

touch \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined.img.gz" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined-efi.img.gz" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined.vmdk" \
  "${TARGET_DIR}/openwrt-x86-64-generic-squashfs-combined-efi.vmdk"

touch "${OPENWRT_DIR}/bin/packages/a/b/example.ipk"
cat > "${OPENWRT_DIR}/package-source-manifest.tsv" <<'EOF'
package	repository	ref	commit	mode
passwall	Openwrt-Passwall/openwrt-passwall	main	1234567890abcdef	pkg
table-safe	example/repo	feature|pipe	abcdef1234567890	name
EOF

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

if find "${FIRMWARE_PATH}" -maxdepth 1 -type f \( -name "*.vmdk" -o -name "*.vdi" -o -name "*.vhd" -o -name "*.vhdx" -o -name "*.qcow2" \) -print -quit | grep -q .; then
  echo "ERROR: VM-specific disk image artifact was not pruned." >&2
  exit 1
fi

assert_match '^Packages\.tar\.gz$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_match '^sha256sums\.txt$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_no_match '\.vmdk$|\.vdi$|\.vhd$|\.vhdx$|\.qcow2$' "${FIRMWARE_PATH}/artifact-manifest.txt"
assert_no_match 'Packages\.tar\.gz|build\.config|package-source-manifest\.tsv|\.vmdk|\.vdi|\.vhd|\.vhdx|\.qcow2' "${FIRMWARE_PATH}/sha256sums.txt"
assert_match '^packages/$' <(tar -tzf "${FIRMWARE_PATH}/Packages.tar.gz")
assert_match '^packages/example\.ipk$' <(tar -tzf "${FIRMWARE_PATH}/Packages.tar.gz")
assert_match '## Package Sources' "${WORK_DIR}/release-body.md"
assert_match 'Openwrt-Passwall/openwrt-passwall' "${WORK_DIR}/release-body.md"
assert_match 'feature\\\|pipe' "${WORK_DIR}/release-body.md"

echo "Artifact and release fixture test passed."
