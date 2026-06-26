#!/usr/bin/env bash
set -euo pipefail

append_line() {
  local target="$1"
  local line="$2"
  if [ -n "${target}" ]; then
    echo "${line}" >> "${target}"
  fi
}

COMPILE_HEARTBEAT_PID=""

start_compile_heartbeat() {
  local compile_log="$1"
  local openwrt_path="$2"
  local interval="${COMPILE_HEARTBEAT_SECONDS:-300}"

  [[ "${interval}" =~ ^[0-9]+$ ]] || interval=300
  [ "${interval}" -ge 60 ] || interval=60

  (
    while true; do
      sleep "${interval}" || exit 0
      {
        echo "[compile heartbeat] $(date -u +"%Y-%m-%dT%H:%M:%SZ") build still running"
        free -h 2>/dev/null || true
        df -hT "${openwrt_path}" 2>/dev/null || true
      } | tee -a "${compile_log}"
    done
  ) &
  COMPILE_HEARTBEAT_PID="$!"
}

stop_compile_heartbeat() {
  local heartbeat_pid="${1:-}"

  if [ -n "${heartbeat_pid}" ]; then
    kill "${heartbeat_pid}" 2>/dev/null || true
    wait "${heartbeat_pid}" 2>/dev/null || true
  fi
}

download_dependencies() {
  local openwrt_path="$1"
  local jobs="${2:-${MAKE_DOWNLOAD_JOBS:-8}}"
  local retry_jobs=4

  cd "${openwrt_path}"
  make defconfig
  if ! make download -j"${jobs}"; then
    echo "WARNING: make download -j${jobs} failed; retrying with lower parallelism." >&2
  fi

  if find dl -size -1024c -print -quit | grep -q .; then
    echo "WARNING: removing incomplete downloads before retry." >&2
    find dl -size -1024c -exec ls -l {} \;
    find dl -size -1024c -exec rm -f {} \;
  fi

  if ! make download -j"${retry_jobs}"; then
    echo "WARNING: make download -j${retry_jobs} failed; retrying serial download." >&2
    make download -j1
  fi

  if find dl -size -1024c -print -quit | grep -q .; then
    echo "ERROR: incomplete downloads remain after retries:" >&2
    find dl -size -1024c -exec ls -l {} \; >&2
    exit 1
  fi
}

