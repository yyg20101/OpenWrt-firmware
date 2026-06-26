#!/usr/bin/env bash
set -euo pipefail

append_github_value() {
  local target="$1"
  local key="$2"
  local value="$3"
  local delimiter

  if [ -n "${target}" ]; then
    delimiter="EOF_${key}_${RANDOM}_$(date +%s%N)"
    {
      printf '%s<<%s\n' "${key}" "${delimiter}"
      printf '%s\n' "${value}"
      printf '%s\n' "${delimiter}"
    } >> "${target}"
  fi
}

sanitize() {
  tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//; s/-$//'
}

release_tag() {
  local profile_slug
  local source_slug_safe
  local branch_slug

  profile_slug="$(printf '%s' "${PROFILE_ID:?PROFILE_ID is required}" | sanitize)"
  source_slug_safe="$(printf '%s' "${SOURCE_SLUG:?SOURCE_SLUG is required}" | sanitize)"
  branch_slug="$(printf '%s' "${REPO_BRANCH:?REPO_BRANCH is required}" | sanitize)"
  printf 'firmware-%s-%s-%s\n' "${profile_slug}" "${source_slug_safe}" "${branch_slug}"
}

field_from_body() {
  local body="$1"
  local field="$2"

  awk -F '|' -v wanted="${field}" '
    {
      key = $2
      value = $3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (tolower(key) == tolower(wanted)) {
        print value
        exit
      }
    }
  ' <<< "${body}"
}

load_release_json() {
  local tag="$1"

  if [ -n "${RELEASE_SKIP_FIXTURE_JSON:-}" ]; then
    printf '%s\n' "${RELEASE_SKIP_FIXTURE_JSON}"
    return 0
  fi

  gh release view "${tag}" \
    --repo "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}" \
    --json body,assets
}

check_unchanged_release() {
  local output_target="${1:-${GITHUB_OUTPUT:-}}"
  local tag
  local release_json
  local body
  local previous_source_commit
  local previous_profile_hash
  local asset_count
  local has_sha256
  local skip="false"
  local reason="release-missing"

  tag="$(release_tag)"

  if release_json="$(load_release_json "${tag}" 2>/dev/null)"; then
    body="$(jq -r '.body // ""' <<< "${release_json}")"
    previous_source_commit="$(field_from_body "${body}" "Source commit")"
    previous_profile_hash="$(field_from_body "${body}" "Profile hash")"
    asset_count="$(jq '[.assets[]?] | length' <<< "${release_json}")"
    has_sha256="$(jq -r 'any(.assets[]?; .name == "sha256sums.txt")' <<< "${release_json}")"

    if [ "${previous_source_commit}" != "${SOURCE_COMMIT:?SOURCE_COMMIT is required}" ]; then
      reason="source-commit-changed"
    elif [ "${previous_profile_hash}" != "${PROFILE_HASH:?PROFILE_HASH is required}" ]; then
      reason="profile-hash-changed"
    elif [ "${asset_count}" -eq 0 ] || [ "${has_sha256}" != "true" ]; then
      reason="release-assets-incomplete"
    else
      skip="true"
      reason="existing-release-matches-source-and-profile"
    fi
  fi

  append_github_value "${output_target}" "skip" "${skip}"
  append_github_value "${output_target}" "reason" "${reason}"
  append_github_value "${output_target}" "release_tag" "${tag}"
  printf 'Release skip decision: skip=%s reason=%s tag=%s\n' "${skip}" "${reason}" "${tag}"
}

case "${1:-}" in
  check)
    check_unchanged_release "${2:-${GITHUB_OUTPUT:-}}"
    ;;
  *)
    echo "Usage: $0 check [github-output-file]" >&2
    exit 1
    ;;
esac
