#!/usr/bin/env bash
set -euo pipefail

resolve_path() {
  local workspace="$1"
  local path="$2"
  if [[ "${path}" = /* ]]; then
    printf '%s\n' "${path}"
  else
    printf '%s/%s\n' "${workspace}" "${path}"
  fi
}

load_base_config() {
  local openwrt_path="$1"
  local config_file="$2"
  local workspace="$3"
  local config_path

  config_path="$(resolve_path "${workspace}" "${config_file}")"
  echo "CONFIG_FILE path: ${config_file}"
  cp "${config_path}" "${openwrt_path}/.config"
}

extend_driver_config() {
  local openwrt_path="$1"
  local workspace="$2"
  local driver_config_path="${DRIVER_CONFIG_PATH:-scripts/common/Driver.config}"
  local driver_config_glob="${DRIVER_CONFIG_GLOB:-}"
  local config_path
  local driver_config
  local existing
  local -a config_files=()
  local glob_path
  local shell_globstar
  local shell_nullglob

  add_config_file() {
    local candidate="$1"
    for existing in "${config_files[@]}"; do
      if [ "${existing}" = "${candidate}" ]; then
        return
      fi
    done
    config_files+=("${candidate}")
  }

  config_path="$(resolve_path "${workspace}" "${driver_config_path}")"
  if [ -f "${config_path}" ]; then
    add_config_file "${config_path}"
  fi

  if [ -n "${driver_config_glob}" ]; then
    if [[ "${driver_config_glob}" = /* ]]; then
      glob_path="${driver_config_glob}"
    else
      glob_path="${workspace}/${driver_config_glob}"
    fi
    shell_globstar="$(shopt -p globstar || true)"
    shell_nullglob="$(shopt -p nullglob || true)"
    shopt -s globstar nullglob
    while IFS= read -r driver_config; do
      [ -f "${driver_config}" ] && add_config_file "${driver_config}"
    done < <(compgen -G "${glob_path}" | sort || true)
    eval "${shell_globstar:-:}"
    eval "${shell_nullglob:-:}"
  fi

  if [ "${#config_files[@]}" -eq 0 ]; then
    echo "No driver config files found (DRIVER_CONFIG_PATH='${driver_config_path}', DRIVER_CONFIG_GLOB='${driver_config_glob}'), skip."
    return
  fi

  echo "" >> "${openwrt_path}/.config"
  for driver_config in "${config_files[@]}"; do
    echo "Append driver config: ${driver_config}"
    cat "${driver_config}" >> "${openwrt_path}/.config"
    echo "" >> "${openwrt_path}/.config"
  done
}

snapshot_effective_config() {
  local openwrt_path="$1"
  local workspace="$2"
  cp "${openwrt_path}/.config" "${workspace}/.merged.config"
}

load_custom_feeds() {
  local openwrt_path="$1"
  local workspace="$2"
  local feeds_conf="$3"
  local diy_p1_sh="$4"

  if [ -n "${feeds_conf}" ]; then
    local feeds_conf_path
    feeds_conf_path="$(resolve_path "${workspace}" "${feeds_conf}")"
    [ -f "${feeds_conf_path}" ] && mv "${feeds_conf_path}" "${openwrt_path}/feeds.conf.default"
  fi

  if [ -n "${diy_p1_sh}" ]; then
    local diy_p1_path
    diy_p1_path="$(resolve_path "${workspace}" "${diy_p1_sh}")"
    if [ -f "${diy_p1_path}" ]; then
      chmod +x "${diy_p1_path}"
      cd "${openwrt_path}"
      "${diy_p1_path}"
      return
    fi
  fi
  echo "DIY_P1_SH missing, skip."
}

run_general_script() {
  local openwrt_path="$1"
  local workspace="$2"
  local general_script_path="${GENERAL_SCRIPT_PATH:-scripts/common/General.sh}"
  local general_script

  general_script="$(resolve_path "${workspace}" "${general_script_path}")"
  if [ -f "${general_script}" ]; then
    chmod +x "${general_script}"
    cd "${openwrt_path}"
    "${general_script}"
  else
    echo "GENERAL_SCRIPT_PATH missing (${general_script_path}), skip."
  fi
}

apply_package_overrides() {
  local openwrt_path="$1"
  local workspace="$2"
  local package_file="$3"
  local package_base_script_path="${PACKAGE_BASE_SCRIPT_PATH:-scripts/common/Packages.sh}"
  local package_base_script

  if [ -z "${package_file}" ]; then
    echo "Package override file missing, skip."
    return
  fi

  local package_file_path
  package_file_path="$(resolve_path "${workspace}" "${package_file}")"
  if [ ! -f "${package_file_path}" ]; then
    echo "Package override file missing, skip."
    return
  fi

  local tmp_packages_sh
  tmp_packages_sh="$(mktemp)"
  trap 'rm -f "${tmp_packages_sh}"' RETURN
  package_base_script="$(resolve_path "${workspace}" "${package_base_script_path}")"
  if [ ! -f "${package_base_script}" ]; then
    echo "PACKAGE_BASE_SCRIPT_PATH missing (${package_base_script_path}), skip."
    return
  fi
  cp "${package_base_script}" "${tmp_packages_sh}"
  echo "" >> "${tmp_packages_sh}"
  cat "${package_file_path}" >> "${tmp_packages_sh}"
  chmod +x "${tmp_packages_sh}"
  cd "${openwrt_path}/package/"
  "${tmp_packages_sh}"
  echo "Package override script executed."
}

load_custom_configuration() {
  local openwrt_path="$1"
  local workspace="$2"
  local diy_p2_sh="$3"

  [ -e "${workspace}/files" ] && mv "${workspace}/files" "${openwrt_path}/files"
  if [ -f "${workspace}/.merged.config" ]; then
    cp "${workspace}/.merged.config" "${openwrt_path}/.config"
  fi

  if [ -n "${diy_p2_sh}" ]; then
    local diy_p2_path
    diy_p2_path="$(resolve_path "${workspace}" "${diy_p2_sh}")"
    if [ -f "${diy_p2_path}" ]; then
      chmod +x "${diy_p2_path}"
      cd "${openwrt_path}"
      "${diy_p2_path}"
      return
    fi
  fi
  echo "DIY_P2_SH missing, skip."
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  load-base-config)
    load_base_config "${2:-}" "${3:-}" "${4:-}"
    ;;
  extend-driver-config)
    extend_driver_config "${2:-}" "${3:-}"
    ;;
  snapshot-effective-config)
    snapshot_effective_config "${2:-}" "${3:-}"
    ;;
  load-custom-feeds)
    load_custom_feeds "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    ;;
  run-general-script)
    run_general_script "${2:-}" "${3:-}"
    ;;
  apply-package-overrides)
    apply_package_overrides "${2:-}" "${3:-}" "${4:-}"
    ;;
  load-custom-configuration)
    load_custom_configuration "${2:-}" "${3:-}" "${4:-}"
    ;;
  *)
    echo "Usage: $0 <subcommand> [args...]" >&2
    echo "Subcommands: load-base-config, extend-driver-config, snapshot-effective-config, load-custom-feeds, run-general-script, apply-package-overrides, load-custom-configuration" >&2
    exit 1
    ;;
esac