compile_firmware() {
  local openwrt_path="$1"
  local workspace="$2"
  local output_target="${3:-${GITHUB_OUTPUT:-}}"
  local env_target="${4:-${GITHUB_ENV:-}}"
  local compile_log="${workspace}/compile.log"
  local failure_dir="${workspace}/failure-context"
  local build_exit=0
  local jobs=1
  local max_jobs="${MAKE_COMPILE_JOBS:-}"
  local heartbeat_pid=""

  jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=1
  [ "${jobs}" -ge 1 ] || jobs=1
  if [[ "${max_jobs}" =~ ^[0-9]+$ ]] && [ "${max_jobs}" -ge 1 ] && [ "${max_jobs}" -lt "${jobs}" ]; then
    jobs="${max_jobs}"
  fi

  cd "${openwrt_path}"
  ccache --max-size="${CCACHE_MAXSIZE:-2G}" || true
  ccache -s || true
  : > "${compile_log}"
  echo "Compile jobs: ${jobs} (runner cores: $(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown), limit: ${max_jobs:-auto})" | tee -a "${compile_log}"
  start_compile_heartbeat "${compile_log}" "${openwrt_path}"
  heartbeat_pid="${COMPILE_HEARTBEAT_PID}"

  set +e
  make -j"${jobs}" 2>&1 | tee -a "${compile_log}"
  build_exit=${PIPESTATUS[0]}
  if [ "${build_exit}" -ne 0 ]; then
    make -j1 2>&1 | tee -a "${compile_log}"
    build_exit=${PIPESTATUS[0]}
  fi
  if [ "${build_exit}" -ne 0 ]; then
    make -j1 V=s 2>&1 | tee -a "${compile_log}"
    build_exit=${PIPESTATUS[0]}
  fi
  set -e
  stop_compile_heartbeat "${heartbeat_pid}"
  heartbeat_pid=""

  ccache -s || true
  if [ "${build_exit}" -eq 0 ]; then
    append_line "${output_target}" "status=success"
    append_line "${env_target}" "DATE=$(date +"%Y-%m-%d %H:%M:%S")"
    append_line "${env_target}" "FILE_DATE=$(date +"%Y.%m.%d")"
    return 0
  fi

  mkdir -p "${failure_dir}"
  cp "${compile_log}" "${failure_dir}/compile.log" 2>/dev/null || true
  tail -n 300 "${compile_log}" > "${failure_dir}/compile-tail.log" 2>/dev/null || true
  grep -E '^(CONFIG_TARGET_|# CONFIG_TARGET_)' "${openwrt_path}/.config" > "${failure_dir}/target-config.txt" 2>/dev/null || true
  grep -E '^(CONFIG_PACKAGE_|# CONFIG_PACKAGE_)' "${openwrt_path}/.config" > "${failure_dir}/package-config.txt" 2>/dev/null || true
  {
    echo "Compile jobs: ${jobs}"
    echo "Runner cores: $(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo unknown)"
    echo "Requested max jobs: ${max_jobs:-auto}"
    echo "OpenWrt path: ${openwrt_path}"
    echo "Workspace: ${workspace}"
    echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    echo "== Disk =="
    df -hT "${workspace}" 2>/dev/null || true
    echo
    echo "== Memory =="
    free -h 2>/dev/null || true
    echo
    echo "== ccache =="
    ccache -s 2>/dev/null || true
    echo
    echo "== OpenWrt tree sizes =="
    du -sh "${openwrt_path}/build_dir" "${openwrt_path}/staging_dir" "${openwrt_path}/dl" "${openwrt_path}/.ccache" 2>/dev/null || true
  } > "${failure_dir}/summary.txt"

  if [ -f "${openwrt_path}/.config" ]; then
    cp "${openwrt_path}/.config" "${failure_dir}/build.config" 2>/dev/null || true
  fi

  append_line "${output_target}" "status=failure"
  return "${build_exit}"
}

dump_failure_context() {
  local openwrt_path="$1"
  local workspace="$2"
  local compile_log="${workspace}/compile.log"
  local failure_dir="${workspace}/failure-context"
  local failed_pkg=""
  local rebuild_target=""

  mkdir -p "${failure_dir}"

  echo "::group::Compile Log Tail (last 300 lines)"
  tail -n 300 "${compile_log}" || true
  echo "::endgroup::"

  cp "${compile_log}" "${failure_dir}/compile.log" 2>/dev/null || true
  tail -n 300 "${compile_log}" > "${failure_dir}/compile-tail.log" 2>/dev/null || true
  if [ -f "${openwrt_path}/.config" ]; then
    cp "${openwrt_path}/.config" "${failure_dir}/build.config" 2>/dev/null || true
    grep -E '^(CONFIG_TARGET_|# CONFIG_TARGET_)' "${openwrt_path}/.config" > "${failure_dir}/target-config.txt" 2>/dev/null || true
    grep -E '^(CONFIG_PACKAGE_|# CONFIG_PACKAGE_)' "${openwrt_path}/.config" > "${failure_dir}/package-config.txt" 2>/dev/null || true
  fi

  failed_pkg="$(grep -oE 'package/[^ ]+ failed to build' "${compile_log}" | tail -1 | awk '{print $1}' || true)"
  if [ -z "${failed_pkg}" ]; then
    echo "No failed package detected in compile.log, skip package rebuild."
    {
      echo "Failed package: not detected"
      echo "OpenWrt path: ${openwrt_path}"
      echo "Workspace: ${workspace}"
      echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "${failure_dir}/failed-package.txt"
    return 0
  fi
  case "${failed_pkg}" in
    */compile) rebuild_target="${failed_pkg}" ;;
    *) rebuild_target="${failed_pkg}/compile" ;;
  esac

  echo "::group::Verbose Rebuild (${rebuild_target}, -j1 V=s)"
  cd "${openwrt_path}"
  make "${rebuild_target}" -j1 V=s 2>&1 | tee "${failure_dir}/verbose-rebuild.log" || true
  echo "::endgroup::"

  {
    echo "Failed package: ${failed_pkg}"
    echo "Rebuild target: ${rebuild_target}"
    echo "OpenWrt path: ${openwrt_path}"
    echo "Workspace: ${workspace}"
    echo "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "${failure_dir}/failed-package.txt"
}

