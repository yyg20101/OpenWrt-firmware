#!/usr/bin/env bash
set -euo pipefail

append_env_line() {
  local target="$1"
  local line="$2"
  if [ -n "${target}" ]; then
    echo "${line}" >> "${target}"
  fi
}

generate_release_tag() {
  local output_target="${1:-${GITHUB_OUTPUT:-}}"
  local release_tag

  release_tag="$(date +"%Y.%m.%d-%H%M")"
  append_env_line "${output_target}" "release_tag=${release_tag}"
}

prepare_release_metadata() {
  local workspace="$1"
  local env_target="${2:-${GITHUB_ENV:-}}"
  local source_repo="$3"
  local repo_branch="$4"
  local firmware_tag="$5"
  local model="$6"
  local repo_url="$7"
  local default_ip="$8"
  local default_ip_source="$9"
  local default_password="${10}"
  local default_password_source="${11}"
  local version_info="${12}"
  local release_name="${source_repo}-${repo_branch}-${firmware_tag}-${model}"
  local release_tag="${release_name}"
  local body_file="${workspace}/release-body.md"

  cat > "${body_file}" <<EOF
**This is OpenWrt Firmware for ${firmware_tag} (${model})**
### 📒 固件信息 / Firmware Info (${firmware_tag})
- 💻 设备 / Device: ${model}
- 🧩 平台 / Platform: ${firmware_tag}
- ⚽ 源码 / Source: ${repo_url}
- 💝 分支 / Branch: ${repo_branch}
- 🌐 默认地址 / Default IP: ${default_ip}
- 🌐 默认地址来源 / Default IP Source: ${default_ip_source}
- 🔑 默认密码状态 / Default Password State: ${default_password}
- 🔑 默认密码来源 / Default Password Source: ${default_password_source}
### 🧊 固件版本 / Build Version
- ${version_info}
EOF

  append_env_line "${env_target}" "RELEASE_NAME=${release_name}"
  append_env_line "${env_target}" "RELEASE_TAG=${release_tag}"
  append_env_line "${env_target}" "RELEASE_BODY_FILE=${body_file}"
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  generate-release-tag)
    generate_release_tag "${2:-${GITHUB_OUTPUT:-}}"
    ;;
  prepare-release-metadata)
    prepare_release_metadata \
      "${2:-${GITHUB_WORKSPACE:-$(pwd)}}" \
      "${3:-${GITHUB_ENV:-}}" \
      "${4:-}" \
      "${5:-}" \
      "${6:-}" \
      "${7:-}" \
      "${8:-}" \
      "${9:-}" \
      "${10:-}" \
      "${11:-}" \
      "${12:-}" \
      "${13:-}"
    ;;
  *)
    echo "Usage: $0 <subcommand> [args...]" >&2
    echo "Subcommands: generate-release-tag, prepare-release-metadata" >&2
    exit 1
    ;;
esac
