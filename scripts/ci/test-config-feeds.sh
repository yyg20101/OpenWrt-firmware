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
mkdir -p "${OPENWRT_DIR}/package" "${WORK_DIR}/files/etc/uci-defaults" "${OPENWRT_DIR}/files/old"

echo "old" > "${OPENWRT_DIR}/files/old/stale"
echo "overlay" > "${WORK_DIR}/files/etc/uci-defaults/99-test"
echo "CONFIG_TEST=y" > "${WORK_DIR}/effective.config"
cat > "${WORK_DIR}/Packages.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch local-base-ran
EOF
cat > "${WORK_DIR}/package" <<'EOF'
touch local-overlay-ran
EOF

bash "${ROOT_DIR}/scripts/ci/config-feeds.sh" apply-package-overrides "${OPENWRT_DIR}" "${WORK_DIR}" "Packages.sh" "package"

if [ ! -f "${OPENWRT_DIR}/package-source-manifest.tsv" ]; then
  echo "ERROR: package source manifest was not written for local overlays" >&2
  exit 1
fi

if ! grep -q 'package-base-script	local:Packages.sh' "${OPENWRT_DIR}/package-source-manifest.tsv"; then
  echo "ERROR: base package script provenance missing" >&2
  exit 1
fi

if ! grep -q 'package-overlay-script	local:package' "${OPENWRT_DIR}/package-source-manifest.tsv"; then
  echo "ERROR: package overlay script provenance missing" >&2
  exit 1
fi

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
