#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
WORKFLOW="${ROOT_DIR}/.github/workflows/firmware-build.yml"

if [ ! -f "${WORKFLOW}" ]; then
  echo "ERROR: missing workflow: ${WORKFLOW}" >&2
  exit 1
fi

ruby - "${WORKFLOW}" <<'RUBY'
workflow = File.read(ARGV.fetch(0))

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

required = [
  'cache_period="$(date +%Y-%m)"',
  'append_github_value "$GITHUB_ENV" "CACHE_PERIOD" "${cache_period}"',
  'append_github_value "$GITHUB_OUTPUT" "cache_period" "${cache_period}"',
  'steps.source.outputs.cache_period',
  "steps.cache-ccache.outputs.cache-hit != 'true'",
  "steps.cache-build-accel.outputs.cache-hit != 'true'",
  'cache save policy: save when the primary cache key is not an exact hit'
]

required.each do |needle|
  fail!("firmware-build.yml must contain #{needle.inspect}") unless workflow.include?(needle)
end

forbidden = [
  'CACHE_WEEK',
  'cache_week',
  "cache-matched-key == ''"
]

forbidden.each do |needle|
  fail!("firmware-build.yml must not contain #{needle.inspect}") if workflow.include?(needle)
end

ccache_key = 'key: ccache-v2-${{ steps.profile.outputs.source_slug }}-${{ steps.profile.outputs.repo_branch }}-${{ steps.profile.outputs.ccache_group }}-${{ steps.source.outputs.cache_period }}'
ccache_restore = 'ccache-v2-${{ steps.profile.outputs.source_slug }}-${{ steps.profile.outputs.repo_branch }}-${{ steps.profile.outputs.ccache_group }}-'
build_key = 'key: build-accel-v2-${{ steps.profile.outputs.source_slug }}-${{ steps.profile.outputs.repo_branch }}-${{ steps.profile.outputs.ccache_group }}-${{ steps.source.outputs.cache_period }}'
build_restore = 'build-accel-v2-${{ steps.profile.outputs.source_slug }}-${{ steps.profile.outputs.repo_branch }}-${{ steps.profile.outputs.ccache_group }}-'

[ccache_key, ccache_restore, build_key, build_restore].each do |needle|
  fail!("cache key policy must preserve source slug, repo branch, and cache group in #{needle.inspect}") unless workflow.include?(needle)
end

ccache_save = workflow[/name: Save ccache.*?(?=\n      - name:|\z)/m]
build_save = workflow[/name: Save Build Accelerator Cache.*?(?=\n      - name:|\z)/m]

fail!("missing Save ccache step") unless ccache_save
fail!("missing Save Build Accelerator Cache step") unless build_save

expected_ccache_condition = "if: steps.compile.outputs.status == 'success' && github.ref == 'refs/heads/main' && steps.cache-ccache.outputs.cache-hit != 'true'"
expected_build_condition = "if: steps.compile.outputs.status == 'success' && github.ref == 'refs/heads/main' && steps.cache-build-accel.outputs.cache-hit != 'true'"

fail!("Save ccache must save when the primary cache key is not an exact hit") unless ccache_save.include?(expected_ccache_condition)
fail!("Save Build Accelerator Cache must save when the primary cache key is not an exact hit") unless build_save.include?(expected_build_condition)

puts "Cache key policy validation passed."
RUBY
