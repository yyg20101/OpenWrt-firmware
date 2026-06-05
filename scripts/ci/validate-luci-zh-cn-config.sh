#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
FRAGMENT="${ROOT_DIR}/scripts/common/config/luci-zh-cn.config"
PROFILES="${ROOT_DIR}/devices/profiles.yml"

require_file() {
  local file="$1"
  if [ ! -f "${file}" ]; then
    echo "ERROR: missing file: ${file}" >&2
    exit 1
  fi
}

require_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -Fq "${pattern}" "${file}"; then
    echo "ERROR: ${file} must contain: ${pattern}" >&2
    exit 1
  fi
}

require_file "${FRAGMENT}"
require_file "${PROFILES}"

require_contains "${FRAGMENT}" "CONFIG_LUCI_LANG_zh_Hans=y"
if grep -Fq "CONFIG_LUCI_LANG_zh-cn=y" "${FRAGMENT}"; then
  echo "ERROR: ${FRAGMENT} should use the active upstream LuCI zh_Hans language symbol, not the legacy zh-cn symbol" >&2
  exit 1
fi
if grep -Eq '^CONFIG_PACKAGE_luci-i18n-[A-Za-z0-9_.+-]+-zh-cn=y$' "${FRAGMENT}"; then
  echo "ERROR: ${FRAGMENT} should select the official LuCI language option, not hard-code per-module i18n packages" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
cfg = YAML.load_file(root.join("devices/profiles.yml").to_s) || {}
profiles = cfg.fetch("profiles", {})
missing = []
feeds_overrides = []

profiles.each do |id, profile|
  next if profile.fetch("enabled", true) == false

  fragments = Array(profile["config_fragments"])
  missing << id unless fragments.include?("scripts/common/config/luci-zh-cn.config")

  feeds_conf = profile["feeds_conf"].to_s.strip
  unless feeds_conf.empty?
    feeds_overrides << "#{id}: #{feeds_conf}"
  end
end

if missing.any?
  warn "ERROR: enabled profiles missing luci-zh-cn.config: #{missing.join(", ")}"
  exit 1
end

if feeds_overrides.any?
  warn "ERROR: enabled profiles should use upstream feeds.conf.default, not local feeds_conf overrides: #{feeds_overrides.join(", ")}"
  exit 1
end

puts "Validated LuCI zh-cn config for #{profiles.count} firmware profile(s)"
RUBY
