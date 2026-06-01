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
  local package_table="${workspace}/release-packages.md"
  local package_count_file="${workspace}/release-package-count.txt"
  local package_source_table="${workspace}/release-package-sources.md"
  local size_report_section="${workspace}/release-size-report.md"
  local build_environment_section="${workspace}/release-build-environment.md"
  local package_count="0"

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

  generate_package_table "${firmware_path}" "${package_table}" "${package_count_file}"
  package_count="$(cat "${package_count_file}")"
  generate_package_source_table "${firmware_path}" "${package_source_table}"
  generate_size_report_section "${firmware_path}" "${size_report_section}"
  generate_build_environment_section "${firmware_path}" "${build_environment_section}"

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

## Size Report

$(cat "${size_report_section}")

## Packages

Packages.tar.gz contains ${package_count} package file(s).

<details>
<summary>Package list</summary>

$(cat "${package_table}")

</details>

## Package Sources

$(cat "${package_source_table}")

## Build Environment

$(cat "${build_environment_section}")
EOF

  append_github_value "${env_target}" "RELEASE_NAME" "${release_name}"
  append_github_value "${env_target}" "RELEASE_TAG" "${release_tag}"
  append_github_value "${env_target}" "RELEASE_BODY_FILE" "${body_file}"
  append_github_value "${output_target}" "release_name" "${release_name}"
  append_github_value "${output_target}" "release_tag" "${release_tag}"
  append_github_value "${output_target}" "release_body_file" "${body_file}"
}

generate_size_report_section() {
  local firmware_path="$1"
  local section_file="$2"
  local report="${firmware_path}/firmware-size-report.md"

  if [ ! -f "${report}" ]; then
    echo "_No firmware size report found._" > "${section_file}"
    return
  fi

  sed -n '3,$p' "${report}" > "${section_file}"
}

generate_build_environment_section() {
  local firmware_path="$1"
  local section_file="$2"
  local report="${firmware_path}/build-environment-provenance.md"

  if [ ! -f "${report}" ]; then
    echo "_No build environment provenance found._" > "${section_file}"
    return
  fi

  cat "${report}" > "${section_file}"
}

generate_package_source_table() {
  local firmware_path="$1"
  local table_file="$2"
  local manifest="${firmware_path}/package-source-manifest.tsv"

  if [ ! -f "${manifest}" ]; then
    echo "_No package source manifest found._" > "${table_file}"
    return
  fi

  {
    echo "| Package | Repository | Ref | Commit | Mode |"
    echo "|---------|------------|-----|--------|------|"
    awk -F '\t' '
    function md_cell(value) {
      gsub(/\\/, "\\\\", value)
      gsub(/\|/, "\\|", value)
      return value
    }
    NR > 1 {
      commit = $4
      if (length(commit) > 12) {
        commit = substr(commit, 1, 12)
      }
      printf("| `%s` | `%s` | `%s` | `%s` | `%s` |\n", md_cell($1), md_cell($2), md_cell($3), md_cell(commit), md_cell($5))
    }' "${manifest}"
  } > "${table_file}"
}

generate_package_table() {
  local firmware_path="$1"
  local table_file="$2"
  local count_file="$3"
  local package_archive="${firmware_path}/Packages.tar.gz"
  local package_tmp
  local package_count

  echo "0" > "${count_file}"
  if [ ! -f "${package_archive}" ]; then
    echo "_No package archive found._" > "${table_file}"
    return
  fi

  package_tmp="$(mktemp -d)"
  if ! tar -xzf "${package_archive}" -C "${package_tmp}"; then
    rm -rf "${package_tmp}"
    echo "_Unable to read Packages.tar.gz._" > "${table_file}"
    return
  fi

  package_count="$(find "${package_tmp}" -type f \( -name "*.ipk" -o -name "*.apk" \) -print | wc -l | awk '{print $1}')"
  echo "${package_count}" > "${count_file}"

  if [ "${package_count}" -eq 0 ]; then
    echo "_No package files found in Packages.tar.gz._" > "${table_file}"
  else
    {
      echo "| Package | Size |"
      echo "|---------|------|"
      find "${package_tmp}" -type f \( -name "*.ipk" -o -name "*.apk" \) -print | sort | while IFS= read -r file; do
        printf '| `%s` | `%s` |\n' "$(basename "${file}")" "$(du -h "${file}" | awk '{print $1}')"
      done
    } > "${table_file}"
  fi

  rm -rf "${package_tmp}"
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
