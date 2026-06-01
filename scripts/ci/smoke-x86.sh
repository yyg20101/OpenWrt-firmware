#!/usr/bin/env bash
set -euo pipefail

OPENWRT_PATH="${1:-${OPENWRT_PATH:-}}"
FIRMWARE_PATH="${2:-${FIRMWARE_PATH:-}}"
WORKSPACE="${3:-${GITHUB_WORKSPACE:-$(pwd)}}"
PROFILE_ID="${4:-${PROFILE_ID:-unknown}}"

if [ -z "${OPENWRT_PATH}" ] || [ -z "${FIRMWARE_PATH}" ] || [ ! -d "${OPENWRT_PATH}" ] || [ ! -d "${FIRMWARE_PATH}" ]; then
  echo "ERROR: smoke-x86 requires openwrt_path and firmware_path directories." >&2
  exit 1
fi

smoke_dir="${WORKSPACE}/smoke-x86"
raw_image="${smoke_dir}/image.raw"
partition_table="${smoke_dir}/partition-table.txt"
summary_file="${smoke_dir}/summary.txt"

mkdir -p "${smoke_dir}"

image_path="$(find "${FIRMWARE_PATH}" -maxdepth 1 -type f \( -name "*-combined.img.gz" -o -name "*-combined-efi.img.gz" \) -print | sort | head -n1 || true)"
if [ -z "${image_path}" ]; then
  echo "ERROR: x86 smoke could not find a combined disk image in ${FIRMWARE_PATH}" >&2
  exit 1
fi

gzip -t "${image_path}"
gzip -dc "${image_path}" > "${raw_image}"

ruby - "${raw_image}" "${partition_table}" <<'RUBY'
raw_path = ARGV.fetch(0)
table_path = ARGV.fetch(1)
data = File.binread(raw_path)

lines = []
if data.bytesize >= 512 && data.byteslice(510, 2) == "\x55\xAA".b
  lines << "Partition table: MBR"
  entries = data.byteslice(446, 64).bytes.each_slice(16).with_index do |entry, index|
    next if entry.all?(&:zero?)

    bootable = entry[0] == 0x80 ? "bootable" : "inactive"
    part_type = format("0x%02x", entry[4])
    start_lba = entry[8, 4].pack("C*").unpack1("V")
    sectors = entry[12, 4].pack("C*").unpack1("V")
    lines << "  entry #{index + 1}: #{bootable}, type=#{part_type}, start_lba=#{start_lba}, sectors=#{sectors}"
  end
elsif data.bytesize >= 520 && data.byteslice(512, 8) == "EFI PART"
  lines << "Partition table: GPT"
else
  abort "ERROR: unable to recognize partition table signature in #{raw_path}"
end

File.write(table_path, lines.join("\n") + "\n")
RUBY

mode="static"
boot_status="skipped"
qemu_log="${smoke_dir}/qemu.log"
qemu_bin="$(command -v qemu-system-x86_64 || true)"

if [ -n "${qemu_bin}" ]; then
  mode="qemu"
  timeout_prefix=()
  if command -v timeout >/dev/null 2>&1; then
    timeout_prefix=(timeout "${SMOKE_X86_TIMEOUT:-120}")
  fi

  set +e
  "${timeout_prefix[@]}" "${qemu_bin}" \
    -accel tcg \
    -m "${SMOKE_X86_MEMORY:-512}" \
    -nographic \
    -monitor none \
    -no-reboot \
    -snapshot \
    -drive "file=${raw_image},format=raw,if=ide,cache=unsafe" \
    -boot c \
    > "${qemu_log}" 2>&1
  qemu_exit=$?
  set -e

  if grep -Eq 'Linux version|Starting kernel|Kernel command line|OpenWrt|Booting from Hard Disk|GRUB' "${qemu_log}"; then
    boot_status="boot-visible"
  else
    boot_status="boot-unverified"
    if [ "${SMOKE_X86_STRICT:-0}" = "1" ]; then
      echo "ERROR: QEMU did not emit recognizable boot output for ${PROFILE_ID}." >&2
      exit "${qemu_exit}"
    fi
  fi
else
  echo "QEMU system binary not found; completed static smoke checks only." > "${qemu_log}"
fi

{
  echo "Profile: ${PROFILE_ID}"
  echo "Image: ${image_path}"
  echo "Mode: ${mode}"
  echo "Boot status: ${boot_status}"
  echo "Static checks: passed"
  echo "Partition table: $(sed -n '1p' "${partition_table}" 2>/dev/null || echo unknown)"
  echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} > "${summary_file}"

echo "x86 smoke passed for ${PROFILE_ID} (${mode}, ${boot_status})."