optimize_build_directories() {
  local openwrt_path="$1"
  du -sh "${openwrt_path}/.ccache" 2>/dev/null || true
  du -sh "${openwrt_path}/dl" 2>/dev/null || true
}

validate_firmware_artifacts() {
  local target_dir="$1"
  local config_file="$2"

  require_artifact_pattern() {
    local pattern="$1"
    local description="$2"
    local artifact

    artifact="$(find "${target_dir}" -maxdepth 1 -type f -name "${pattern}" -print -quit)"
    if [ -n "${artifact}" ]; then
      return 0
    fi

    echo "ERROR: x86_64 build did not produce ${description}." >&2
    echo "Expected files matching: ${pattern}" >&2
    echo "Available files:" >&2
    find "${target_dir}" -maxdepth 1 -type f -print | while IFS= read -r file; do
      printf '  %s\n' "$(basename "${file}")"
    done | sort >&2
    exit 1
  }

  if grep -q '^CONFIG_TARGET_x86_64=y$' "${config_file}"; then
    require_artifact_pattern "*-combined.img.gz" "combined disk images"
    if grep -q '^CONFIG_GRUB_EFI_IMAGES=y$' "${config_file}"; then
      require_artifact_pattern "*-combined-efi.img.gz" "EFI combined disk images"
    fi
  fi
}

prune_virtual_machine_images() {
  local target_dir="$1"

  find "${target_dir}" -maxdepth 1 -type f \
    \( -name "*.vmdk" -o -name "*.vdi" -o -name "*.vhd" -o -name "*.vhdx" -o -name "*.qcow2" \) \
    -print | sort | while IFS= read -r file; do
      echo "Prune VM image artifact: $(basename "${file}")"
      rm -f "${file}"
    done

  return 0
}

extract_config_number() {
  local config_file="$1"
  local key="$2"

  awk -F= -v key="${key}" '$1 == key { gsub(/"/, "", $2); print $2; exit }' "${config_file}" 2>/dev/null || true
}

write_size_report() {
  local openwrt_path="$1"
  local firmware_path="$2"
  local config_file="${openwrt_path}/.config"
  local report="${firmware_path}/firmware-size-report.md"
  local rootfs_partsize
  local kernel_partsize
  local packages_size="0"
  local packages_count="0"

  rootfs_partsize="$(extract_config_number "${config_file}" "CONFIG_TARGET_ROOTFS_PARTSIZE")"
  kernel_partsize="$(extract_config_number "${config_file}" "CONFIG_TARGET_KERNEL_PARTSIZE")"

  if [ -d "${firmware_path}/packages" ]; then
    packages_size="$(du -sk "${firmware_path}/packages" 2>/dev/null | awk '{print $1}' || echo 0)"
    packages_count="$(find "${firmware_path}/packages" -type f \( -name "*.ipk" -o -name "*.apk" \) -print | wc -l | awk '{print $1}')"
  fi

  {
    echo "# Firmware Size Report"
    echo
    echo "| Field | Value |"
    echo "|-------|-------|"
    echo "| Target directory | \`${firmware_path}\` |"
    echo "| Rootfs partsize | \`${rootfs_partsize:-unknown} MiB\` |"
    echo "| Kernel partsize | \`${kernel_partsize:-unknown} MiB\` |"
    echo "| Package archive input size | \`${packages_size} KiB\` |"
    echo "| Package archive file count | \`${packages_count}\` |"
    echo
    echo "## Files"
    echo
    echo "| File | Size | Rootfs partition share |"
    echo "|------|------|------------------------|"
    find "${firmware_path}" -maxdepth 1 -type f ! -name "firmware-size-report.md" -print | sort | while IFS= read -r file; do
      local name
      local size_bytes
      local size_human
      local share="n/a"
      name="$(basename "${file}")"
      size_bytes="$(wc -c < "${file}" | awk '{print $1}')"
      size_human="$(du -h "${file}" | awk '{print $1}')"
      if [[ "${rootfs_partsize:-}" =~ ^[0-9]+$ ]] && [ "${rootfs_partsize}" -gt 0 ]; then
        share="$(awk -v bytes="${size_bytes}" -v mib="${rootfs_partsize}" 'BEGIN { printf "%.2f%%", bytes / (mib * 1024 * 1024) * 100 }')"
      fi
      printf '| `%s` | `%s` | `%s` |\n' "${name}" "${size_human}" "${share}"
    done
  } > "${report}"
}

