#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
PACKAGE_OVERLAY="${ROOT_DIR}/scripts/common/package"

if [ ! -f "${PACKAGE_OVERLAY}" ]; then
  echo "ERROR: missing package overlay script: ${PACKAGE_OVERLAY}" >&2
  exit 1
fi

ruby - "${PACKAGE_OVERLAY}" <<'RUBY'
package_overlay = File.read(ARGV.fetch(0))

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

small_overlay = 'UPDATE_PACKAGE "small" "kenzok8/small" "master" "all"'
fail!("LEDE package overlay must use kenzok8/small@master in all mode") unless package_overlay.include?(small_overlay)

small_indexes = package_overlay.enum_for(:scan, Regexp.new(Regexp.escape(small_overlay))).map { Regexp.last_match.begin(0) }
fail!("LEDE package overlay must use kenzok8/small@master in all mode") if small_indexes.empty?
small_indexes.each do |small_index|
  branch = package_overlay[0...small_index].scan(/^  ([A-Za-z0-9_.|-]+)\)\n/).last&.first

  fail!("kenzok8/small overlay must be inside a lede-only case block") unless branch == "lede"
end

puts "LEDE small overlay validation passed."
RUBY
