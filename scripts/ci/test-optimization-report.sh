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
grep -q "Profile Sources" "${TMP_DIR}/summary.md"
grep -q "x86_64_LEDE" "${TMP_DIR}/summary.md"

cat > "${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  *"release view"*)
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
    ;;
  *"actions/caches"*)
    printf '%s\t%s\t%s\t%s\n' \
      "ccache-v2-coolsnowwolf_lede-master-x86_64-2026-06" "refs/heads/main" "1048576" "2026-06-01T00:00:00Z" \
      "ccache-v2-immortalwrt_immortalwrt-openwrt-25.12-x86_64-2026-06" "refs/heads/main" "2097152" "2026-06-01T01:00:00Z" \
      "build-accel-v2-coolsnowwolf_lede-master-x86_64-2026-06" "refs/heads/main" "3145728" "2026-06-01T02:00:00Z"
    ;;
  *"repos/owner/repo/releases"*)
    printf '%s\n' \
      '["firmware-x86_64_LEDE-coolsnowwolf_lede-master-aaaaaaaaaaaa-run42","2026-06-01T00:00:00Z","| Source commit | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |"]'
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "${FAKE_BIN}/gh"

cat > "${FAKE_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [ "$1" != "ls-remote" ]; then
  echo "unexpected git invocation: $*" >&2
  exit 1
fi

repo="$3"
branch="$4"
case "${repo} ${branch}" in
  "https://github.com/coolsnowwolf/lede master")
    printf '%s\trefs/heads/master\n' "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    ;;
  "https://github.com/immortalwrt/immortalwrt openwrt-25.12")
    printf '%s\trefs/heads/openwrt-25.12\n' "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    ;;
  "https://github.com/VIKINGYFY/immortalwrt main")
    printf '%s\trefs/heads/main\n' "cccccccccccccccccccccccccccccccccccccccc"
    ;;
  *)
    printf '%s\trefs/heads/%s\n' "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee" "${branch}"
    ;;
esac
EOF
chmod +x "${FAKE_BIN}/git"

PATH="${FAKE_BIN}:${PATH}" \
  bash "${ROOT_DIR}/scripts/ci/optimization-report.sh" profile-drift "${ROOT_DIR}" "owner/repo" > "${TMP_DIR}/profile-drift.md"
grep -q "Profile Upstream Drift" "${TMP_DIR}/profile-drift.md"
grep -q 'x86_64_LEDE.*aaaaaaaaaaaa.*no' "${TMP_DIR}/profile-drift.md"
grep -q "release:firmware-x86_64_LEDE" "${TMP_DIR}/profile-drift.md"

PATH="${FAKE_BIN}:${PATH}" \
  bash "${ROOT_DIR}/scripts/ci/optimization-report.sh" cache "owner/repo" > "${TMP_DIR}/cache.md"
grep -q "Cache Prefix Groups" "${TMP_DIR}/cache.md"
grep -q 'ccache-v2-coolsnowwolf_lede-master-x86_64.*1.*1.00 MiB' "${TMP_DIR}/cache.md"
grep -q 'ccache-v2-immortalwrt_immortalwrt-openwrt-25.12.*1.*2.00 MiB' "${TMP_DIR}/cache.md"
grep -q 'build-accel-v2-coolsnowwolf_lede-master-x86_64.*1.*3.00 MiB' "${TMP_DIR}/cache.md"

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
