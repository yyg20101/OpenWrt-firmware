#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

FAKE_BIN="${TMP_DIR}/bin"
mkdir -p "${FAKE_BIN}"

bash "${ROOT_DIR}/scripts/ci/optimization-report.sh" summary "${ROOT_DIR}" > "${TMP_DIR}/summary.md"
grep -q "Enabled profiles" "${TMP_DIR}/summary.md"
grep -q "Packages.tar.gz must be retained" "${TMP_DIR}/summary.md"

cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "${FAKE_RELEASE_MODE:-pass}" = "vm" ]; then
  printf '%s\n' \
    "Packages.tar.gz" \
    "build.config" \
    "openwrt-x86-64-generic-squashfs-combined.vmdk.gz"
else
  printf '%s\n' \
    "Packages.tar.gz" \
    "build.config" \
    "openwrt-x86-64-generic-squashfs-combined.img.gz"
fi
EOF
chmod +x "${FAKE_BIN}/gh"

PATH="${FAKE_BIN}:${PATH}" \
  bash "${ROOT_DIR}/scripts/ci/optimization-report.sh" release "owner/repo" "firmware-test" > "${TMP_DIR}/release-pass.md"
grep -q "Packages.tar.gz | present" "${TMP_DIR}/release-pass.md"
grep -q "VM image formats | absent" "${TMP_DIR}/release-pass.md"

if PATH="${FAKE_BIN}:${PATH}" FAKE_RELEASE_MODE=vm \
  bash "${ROOT_DIR}/scripts/ci/optimization-report.sh" release "owner/repo" "firmware-test" >"${TMP_DIR}/release-fail.log" 2>&1; then
  echo "ERROR: release report passed with VM-specific disk image assets" >&2
  exit 1
fi
grep -q "contains VM-specific disk image assets" "${TMP_DIR}/release-fail.log"

echo "Optimization report fixture test passed."
