#!/usr/bin/env bash
set -euo pipefail

COMMAND="${1:-}"
SELECTOR="${2:-}"
ENV_OUT="${3:-}"
ROOT_DIR="${4:-${GITHUB_WORKSPACE:-$(pwd)}}"
OUTPUT_OUT="${5:-${GITHUB_OUTPUT:-}}"
CONFIG_PATH="${PROFILES_FILE:-devices/profiles.yml}"

if [ -z "${COMMAND}" ]; then
  echo "Usage: $0 <validate|list|target-options|matrix|export-env> [selector] [env-out] [root-dir]" >&2
  exit 1
fi

ROOT_DIR="${ROOT_DIR}" CONFIG_PATH="${CONFIG_PATH}" COMMAND="${COMMAND}" SELECTOR="${SELECTOR}" ENV_OUT="${ENV_OUT}" OUTPUT_OUT="${OUTPUT_OUT}" ruby <<'RUBY'
require "yaml"
require "json"
require "pathname"
require "digest"
require "securerandom"

def fail!(message)
  warn "ERROR: #{message}"
  exit 1
end

def append_github_value(target, key, value)
  return if target.to_s.strip.empty?

  delimiter = "EOF_#{key}_#{SecureRandom.hex(8)}"
  File.open(target, "a") do |file|
    file.puts("#{key}<<#{delimiter}")
    file.puts(value.to_s)
    file.puts(delimiter)
  end
end

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
config_path = Pathname.new(ENV.fetch("CONFIG_PATH"))
config_path = root.join(config_path) unless config_path.absolute?
fail!("missing profile config: #{config_path}") unless config_path.file?

cfg = YAML.load_file(config_path.to_s) || {}
profiles = cfg.fetch("profiles", {})
defaults = cfg.fetch("defaults", {})
fail!("profiles must be a map") unless profiles.is_a?(Hash) && !profiles.empty?

def absolute_path(root, path)
  return nil if path.nil? || path.to_s.strip.empty?

  candidate = Pathname.new(path.to_s)
  candidate = root.join(candidate) unless candidate.absolute?
  candidate
end

def array_value(value, field)
  return [] if value.nil?
  fail!("#{field} must be a list") unless value.is_a?(Array)

  value
end

def merged_profile(defaults, profile)
  defaults.merge(profile) do |key, default_value, override|
    if key == "config_fragments"
      (array_value(default_value, "defaults config_fragments") + array_value(override, "profile config_fragments")).uniq
    else
      override.nil? ? default_value : override
    end
  end
end

def enabled?(profile)
  profile.fetch("enabled", true) != false
end

def profile_groups(profile, field)
  array_value(profile["groups"], field)
end

def selected_profile_ids(selector, profiles)
  return profiles.select { |_id, profile| enabled?(profile) }.keys if selector == "all"

  group_ids = profiles.select do |id, profile|
    enabled?(profile) && profile_groups(profile, "profile #{id} groups").include?(selector)
  end.keys
  return group_ids if group_ids.any?

  fail!("unknown profile or group: #{selector}") unless profiles.key?(selector)

  fail!("profile is disabled: #{selector}") unless enabled?(profiles.fetch(selector))
  [selector]
end

def validate_path!(root, value, field, required: false)
  if value.nil? || value.to_s.strip.empty?
    fail!("missing #{field}") if required
    return
  end

  path = absolute_path(root, value)
  fail!("#{field} does not exist: #{value}") unless path.file?
end

def existing_paths(root, values)
  Array(values).each_with_object([]) do |value, paths|
    next if value.nil? || value.to_s.strip.empty?

    path = absolute_path(root, value)
    paths << path if path.file?
  end
end

