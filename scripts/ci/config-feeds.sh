#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "${SCRIPT_DIR}/retry.sh"

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

append_config_fragments() {
  local openwrt_path="$1"
  local workspace="$2"
  local config_fragments="${3:-}"
  local fragment
  local fragment_path

  if [ -z "${config_fragments}" ]; then
    echo "No config fragments configured, skip."
    return
  fi

  echo "" >> "${openwrt_path}/.config"
  IFS=':' read -r -a fragments <<< "${config_fragments}"
  for fragment in "${fragments[@]}"; do
    [ -n "${fragment}" ] || continue
    fragment_path="$(resolve_path "${workspace}" "${fragment}")"
    if [ ! -f "${fragment_path}" ]; then
      echo "ERROR: config fragment missing: ${fragment}" >&2
      exit 1
    fi
    echo "Append config fragment: ${fragment}"
    cat "${fragment_path}" >> "${openwrt_path}/.config"
    echo "" >> "${openwrt_path}/.config"
  done
}

snapshot_effective_config() {
  local openwrt_path="$1"
  local workspace="$2"
  cp "${openwrt_path}/.config" "${workspace}/effective.config"
}

prepare_feeds() {
  local openwrt_path="$1"
  local workspace="$2"
  local feeds_conf="$3"
  local pre_feeds_script="$4"

  if [ -n "${feeds_conf}" ]; then
    local feeds_conf_path
    feeds_conf_path="$(resolve_path "${workspace}" "${feeds_conf}")"
    if [ ! -f "${feeds_conf_path}" ]; then
      echo "ERROR: feeds config missing: ${feeds_conf}" >&2
      exit 1
    fi
    cp "${feeds_conf_path}" "${openwrt_path}/feeds.conf.default"
  fi

  if [ -n "${pre_feeds_script}" ]; then
    local pre_feeds_path
    pre_feeds_path="$(resolve_path "${workspace}" "${pre_feeds_script}")"
    if [ -f "${pre_feeds_path}" ]; then
      chmod +x "${pre_feeds_path}"
      cd "${openwrt_path}"
      "${pre_feeds_path}"
      return
    fi
  fi
  echo "Pre-feeds script missing, skip."
}

update_and_install_feeds() {
  local openwrt_path="$1"

  cd "${openwrt_path}"
  run_with_retries "feeds update" ./scripts/feeds update -a
  run_with_retries "feeds install" ./scripts/feeds install -a
}

run_general_script() {
  local openwrt_path="$1"
  local workspace="$2"
  local general_script_path="${3:-}"
  local general_script

  if [ -z "${general_script_path}" ]; then
    echo "General script not configured, skip."
    return
  fi

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
  local package_base_script_path="$3"
  local package_file="$4"
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
  local post_feeds_script="$3"

  [ -e "${workspace}/files" ] && mv "${workspace}/files" "${openwrt_path}/files"
  if [ -f "${workspace}/effective.config" ]; then
    cp "${workspace}/effective.config" "${openwrt_path}/.config"
  fi

  if [ -n "${post_feeds_script}" ]; then
    local post_feeds_path
    post_feeds_path="$(resolve_path "${workspace}" "${post_feeds_script}")"
    if [ -f "${post_feeds_path}" ]; then
      chmod +x "${post_feeds_path}"
      cd "${openwrt_path}"
      "${post_feeds_path}"
      return
    fi
  fi
  echo "Post-feeds script missing, skip."
}

SUBCOMMAND="${1:-}"
case "${SUBCOMMAND}" in
  load-base-config)
    load_base_config "${2:-}" "${3:-}" "${4:-}"
    ;;
  append-config-fragments)
    append_config_fragments "${2:-}" "${3:-}" "${4:-}"
    ;;
  snapshot-effective-config)
    snapshot_effective_config "${2:-}" "${3:-}"
    ;;
  prepare-feeds)
    prepare_feeds "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    ;;
  update-install-feeds)
    update_and_install_feeds "${2:-}"
    ;;
  run-general-script)
    run_general_script "${2:-}" "${3:-}" "${4:-}"
    ;;
  apply-package-overrides)
    apply_package_overrides "${2:-}" "${3:-}" "${4:-}" "${5:-}"
    ;;
  load-custom-configuration)
    load_custom_configuration "${2:-}" "${3:-}" "${4:-}"
    ;;
  *)
    echo "Usage: $0 <subcommand> [args...]" >&2
    echo "Subcommands: load-base-config, append-config-fragments, snapshot-effective-config, prepare-feeds, update-install-feeds, run-general-script, apply-package-overrides, load-custom-configuration" >&2
    exit 1
    ;;
esac
