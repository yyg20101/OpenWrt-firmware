#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

github_output_value() {
  local file="$1"
  local key="$2"

  awk -v wanted="${key}" '
    $0 ~ "^" wanted "<<" {
      delimiter = substr($0, index($0, "<<") + 2)
      getline
      print
      exit
    }
  ' "${file}"
}

run_release_skip() {
  local name="$1"
  local fixture="$2"
  local source_commit="${3:-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}"
  local profile_hash="${4:-profilehash}"
  local output_file="${TMP_DIR}/${name}.out"

  PROFILE_ID="x86_64_immortalWrt" \
  SOURCE_SLUG="immortalwrt_immortalwrt" \
  REPO_BRANCH="openwrt-25.12" \
  SOURCE_COMMIT="${source_commit}" \
  PROFILE_HASH="${profile_hash}" \
  RELEASE_SKIP_FIXTURE_JSON="${fixture}" \
    bash "${ROOT_DIR}/scripts/ci/release-skip.sh" check "${output_file}" >/dev/null

  printf '%s\n' "${output_file}"
}

matching_fixture='{"body":"| Field | Value |\n|-------|-------|\n| Source commit | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |\n| Profile hash | profilehash |","assets":[{"name":"sha256sums.txt"},{"name":"openwrt.img.gz"}]}'
changed_commit_fixture='{"body":"| Source commit | bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb |\n| Profile hash | profilehash |","assets":[{"name":"sha256sums.txt"}]}'
missing_asset_fixture='{"body":"| Source commit | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa |\n| Profile hash | profilehash |","assets":[{"name":"openwrt.img.gz"}]}'

out_file="$(run_release_skip matching "${matching_fixture}")"
[ "$(github_output_value "${out_file}" skip)" = "true" ]
[ "$(github_output_value "${out_file}" reason)" = "existing-release-matches-source-and-profile" ]
[ "$(github_output_value "${out_file}" release_tag)" = "firmware-x86_64_immortalWrt-immortalwrt_immortalwrt-openwrt-25.12" ]

out_file="$(run_release_skip changed "${changed_commit_fixture}")"
[ "$(github_output_value "${out_file}" skip)" = "false" ]
[ "$(github_output_value "${out_file}" reason)" = "source-commit-changed" ]

out_file="$(run_release_skip missing_asset "${missing_asset_fixture}")"
[ "$(github_output_value "${out_file}" skip)" = "false" ]
[ "$(github_output_value "${out_file}" reason)" = "release-assets-incomplete" ]

echo "Release skip fixture test passed."