def config_assignment(lines, option)
  lines.reverse_each do |line|
    stripped = line.strip
    return "n" if stripped == "# #{option} is not set"

    match = stripped.match(/\A#{Regexp.escape(option)}=(.+)\z/)
    return match[1] if match
  end

  nil
end

def merged_config_lines(root, profile, id)
  paths = [profile.fetch("config")]
  paths.concat(array_value(profile["config_fragments"], "profile #{id} config_fragments"))
  paths.flat_map do |path_value|
    path = absolute_path(root, path_value)
    path.read.lines
  end
end

def validate_x86_image_options!(root, id, profile)
  lines = merged_config_lines(root, profile, id)
  return unless config_assignment(lines, "CONFIG_TARGET_x86_64") == "y"

  required = {
    "CONFIG_TARGET_KERNEL_PARTSIZE" => "128",
    "CONFIG_TARGET_ROOTFS_PARTSIZE" => "1024",
    "CONFIG_TARGET_ROOTFS_EXT4FS" => "y",
    "CONFIG_GRUB_IMAGES" => "y",
    "CONFIG_GRUB_EFI_IMAGES" => "y"
  }

  required.each do |option, expected|
    actual = config_assignment(lines, option)
    next if actual == expected

    fail!("profile #{id} requires #{option}=#{expected} for x86 image output, got #{actual || "unset"}")
  end

  %w[
    CONFIG_VMDK_IMAGES
    CONFIG_VDI_IMAGES
    CONFIG_VHDX_IMAGES
    CONFIG_QCOW2_IMAGES
  ].each do |option|
    actual = config_assignment(lines, option)
    next if actual.nil? || actual == "n"

    fail!("profile #{id} should not enable #{option}; VM-specific disk images are pruned from CI artifacts")
  end
end

def validate_luci_web_options!(root, id, profile)
  lines = merged_config_lines(root, profile, id)
  has_luci = lines.any? do |line|
    stripped = line.strip
    stripped.start_with?("CONFIG_PACKAGE_luci") && stripped.end_with?("=y")
  end
  return unless has_luci

  required = {
    "CONFIG_PACKAGE_luci" => "y"
  }

  required.each do |option, expected|
    actual = config_assignment(lines, option)
    next if actual == expected

    fail!("profile #{id} enables LuCI components but lacks #{option}=#{expected}, got #{actual || "unset"}")
  end
end

def validate_profile!(root, id, raw_profile, defaults)
  fail!("profile #{id} must be a map") unless raw_profile.is_a?(Hash)

  profile = merged_profile(defaults, raw_profile)
  %w[source_repo source_branch firmware_tag config cache_group].each do |field|
    fail!("profile #{id} missing #{field}") if profile[field].nil? || profile[field].to_s.strip.empty?
  end
  profile_groups(profile, "profile #{id} groups")

  unless profile["source_repo"].to_s.match?(%r{\Ahttps://github\.com/[^/]+/[^/]+(\.git)?\z})
    fail!("profile #{id} source_repo must be a GitHub HTTPS repository URL")
  end

  validate_path!(root, profile["config"], "profile #{id} config", required: true)
  array_value(profile["config_fragments"], "profile #{id} config_fragments").each do |fragment|
    validate_path!(root, fragment, "profile #{id} config fragment", required: true)
  end

  %w[feeds_conf pre_feeds_script post_feeds_script general_script package_base_script package_overlay_script].each do |field|
    validate_path!(root, profile[field], "profile #{id} #{field}")
  end
  if profile.key?("make_compile_jobs") && !profile["make_compile_jobs"].to_s.match?(/\A[1-9][0-9]*\z/)
    fail!("profile #{id} make_compile_jobs must be a positive integer")
  end

  validate_x86_image_options!(root, id, profile)
  validate_luci_web_options!(root, id, profile)
end

profiles.each do |id, profile|
  validate_profile!(root, id, profile, defaults)
end

command = ENV.fetch("COMMAND")
selector = ENV.fetch("SELECTOR")

case command
when "validate"
  puts "Validated #{profiles.length} firmware profiles from #{config_path.relative_path_from(root)}"
when "list"
  puts profiles.keys.join("\n")
when "target-options"
  enabled_profile_ids = profiles.select { |_id, profile| enabled?(profile) }.keys
  enabled_profiles = profiles.select { |_id, profile| enabled?(profile) }.values
  group_options = enabled_profiles.flat_map { |profile| profile_groups(profile, "enabled profile groups") }.uniq
  puts((enabled_profile_ids + group_options + ["all"]).join("\n"))
when "matrix"
  fail!("selector is required for matrix") if selector.to_s.strip.empty?
  ids = selected_profile_ids(selector, profiles)

  fail!("no enabled profiles selected") if ids.empty?

  matrix = {
    include: ids.map do |id|
      profile = merged_profile(defaults, profiles.fetch(id))
      {
        profile: id,
        title: profile.fetch("title", id),
        cache_group: profile.fetch("cache_group")
      }
    end
  }
  puts JSON.generate(matrix)
when "export-env"
  fail!("profile id is required for export-env") if selector.to_s.strip.empty?
  fail!("unknown profile: #{selector}") unless profiles.key?(selector)

  env_out = ENV.fetch("ENV_OUT")
  fail!("env output target is required for export-env") if env_out.to_s.strip.empty?
  output_out = ENV.fetch("OUTPUT_OUT")

  profile = merged_profile(defaults, profiles.fetch(selector))
  config_fragments = array_value(profile["config_fragments"], "profile #{selector} config_fragments")
  source_repo = profile.fetch("source_repo").to_s
  source_repo_name = source_repo.sub(%r{\.git\z}, "").split("/").last
  source_slug = source_repo.sub(%r{\Ahttps://github\.com/}, "").sub(%r{\.git\z}, "").tr("/", "_")
  hash_inputs = [
    absolute_path(root, profile.fetch("config")),
    *existing_paths(root, config_fragments),
    *existing_paths(root, [
      profile["pre_feeds_script"],
      profile["post_feeds_script"],
      profile["general_script"],
      profile["package_base_script"],
      profile["package_overlay_script"],
      profile["feeds_conf"]
    ]),
    *Dir[root.join("files/**/*").to_s].select { |path| File.file?(path) }.map { |path| Pathname.new(path) },
    config_path
  ].uniq
  profile_hash = Digest::SHA256.hexdigest(hash_inputs.map { |path| Digest::SHA256.file(path.to_s).hexdigest }.join(":"))[0, 16]

  values = {
    "PROFILE_ID" => selector,
    "PROFILE_TITLE" => profile.fetch("title", selector),
    "REPO_URL" => source_repo,
    "REPO_BRANCH" => profile.fetch("source_branch"),
    "SOURCE_REPO" => source_repo_name,
    "SOURCE_SLUG" => source_slug,
    "FIRMWARE_TAG" => profile.fetch("firmware_tag"),
    "CCACHE_GROUP" => profile.fetch("cache_group"),
    "CONFIG_FILE" => profile.fetch("config"),
    "CONFIG_FRAGMENTS" => config_fragments.join(":"),
    "FEEDS_CONF" => profile["feeds_conf"].to_s,
    "PRE_FEEDS_SCRIPT" => profile["pre_feeds_script"].to_s,
    "POST_FEEDS_SCRIPT" => profile["post_feeds_script"].to_s,
    "GENERAL_SCRIPT" => profile["general_script"].to_s,
    "PACKAGE_BASE_SCRIPT" => profile["package_base_script"].to_s,
    "PACKAGE_OVERLAY_SCRIPT" => profile["package_overlay_script"].to_s,
    "MAKE_DOWNLOAD_JOBS" => profile.fetch("make_download_jobs", 8).to_s,
    "MAKE_COMPILE_JOBS" => profile["make_compile_jobs"].to_s,
    "PROFILE_HASH" => profile_hash,
    "TZ" => profile.fetch("timezone", "Asia/Shanghai")
  }

  values.each do |key, value|
    append_github_value(env_out, key, value)
  end

  values.each do |key, value|
    append_github_value(output_out, key.downcase, value)
  end

  puts "Loaded profile #{selector}: #{values["PROFILE_TITLE"]}"
else
  fail!("unknown command: #{command}")
end
RUBY
