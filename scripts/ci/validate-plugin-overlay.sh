#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
BASE_CONFIG="${ROOT_DIR}/scripts/common/config/base.config"
LEDE_EXTRA_CONFIG="${ROOT_DIR}/scripts/common/config/lede-extra.config"
IMMORTALWRT_EXTRA_CONFIG="${ROOT_DIR}/scripts/common/config/immortalwrt-extra.config"
PACKAGE_OVERLAY="${ROOT_DIR}/scripts/common/package"
PROFILES_FILE="${ROOT_DIR}/devices/profiles.yml"

require_contains() {
  local file="$1"
  local pattern="$2"

  if ! grep -Fq "${pattern}" "${file}"; then
    echo "ERROR: ${file} must contain: ${pattern}" >&2
    exit 1
  fi
}

require_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -Fq "${pattern}" "${file}"; then
    echo "ERROR: ${file} must not contain: ${pattern}" >&2
    exit 1
  fi
}

require_config_only_in() {
  local option="$1"
  local allowed_file="$2"
  local match

  while IFS= read -r match; do
    [ -z "${match}" ] && continue
    if [ "${match%%:*}" != "${allowed_file}" ]; then
      echo "ERROR: ${option}=y must only appear in ${allowed_file}, found: ${match}" >&2
      exit 1
    fi
  done < <(grep -R -n -F "${option}=y" "${ROOT_DIR}/scripts/common/config" 2>/dev/null || true)
}

for option in \
  CONFIG_PACKAGE_luci-app-alist \
  CONFIG_PACKAGE_luci-app-gecoosac \
  CONFIG_PACKAGE_luci-app-mini-diskmanager \
  CONFIG_PACKAGE_luci-app-partexp \
  CONFIG_PACKAGE_luci-app-passwall \
  CONFIG_PACKAGE_luci-app-wolplus
do
  require_contains "${BASE_CONFIG}" "${option}=y"
done

for option in \
  CONFIG_PACKAGE_luci-app-msd_lite \
  CONFIG_PACKAGE_luci-app-mwan3 \
  CONFIG_PACKAGE_luci-app-mwan3helper \
  CONFIG_PACKAGE_luci-app-openvpn \
  CONFIG_PACKAGE_luci-app-openvpn-server \
  CONFIG_PACKAGE_luci-app-qbittorrent \
  CONFIG_PACKAGE_luci-app-syncdial
do
  require_contains "${LEDE_EXTRA_CONFIG}" "${option}=y"
done

require_not_contains "${BASE_CONFIG}" "CONFIG_PACKAGE_luci-app-openvpn=y"
require_not_contains "${BASE_CONFIG}" "CONFIG_PACKAGE_luci-app-openvpn-server=y"
require_not_contains "${IMMORTALWRT_EXTRA_CONFIG}" "CONFIG_PACKAGE_luci-app-openvpn=y"
require_not_contains "${IMMORTALWRT_EXTRA_CONFIG}" "CONFIG_PACKAGE_luci-app-openvpn-server=y"
require_config_only_in "CONFIG_PACKAGE_luci-app-openvpn" "${LEDE_EXTRA_CONFIG}"
require_config_only_in "CONFIG_PACKAGE_luci-app-openvpn-server" "${LEDE_EXTRA_CONFIG}"

require_contains "${PACKAGE_OVERLAY}" 'lede|immortalwrt|openwrt-6.x)'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-alist" "sbwml/luci-app-alist" "main" "all" "alist"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main" "all" "gecoosac"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-mini-diskmanager" "4IceG/luci-app-mini-diskmanager" "main" "all"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-partexp" "sirpdboy/luci-app-partexp" "main" "all"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-wolplus" "animegasan/luci-app-wolplus" "main" "root"'
require_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-mwan3helper" "kenzok8/small-package" "main" "pkg"'
require_not_contains "${PACKAGE_OVERLAY}" 'UPDATE_PACKAGE "luci-app-openvpn"'

ruby -ryaml -e '
  root = ARGV.fetch(0)
  profiles_file = ARGV.fetch(1)
  cfg = YAML.load_file(profiles_file)
  defaults = cfg.fetch("defaults", {})
  profiles = cfg.fetch("profiles", {})
  supported_sources = %w[lede immortalwrt openwrt-6.x]

  profiles.each do |id, raw_profile|
    next if raw_profile.fetch("enabled", true) == false

    profile = defaults.merge(raw_profile) do |key, default_value, override|
      key == "config_fragments" ? Array(default_value) + Array(override) : override
    end

    source_name = profile.fetch("source_repo").sub(%r{\.git\z}, "").split("/").last
    unless supported_sources.include?(source_name)
      warn "ERROR: profile #{id} source #{source_name} is not covered by plugin overlay policy"
      exit 1
    end

    fragments = Array(profile["config_fragments"])
    %w[
      scripts/common/config/base.config
      scripts/common/config/proxy.config
      scripts/common/config/luci-zh-cn.config
      scripts/common/config/samba.config
    ].each do |fragment|
      unless fragments.include?(fragment)
        warn "ERROR: profile #{id} must include #{fragment}"
        exit 1
      end
    end

    has_lede_extra = fragments.include?("scripts/common/config/lede-extra.config")
    if source_name == "lede"
      unless has_lede_extra
        warn "ERROR: LEDE profile #{id} must include lede-extra.config"
        exit 1
      end
    elsif has_lede_extra
      warn "ERROR: non-LEDE profile #{id} must not include lede-extra.config"
      exit 1
    end
  end
' "${ROOT_DIR}" "${PROFILES_FILE}"

echo "Plugin overlay policy validated."
