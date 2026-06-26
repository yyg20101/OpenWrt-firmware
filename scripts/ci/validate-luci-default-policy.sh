#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
PROFILES="${ROOT_DIR}/devices/profiles.yml"
REMOVED_FRAGMENT="${ROOT_DIR}/scripts/common/config/luci-zh-cn.config"

if [ -f "${REMOVED_FRAGMENT}" ]; then
  echo "ERROR: local LuCI Chinese defaults fragment must not exist: ${REMOVED_FRAGMENT}" >&2
  exit 1
fi

if [ ! -f "${PROFILES}" ]; then
  echo "ERROR: missing file: ${PROFILES}" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "yaml"
require "pathname"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
profiles_path = root.join("devices/profiles.yml")
cfg = YAML.load_file(profiles_path.to_s) || {}
profiles = cfg.fetch("profiles", {})
errors = []

profiles.each do |id, profile|
  next if profile.fetch("enabled", true) == false

  fragments = Array(profile["config_fragments"])
  if fragments.include?("scripts/common/config/luci-zh-cn.config")
    errors << "#{id}: must not include removed luci-zh-cn.config"
  end

  feeds_conf = profile["feeds_conf"].to_s.strip
  unless feeds_conf.empty?
    errors << "#{id}: should use upstream feeds.conf.default, not local feeds_conf=#{feeds_conf}"
  end
end

if errors.any?
  warn "ERROR: LuCI default policy violation(s):"
  errors.each { |error| warn "  #{error}" }
  exit 1
end

puts "Validated LuCI default policy for #{profiles.count} firmware profile(s)"
RUBY

MATCHES_FILE="$(mktemp)"
trap 'rm -f "${MATCHES_FILE}"' EXIT

if grep -RInE '^CONFIG_LUCI_LANG_|^CONFIG_PACKAGE_luci-i18n-' "${ROOT_DIR}/devices" "${ROOT_DIR}/scripts/common/config" >"${MATCHES_FILE}" 2>/dev/null; then
  echo "ERROR: local device/config fragments must not force LuCI language or i18n packages." >&2
  cat "${MATCHES_FILE}" >&2
  exit 1
fi
