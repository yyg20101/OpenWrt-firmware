#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"

ROOT_DIR="${ROOT_DIR}" ruby <<'RUBY'
require "pathname"
require "open3"

root = Pathname.new(ENV.fetch("ROOT_DIR")).expand_path
profiles_script = root.join("scripts/ci/profiles.sh")
workflow_path = root.join(".github/workflows/firmware-ci.yml")

unless profiles_script.file?
  warn "ERROR: missing profiles script: #{profiles_script}"
  exit 1
end

unless workflow_path.file?
  warn "ERROR: missing workflow: #{workflow_path}"
  exit 1
end

stdout, stderr, status = Open3.capture3(
  "bash",
  profiles_script.to_s,
  "target-options",
  "",
  "",
  root.to_s
)
unless status.success?
  warn stderr
  warn "ERROR: failed to generate firmware-ci target options"
  exit status.exitstatus || 1
end

options = stdout.lines.map(&:strip).reject(&:empty?)

if options.empty?
  warn "ERROR: no target options were generated"
  exit 1
end

lines = workflow_path.read.lines
target_start = nil
target_indent = nil
options_start = nil
options_indent = nil
options_end = nil

lines.each_with_index do |line, index|
  if target_start.nil? && line.match?(/\A\s{6}target:\s*\z/)
    target_start = index
    target_indent = line[/\A */].length
    next
  end

  next if target_start.nil?

  indent = line[/\A */].length
  if options_start.nil?
    if indent == target_indent + 2 && line.match?(/\A\s+options:\s*\z/)
      options_start = index
      options_indent = indent
      next
    end

    if indent <= target_indent && !line.strip.empty?
      break
    end
  else
    if line.strip.empty?
      options_end = index
      break
    end

    if indent <= options_indent && !line.match?(/\A\s*-\s+/)
      options_end = index
      break
    end
  end
end

if options_start.nil?
  warn "ERROR: unable to locate workflow_dispatch target options in #{workflow_path}"
  exit 1
end

options_end ||= lines.length
replacement = ["#{" " * options_indent}options:\n"]
replacement.concat(options.map { |option| "#{" " * (options_indent + 2)}- #{option}\n" })
updated = lines[0...options_start] + replacement + lines[options_end..]

workflow_path.write(updated.join)
puts "Synced #{options.length} firmware-ci target option(s) in #{workflow_path.relative_path_from(root)}"
RUBY
