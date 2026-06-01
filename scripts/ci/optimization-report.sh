#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  optimization-report.sh summary <root-dir>
  optimization-report.sh profile-drift <root-dir> [owner/repo]
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

profile_inventory_report() {
  local root_dir="$1"

  ROOT_DIR="${root_dir}" ruby <<'RUBY'
require "yaml"
require "pathname"
require "digest"

def array_value(value)
  value.is_a?(Array) ? value : []
end

def merged_profile(defaults, profile)
  defaults.merge(profile) do |key, default_value, override|
    if key == "config_fragments"
      (array_value(default_value) + array_value(override)).uniq
    else
      override.nil? ? default_value : override
    end
  end
end

def absolute_path(root, value)
  path = Pathname.new(value.to_s)
  path.absolute? ? path : root.join(path)
end

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
config_path = root.join("devices/profiles.yml")
cfg = YAML.load_file(config_path.to_s) || {}
profiles = cfg.fetch("profiles", {})
defaults = cfg.fetch("defaults", {})

puts "## Profile Sources"
puts
puts "| Profile | Enabled | Source repo | Branch | Cache group | Compile jobs | Profile hash |"
puts "|---------|---------|-------------|--------|-------------|--------------|--------------|"

profiles.each do |id, raw_profile|
  profile = merged_profile(defaults, raw_profile || {})
  source_repo = profile.fetch("source_repo", "")
  config_fragments = array_value(profile["config_fragments"])
  hash_inputs = [
    absolute_path(root, profile.fetch("config")),
    *config_fragments.map { |fragment| absolute_path(root, fragment) },
    *%w[
      feeds_conf
      pre_feeds_script
      post_feeds_script
      general_script
      package_base_script
      package_overlay_script
    ].map { |field| value = profile[field]; value.to_s.strip.empty? ? nil : absolute_path(root, value) }.compact,
    *Dir[root.join("files/**/*").to_s].select { |path| File.file?(path) }.map { |path| Pathname.new(path) },
    config_path
  ].uniq.select(&:file?)
  profile_hash = Digest::SHA256.hexdigest(hash_inputs.map { |path| Digest::SHA256.file(path.to_s).hexdigest }.join(":"))[0, 16]
  source_slug = source_repo.sub(%r{\Ahttps://github\.com/}, "").sub(%r{\.git\z}, "")
  compile_jobs = profile["make_compile_jobs"].to_s.strip.empty? ? "auto" : profile["make_compile_jobs"]

  puts "| `#{id}` | `#{profile.fetch("enabled", true) != false}` | `#{source_slug}` | `#{profile.fetch("source_branch", "")}` | `#{profile.fetch("cache_group", "")}` | `#{compile_jobs}` | `#{profile_hash}` |"
end
RUBY
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

  echo
  profile_inventory_report "${root_dir}"
}

profile_drift_report() {
  local root_dir="${1:-}"
  local repo="${2:-${PROFILE_DRIFT_REPOSITORY:-${GITHUB_REPOSITORY:-}}}"

  require_arg "${root_dir}" "root-dir"
  if [ ! -d "${root_dir}" ]; then
    echo "ERROR: root-dir is not a directory: ${root_dir}" >&2
    exit 1
  fi

  require_command ruby
  require_command git

  ROOT_DIR="${root_dir}" PROFILE_DRIFT_REPOSITORY="${repo}" ruby <<'RUBY'
require "yaml"
require "pathname"
require "open3"
require "json"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
repository = ENV.fetch("PROFILE_DRIFT_REPOSITORY", "").strip
cfg = YAML.load_file(root.join("devices/profiles.yml").to_s) || {}
profiles = cfg.fetch("profiles", {})
defaults = cfg.fetch("defaults", {})

def array_value(value)
  value.is_a?(Array) ? value : []
end

def merged_profile(defaults, profile)
  defaults.merge(profile || {}) do |key, default_value, override|
    if key == "config_fragments"
      (array_value(default_value) + array_value(override)).uniq
    else
      override.nil? ? default_value : override
    end
  end
end

def run_git_ls_remote(repo, branch)
  stdout, stderr, status = Open3.capture3("git", "ls-remote", "--heads", repo, branch)
  return ["unavailable", stderr.lines.first.to_s.strip] unless status.success?

  line = stdout.lines.first.to_s
  commit = line.split(/\s+/).first.to_s
  commit.empty? ? ["missing", "branch not found"] : [commit, ""]
end

def command_available?(command)
  ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |directory|
    path = File.join(directory, command)
    File.file?(path) && File.executable?(path)
  end
end

def sanitize_slug(value)
  value.to_s.gsub(/[^A-Za-z0-9._-]+/, "-").sub(/\A-+/, "").sub(/-+\z/, "")
end

def load_release_commit_index(repository)
  return [[], "release lookup disabled"] if repository.empty?
  return [[], "gh unavailable"] unless command_available?("gh")

  stdout, stderr, status = Open3.capture3(
    "gh",
    "api",
    "repos/#{repository}/releases?per_page=100",
    "--paginate",
    "--jq",
    '.[] | [.tag_name, .published_at, .body] | @json'
  )
  return [[], "release lookup failed: #{stderr.lines.first.to_s.strip}"] unless status.success?

  releases = stdout.lines.map do |line|
    next if line.strip.empty?

    tag_name, published_at, body = JSON.parse(line)
    { tag_name: tag_name.to_s, published_at: published_at.to_s, body: body.to_s }
  rescue JSON::ParserError
    nil
  end.compact

  [releases, ""]
end

def release_commit_for_profile(id, releases)
  prefix = "firmware-#{sanitize_slug(id)}-"
  release = releases.find { |entry| entry[:tag_name].start_with?(prefix) }
  return ["unknown", "no matching release"] unless release

  match = release[:body].match(/^\|\s*Source commit\s*\|\s*([^|]+?)\s*\|/i)
  return ["unknown", "release:#{release[:tag_name]} missing source commit"] unless match

  [match[1].strip, "release:#{release[:tag_name]}"]
end

releases, release_lookup_note = load_release_commit_index(repository)

puts "# Profile Upstream Drift"
puts
puts "| Profile | Source repo | Branch | Remote HEAD | Last build commit | Drift | Note |"
puts "|---------|-------------|--------|-------------|-------------------|-------|------|"

profiles.each do |id, raw_profile|
  profile = merged_profile(defaults, raw_profile)
  next if profile.fetch("enabled", true) == false

  repo = profile.fetch("source_repo")
  branch = profile.fetch("source_branch")
  remote_head, note = run_git_ls_remote(repo, branch)
  source_slug = repo.sub(%r{\Ahttps://github\.com/}, "").sub(%r{\.git\z}, "")
  env_name = "LAST_SOURCE_COMMIT_#{id.to_s.gsub(/[^A-Za-z0-9_]/, "_")}"
  last_build_commit = ENV[env_name].to_s.strip
  build_note = ""
  if last_build_commit.empty?
    last_build_commit, build_note = release_commit_for_profile(id, releases)
    build_note = release_lookup_note unless release_lookup_note.empty? || last_build_commit != "unknown"
  else
    build_note = "env:#{env_name}"
  end
  last_build_commit = "unknown" if last_build_commit.empty?
  drift =
    if remote_head == "unavailable" || remote_head == "missing" || last_build_commit == "unknown"
      "unknown"
    elsif remote_head.start_with?(last_build_commit) || last_build_commit.start_with?(remote_head)
      "no"
    else
      "yes"
    end

  short_remote = remote_head.match?(/\A[0-9a-f]{40}\z/) ? remote_head[0, 12] : remote_head
  short_last = last_build_commit.match?(/\A[0-9a-f]{7,40}\z/) ? last_build_commit[0, 12] : last_build_commit
  notes = [note, build_note].reject(&:empty?).map { |value| value.gsub("|", "\\|") }
  puts "| `#{id}` | `#{source_slug}` | `#{branch}` | `#{short_remote}` | `#{short_last}` | `#{drift}` | #{notes.empty? ? "" : "`#{notes.join("; ")}`"} |"
end
RUBY
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

  cat <<'EOF'

## Cache Prefix Groups

| Prefix group | Count | Total size | Last accessed |
|--------------|-------|------------|---------------|
EOF

  awk -F '\t' '
    function group_key(key, parts) {
      split(key, parts, "-")
      if (parts[1] == "") {
        return "(unknown)"
      }
      if (parts[1] == "ccache" && parts[2] == "v2" && parts[3] != "" && parts[4] != "" && parts[5] != "") {
        return parts[1] "-" parts[2] "-" parts[3] "-" parts[4] "-" parts[5]
      }
      if (parts[1] == "build" && parts[2] == "accel" && parts[3] == "v2" && parts[4] != "" && parts[5] != "" && parts[6] != "") {
        return parts[1] "-" parts[2] "-" parts[3] "-" parts[4] "-" parts[5] "-" parts[6]
      }
      return parts[1]
    }
    {
      group = group_key($1)
      count[group] += 1
      total[group] += $3
      if (last[group] == "" || $4 > last[group]) {
        last[group] = $4
      }
    }
    END {
      for (group in count) {
        printf("%s\t%d\t%.2f\t%s\n", group, count[group], total[group] / 1024 / 1024, last[group])
      }
    }' "${tmp_file}" | sort | awk -F '\t' '{
      printf("| `%s` | `%s` | `%.2f MiB` | `%s` |\n", $1, $2, $3, $4)
    }'
}

release_report() {
  local repo="${1:-}"
  local tag="${2:-}"
  local assets
  local vm_pattern='\.v(mdk|di|hd|hdx)(\.|$)|\.qcow2(\.|$)'

  require_arg "${repo}" "owner/repo"
  require_arg "${tag}" "tag"
  require_command gh
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
  profile-drift)
    profile_drift_report "${2:-}" "${3:-}"
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
