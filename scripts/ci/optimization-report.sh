#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  optimization-report.sh summary <root-dir>
  optimization-report.sh cache <owner/repo>
  optimization-report.sh release <owner/repo> <tag>
EOF
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "ERROR: required command not found: ${command_name}" >&2
    exit 1
  fi
}

require_arg() {
  local value="$1"
  local name="$2"

  if [ -z "${value}" ]; then
    echo "ERROR: missing ${name}" >&2
    usage
    exit 1
  fi
}

format_mib() {
  awk -v bytes="$1" 'BEGIN { printf "%.2f", bytes / 1024 / 1024 }'
}

summary_report() {
  local root_dir="${1:-}"
  local target_options
  local matrix
  local enabled_count

  require_arg "${root_dir}" "root-dir"
  if [ ! -d "${root_dir}" ]; then
    echo "ERROR: root-dir is not a directory: ${root_dir}" >&2
    exit 1
  fi

  require_command ruby
  target_options="$(bash "${root_dir}/scripts/ci/profiles.sh" target-options "" "" "${root_dir}")"
  matrix="$(bash "${root_dir}/scripts/ci/profiles.sh" matrix all "" "${root_dir}")"
  enabled_count="$(printf '%s' "${matrix}" | ruby -rjson -e 'payload = JSON.parse(STDIN.read); puts Array(payload.fetch("include")).length')"

  cat <<EOF
# Optimization Health Summary

| Field | Value |
|-------|-------|
| Enabled profiles | ${enabled_count} |
| Profile source | devices/profiles.yml |
| Matrix source | scripts/ci/profiles.sh |
| Web guard | LuCI/uHTTPd/rpcd/theme checked after defconfig |
| Performance guard | BBR/SQM/CAKE/IFB/irqbalance checked by config audit |
| Packages archive | Packages.tar.gz must be retained |
| VM images | .vmdk/.vdi/.vhd/.vhdx/.qcow2 must be pruned |

## Targets

\`\`\`text
${target_options}
\`\`\`

## Matrix

\`\`\`json
${matrix}
\`\`\`
EOF
}

cache_report() {
  local repo="${1:-}"
  local tmp_file
  local count
  local total_bytes
  local total_mib
  local threshold_mib=8192

  require_arg "${repo}" "owner/repo"
  require_command gh
  require_command jq
  require_command awk

  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file}"' RETURN

  gh api "repos/${repo}/actions/caches" --paginate \
    --jq '.actions_caches[] | [.key, .ref, .size_in_bytes, .last_accessed_at] | @tsv' > "${tmp_file}"

  count="$(awk 'END { print NR + 0 }' "${tmp_file}")"
  total_bytes="$(awk -F '\t' '{ total += $3 } END { printf "%.0f", total + 0 }' "${tmp_file}")"
  total_mib="$(format_mib "${total_bytes}")"

  cat <<EOF
# GitHub Actions Cache Health

| Field | Value |
|-------|-------|
| Repository | ${repo} |
| Cache count | ${count} |
| Total size | ${total_mib} MiB |
| Advisory threshold | ${threshold_mib} MiB |
EOF

  if awk -v current="${total_mib}" -v threshold="${threshold_mib}" 'BEGIN { exit current > threshold ? 0 : 1 }'; then
    cat <<EOF

> Cache usage is above ${threshold_mib} MiB. Run Cache Maintenance in dry-run mode before deleting anything.
EOF
  fi

  cat <<'EOF'

## Caches

| Key | Ref | Size | Last accessed |
|-----|-----|------|---------------|
EOF

  if [ "${count}" -eq 0 ]; then
    echo "| _none_ | _none_ | _none_ | _none_ |"
    return
  fi

  awk -F '\t' '{
    size = $3 / 1024 / 1024
    printf("| `%s` | `%s` | `%.2f MiB` | `%s` |\n", $1, $2, size, $4)
  }' "${tmp_file}"
}

release_report() {
  local repo="${1:-}"
  local tag="${2:-}"
  local assets
  local vm_pattern='\.v(mdk|di|hd|hdx)(\.|$)|\.qcow2(\.|$)'

  require_arg "${repo}" "owner/repo"
  require_arg "${tag}" "tag"
  require_command gh
  require_command jq
  require_command grep

  assets="$(gh release view "${tag}" --repo "${repo}" --json assets --jq '.assets[].name')"

  if ! printf '%s\n' "${assets}" | grep -Fxq "Packages.tar.gz"; then
    echo "ERROR: Release ${tag} does not contain Packages.tar.gz" >&2
    exit 1
  fi

  if printf '%s\n' "${assets}" | grep -Eiq "${vm_pattern}"; then
    echo "ERROR: Release ${tag} contains VM-specific disk image assets" >&2
    printf '%s\n' "${assets}" | grep -Ei "${vm_pattern}" >&2
    exit 1
  fi

  cat <<EOF
# Release Artifact Health

| Field | Value |
|-------|-------|
| Repository | ${repo} |
| Release tag | ${tag} |
| Packages.tar.gz | present |
| VM image formats | absent |

## Assets

\`\`\`text
${assets}
\`\`\`
EOF
}

command="${1:-}"
case "${command}" in
  summary)
    summary_report "${2:-}"
    ;;
  cache)
    cache_report "${2:-}"
    ;;
  release)
    release_report "${2:-}" "${3:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac
