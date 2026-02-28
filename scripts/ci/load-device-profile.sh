#!/usr/bin/env bash
set -euo pipefail

MODEL="${1:-}"
ENV_OUT="${2:-${GITHUB_ENV:-}}"
WORKSPACE="${3:-${GITHUB_WORKSPACE:-$(pwd)}}"

if [ -z "${MODEL}" ]; then
  echo "ERROR: model is required" >&2
  exit 1
fi

if [ -z "${ENV_OUT}" ]; then
  echo "ERROR: env output target is required" >&2
  exit 1
fi

cd "${WORKSPACE}"

DEVICE_PATH="devices/${MODEL}"
CONFIG_FILE_VALUE="${CONFIG_FILE:-.config}"
FEEDS_CONF_VALUE="${FEEDS_CONF:-feeds.conf.default}"
DIY_P1_VALUE="${DIY_P1_SH:-}"
DIY_P2_VALUE="${DIY_P2_SH:-}"
PACKAGE_FILE_VALUE="${PACKAGE_FILE:-}"

append_env() {
  local key="$1"
  local value="$2"
  echo "${key}=${value}" >> "${ENV_OUT}"
}

file_exists() {
  local path="$1"
  if [[ "${path}" = /* ]]; then
    [ -f "${path}" ]
  else
    [ -f "${WORKSPACE}/${path}" ]
  fi
}

append_env "DEVICE_PATH" "${DEVICE_PATH}"

if [[ "${MODEL}" == x86_64* ]]; then
  append_env "CCACHE_GROUP" "x86_64"
elif [[ "${MODEL}" == Qualcommax* ]]; then
  append_env "CCACHE_GROUP" "qualcommax"
else
  append_env "CCACHE_GROUP" "${MODEL}"
fi

if [ -f "${DEVICE_PATH}/env" ]; then
  while IFS= read -r line || [ -n "${line}" ]; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    var_name="${line%%:*}"
    var_value="${line#*:}"
    var_name="$(echo -n "${var_name}" | xargs)"
    var_value="$(echo -n "${var_value}" | xargs)"
    [ -n "${var_value}" ] && append_env "${var_name}" "${var_value}"
  done < "${DEVICE_PATH}/env"
fi

if file_exists "${DEVICE_PATH}/${CONFIG_FILE_VALUE}"; then
  append_env "CONFIG_FILE" "${DEVICE_PATH}/${CONFIG_FILE_VALUE}"
elif file_exists "${CONFIG_FILE_VALUE}"; then
  append_env "CONFIG_FILE" "${CONFIG_FILE_VALUE}"
else
  echo "ERROR: CONFIG_FILE not found: ${DEVICE_PATH}/${CONFIG_FILE_VALUE}" >&2
  exit 1
fi

if file_exists "${DEVICE_PATH}/${FEEDS_CONF_VALUE}"; then
  append_env "FEEDS_CONF" "${DEVICE_PATH}/${FEEDS_CONF_VALUE}"
elif file_exists "${FEEDS_CONF_VALUE}"; then
  append_env "FEEDS_CONF" "${FEEDS_CONF_VALUE}"
else
  append_env "FEEDS_CONF" ""
fi

if file_exists "${DEVICE_PATH}/diy-part1.sh"; then
  append_env "DIY_P1_SH" "${DEVICE_PATH}/diy-part1.sh"
elif [ -n "${DIY_P1_VALUE}" ] && file_exists "${DIY_P1_VALUE}"; then
  append_env "DIY_P1_SH" "${DIY_P1_VALUE}"
else
  append_env "DIY_P1_SH" ""
fi

if file_exists "${DEVICE_PATH}/diy-part2.sh"; then
  append_env "DIY_P2_SH" "${DEVICE_PATH}/diy-part2.sh"
elif [ -n "${DIY_P2_VALUE}" ] && file_exists "${DIY_P2_VALUE}"; then
  append_env "DIY_P2_SH" "${DIY_P2_VALUE}"
else
  append_env "DIY_P2_SH" ""
fi

if file_exists "${DEVICE_PATH}/package"; then
  append_env "PACKAGE_FILE" "${DEVICE_PATH}/package"
elif [ -n "${PACKAGE_FILE_VALUE}" ] && file_exists "${PACKAGE_FILE_VALUE}"; then
  append_env "PACKAGE_FILE" "${PACKAGE_FILE_VALUE}"
else
  append_env "PACKAGE_FILE" ""
fi