write_artifact_manifest() {
  local firmware_path="$1"

  cd "${firmware_path}"
  find . -maxdepth 1 -type f ! -name artifact-manifest.txt ! -name artifact-manifest.tmp -print | while IFS= read -r file; do
    basename "${file}"
  done | sort > artifact-manifest.tmp
  mv artifact-manifest.tmp artifact-manifest.txt
}

organize_firmware_files() {
  local openwrt_path="$1"
  local env_target="${2:-${GITHUB_ENV:-}}"
  local output_target="${3:-${GITHUB_OUTPUT:-}}"
  local target_dir

  target_dir="$(find "${openwrt_path}/bin/targets" -mindepth 2 -maxdepth 2 -type d | sort | head -n1 || true)"
  if [ -z "${target_dir}" ] || [ ! -d "${target_dir}" ]; then
    echo "ERROR: firmware target directory not found under ${openwrt_path}/bin/targets" >&2
    exit 1
  fi

  validate_firmware_artifacts "${target_dir}" "${openwrt_path}/.config"
  prune_virtual_machine_images "${target_dir}"

  cd "${target_dir}"
  mkdir -p packages
  if [ -d "${openwrt_path}/bin/packages" ]; then
    find "${openwrt_path}/bin/packages/" -type f \( -name "*.ipk" -o -name "*.apk" \) -exec mv -f {} packages/ \;
  fi
  tar -zcf Packages.tar.gz packages
  cp "${openwrt_path}/.config" build.config
  if [ -f "${openwrt_path}/package-source-manifest.tsv" ]; then
    cp "${openwrt_path}/package-source-manifest.tsv" package-source-manifest.tsv
  fi
  if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -f "${GITHUB_WORKSPACE}/build-environment-provenance.md" ]; then
    cp "${GITHUB_WORKSPACE}/build-environment-provenance.md" build-environment-provenance.md
  fi
  write_size_report "${openwrt_path}" "${PWD}"
  write_artifact_manifest "${PWD}"
  rm -rf packages
  append_line "${env_target}" "FIRMWARE_PATH=${PWD}"
  append_line "${output_target}" "firmware_path=${PWD}"
}

generate_sha256_checksums() {
  local firmware_path="$1"

  cd "${firmware_path}"
  rm -f sha256sums.txt
  for pattern in "*.img.gz" "*.bin" "*.tar.gz"; do
    for file in ${pattern}; do
      [ -f "${file}" ] || continue
      case "${file}" in
        Packages.tar.gz|build.config) continue ;;
      esac
      sha256sum "${file}" >> sha256sums.txt
    done
  done
  [ -s sha256sums.txt ] || echo "No firmware files matched checksum patterns."
  write_artifact_manifest "${firmware_path}"
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  download-dependencies)
    download_dependencies "${2:-}" "${3:-${MAKE_DOWNLOAD_JOBS:-8}}"
    ;;
  compile-firmware)
    compile_firmware "${2:-}" "${3:-${GITHUB_WORKSPACE:-$(pwd)}}" "${4:-${GITHUB_OUTPUT:-}}" "${5:-${GITHUB_ENV:-}}"
    ;;
  dump-failure-context)
    dump_failure_context "${2:-}" "${3:-${GITHUB_WORKSPACE:-$(pwd)}}"
    ;;
  optimize-build-dirs)
    optimize_build_directories "${2:-}"
    ;;
  organize-firmware-files)
    organize_firmware_files "${2:-}" "${3:-${GITHUB_ENV:-}}" "${4:-${GITHUB_OUTPUT:-}}"
    ;;
  generate-sha256)
    generate_sha256_checksums "${2:-}"
    ;;
  *)
    echo "Usage: $0 <subcommand> [args...]" >&2
    echo "Subcommands: download-dependencies, compile-firmware, dump-failure-context, optimize-build-dirs, organize-firmware-files, generate-sha256" >&2
    exit 1
    ;;
esac
