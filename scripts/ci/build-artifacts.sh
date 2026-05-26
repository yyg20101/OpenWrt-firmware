#!/usr/bin/env bash
set -euo pipefail

append_line() {
  local target="$1"
  local line="$2"
  if [ -n "${target}" ]; then
    echo "${line}" >> "${target}"
  fi
}

download_dependencies() {
  local openwrt_path="$1"
  local jobs="${2:-${MAKE_DOWNLOAD_JOBS:-8}}"

  cd "${openwrt_path}"
  make defconfig
  make download -j"${jobs}"
  find dl -size -1024c -exec ls -l {} \;
  find dl -size -1024c -exec rm -f {} \;
}

compile_firmware() {
  local openwrt_path="$1"
  local workspace="$2"
  local output_target="${3:-${GITHUB_OUTPUT:-}}"
  local env_target="${4:-${GITHUB_ENV:-}}"
  local compile_log="${workspace}/compile.log"
  local build_exit=0
  local jobs=1

  jobs="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
  [[ "${jobs}" =~ ^[0-9]+$ ]] || jobs=1
  [ "${jobs}" -ge 1 ] || jobs=1

  cd "${openwrt_path}"
  ccache -s || true
  : > "${compile_log}"

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

  ccache -s || true
  if [ "${build_exit}" -eq 0 ]; then
    append_line "${output_target}" "status=success"
    append_line "${env_target}" "DATE=$(date +"%Y-%m-%d %H:%M:%S")"
    append_line "${env_target}" "FILE_DATE=$(date +"%Y.%m.%d")"
    return 0
  fi

  append_line "${output_target}" "status=failure"
  return "${build_exit}"
}

dump_failure_context() {
  local openwrt_path="$1"
  local workspace="$2"
  local compile_log="${workspace}/compile.log"
  local failed_pkg=""

  echo "::group::Compile Log Tail (last 300 lines)"
  tail -n 300 "${compile_log}" || true
  echo "::endgroup::"

  failed_pkg="$(grep -oE 'package/[^ ]+ failed to build' "${compile_log}" | tail -1 | awk '{print $1}' || true)"
  if [ -z "${failed_pkg}" ]; then
    echo "No failed package detected in compile.log, skip package rebuild."
    return 0
  fi

  echo "::group::Verbose Rebuild (${failed_pkg}, -j1 V=s)"
  cd "${openwrt_path}"
  make "${failed_pkg}/compile" -j1 V=s || true
  echo "::endgroup::"
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
    if grep -q '^CONFIG_VMDK_IMAGES=y$' "${config_file}"; then
      require_artifact_pattern "*-combined.vmdk" "VMDK disk images"
      if grep -q '^CONFIG_GRUB_EFI_IMAGES=y$' "${config_file}"; then
        require_artifact_pattern "*-combined-efi.vmdk" "EFI VMDK disk images"
      fi
    fi
  fi
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

  cd "${target_dir}"
  mkdir -p packages
  if [ -d "${openwrt_path}/bin/packages" ]; then
    find "${openwrt_path}/bin/packages/" -type f \( -name "*.ipk" -o -name "*.apk" \) -exec mv -f {} packages/ \;
  fi
  tar -zcf Packages.tar.gz packages
  cp "${openwrt_path}/.config" build.config
  find . -maxdepth 1 -type f ! -name artifact-manifest.txt ! -name artifact-manifest.tmp -print | while IFS= read -r file; do
    basename "${file}"
  done | sort > artifact-manifest.tmp
  mv artifact-manifest.tmp artifact-manifest.txt
  rm -rf packages
  append_line "${env_target}" "FIRMWARE_PATH=${PWD}"
  append_line "${output_target}" "firmware_path=${PWD}"
}

generate_sha256_checksums() {
  local firmware_path="$1"

  cd "${firmware_path}"
  rm -f sha256sums.txt
  for pattern in "*.img.gz" "*.vmdk" "*.bin" "*.tar.gz"; do
    for file in ${pattern}; do
      [ -f "${file}" ] || continue
      case "${file}" in
        Packages.tar.gz|build.config) continue ;;
      esac
      sha256sum "${file}" >> sha256sums.txt
    done
  done
  [ -s sha256sums.txt ] || echo "No firmware files matched checksum patterns."
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
