#!/usr/bin/env bash
set -euo pipefail

append_env_line() {
  local target="$1"
  local line="$2"
  if [ -n "${target}" ]; then
    echo "${line}" >> "${target}"
  fi
}

prepare_release_metadata() {
  local workspace="$1"
  local env_target="${2:-${GITHUB_ENV:-}}"
  local firmware_path="${3:-${FIRMWARE_PATH:-}}"
  local output_target="${4:-${GITHUB_OUTPUT:-}}"
  local profile_id="${PROFILE_ID:-unknown-profile}"
  local profile_title="${PROFILE_TITLE:-${profile_id}}"
  local source_repo="${SOURCE_REPO:-unknown-source}"
  local source_slug="${SOURCE_SLUG:-${source_repo}}"
  local repo_branch="${REPO_BRANCH:-unknown-branch}"
  local firmware_tag="${FIRMWARE_TAG:-unknown-platform}"
  local wrt_hash="${WRT_HASH:-unknown}"
  local profile_hash="${PROFILE_HASH:-unknown}"
  local run_number="${GITHUB_RUN_NUMBER:-0}"
  local default_ip="${DEFAULT_IP:-unknown}"
  local default_ip_source="${DEFAULT_IP_SOURCE:-n/a}"
  local default_password="${DEFAULT_PASSWORD:-unknown}"
  local default_password_source="${DEFAULT_PASSWORD_SOURCE:-n/a}"
  local source_commit="${SOURCE_COMMIT:-unknown}"
  local source_commit_date="${SOURCE_COMMIT_DATE:-unknown}"
  local source_commit_subject="${SOURCE_COMMIT_SUBJECT:-unknown}"
  local repo_url="${REPO_URL:-unknown}"
  local branch_slug
  local profile_slug
  local source_slug_safe
  local release_name
  local release_tag
  local body_file="${workspace}/release-body.md"
  local artifact_table="${workspace}/release-artifacts.md"

  if [ -z "${firmware_path}" ] || [ ! -d "${firmware_path}" ]; then
    echo "ERROR: firmware path is missing or invalid: ${firmware_path}" >&2
    exit 1
  fi

  sanitize() {
    tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//; s/-$//'
  }

  profile_slug="$(printf '%s' "${profile_id}" | sanitize)"
  source_slug_safe="$(printf '%s' "${source_slug}" | sanitize)"
  branch_slug="$(printf '%s' "${repo_branch}" | sanitize)"
  release_tag="firmware-${profile_slug}-${source_slug_safe}-${branch_slug}-${wrt_hash}-run${run_number}"
  release_name="${profile_title} / ${source_repo}:${repo_branch} / ${wrt_hash}"

  {
    echo "| File | Size |"
    echo "|------|------|"
    find "${firmware_path}" -maxdepth 1 -type f -print | sort | while IFS= read -r file; do
      printf '| `%s` | `%s` |\n' "$(basename "${file}")" "$(du -h "${file}" | awk '{print $1}')"
    done
  } > "${artifact_table}"

  cat > "${body_file}" <<EOF
## Firmware Build

| Field | Value |
|-------|-------|
| Profile | ${profile_title} (${profile_id}) |
| Platform tag | ${firmware_tag} |
| Source | ${repo_url} |
| Branch | ${repo_branch} |
| Source commit | ${source_commit} |
| Source commit date | ${source_commit_date} |
| Source commit subject | ${source_commit_subject} |
| Profile hash | ${profile_hash} |
| Workflow run | ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-unknown}/actions/runs/${GITHUB_RUN_ID:-0} |

## Default Access

| Field | Value |
|-------|-------|
| Default IP | ${default_ip} |
| Default IP source | ${default_ip_source} |
| Default password state | ${default_password} |
| Default password source | ${default_password_source} |

## Artifacts

$(cat "${artifact_table}")
EOF

  append_env_line "${env_target}" "RELEASE_NAME=${release_name}"
  append_env_line "${env_target}" "RELEASE_TAG=${release_tag}"
  append_env_line "${env_target}" "RELEASE_BODY_FILE=${body_file}"
  append_env_line "${output_target}" "release_name=${release_name}"
  append_env_line "${output_target}" "release_tag=${release_tag}"
  append_env_line "${output_target}" "release_body_file=${body_file}"
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  prepare-release-metadata)
    prepare_release_metadata \
      "${2:-${GITHUB_WORKSPACE:-$(pwd)}}" \
      "${3:-${GITHUB_ENV:-}}" \
      "${4:-${FIRMWARE_PATH:-}}" \
      "${5:-${GITHUB_OUTPUT:-}}"
    ;;
  *)
    echo "Usage: $0 <subcommand> [args...]" >&2
    echo "Subcommands: prepare-release-metadata" >&2
    exit 1
    ;;
esac
