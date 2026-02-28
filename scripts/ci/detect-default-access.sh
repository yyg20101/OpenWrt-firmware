#!/usr/bin/env bash
set -euo pipefail

OPENWRT_PATH_ARG="${1:-${OPENWRT_PATH:-}}"
ENV_OUT="${2:-${GITHUB_ENV:-}}"

if [ -z "${OPENWRT_PATH_ARG}" ] || [ ! -d "${OPENWRT_PATH_ARG}" ]; then
  echo "ERROR: OPENWRT_PATH is missing or invalid: ${OPENWRT_PATH_ARG}" >&2
  exit 1
fi

cd "${OPENWRT_PATH_ARG}"

find_rootfs_file() {
  local rel_path="$1"
  find build_dir -type f -path "*/root-*/${rel_path}" 2>/dev/null | head -n1 || true
}

parse_lan_ip_from_network() {
  local network_file="$1"
  awk '
    $1=="config" && $2=="interface" {
      in_lan=($3=="'\''lan'\''" || $3=="\"lan\"")
      next
    }
    in_lan && $1=="option" && $2=="ipaddr" {
      gsub(/'\''|"/, "", $3)
      print $3
      exit
    }
  ' "$network_file"
}

detect_ip() {
  local ip=""
  local source=""
  local cfg_file="package/base-files/files/bin/config_generate"
  local network_file=""

  network_file="$(find_rootfs_file "etc/config/network")"
  if [ -n "$network_file" ] && [ -f "$network_file" ]; then
    ip="$(parse_lan_ip_from_network "$network_file" || true)"
    if [ -n "$ip" ] && [[ ! "$ip" =~ ^127\. ]]; then
      source="$network_file"
    else
      ip=""
    fi
  fi

  if [ -z "$ip" ] && [ -f "$cfg_file" ]; then
    if [ -z "$ip" ]; then
      ip="$(sed -nE "s/.*set network\.lan\.ipaddr='?(([0-9]{1,3}\.){3}[0-9]{1,3})'?.*/\1/p" "$cfg_file" | head -n1)"
    fi
    if [ -z "$ip" ]; then
      ip="$(sed -nE "s/.*ucidef_set_interface_lan '?(([0-9]{1,3}\.){3}[0-9]{1,3})(\/[0-9]+)?'?.*/\1/p" "$cfg_file" | head -n1)"
    fi
    if [ -z "$ip" ]; then
      ip="$(sed -nE "s/.*generate_network[[:space:]]+\"lan\"[^\"]*\"(([0-9]{1,3}\.){3}[0-9]{1,3})(\/[0-9]+)?\".*/\1/p" "$cfg_file" | head -n1)"
    fi
    if [ -z "$ip" ]; then
      ip="$(sed -nE "s/.*ipaddr:-\"(([0-9]{1,3}\.){3}[0-9]{1,3})\".*/\1/p" "$cfg_file" | head -n1)"
    fi
    if [ -n "$ip" ] && [[ ! "$ip" =~ ^127\. ]]; then
      source="$cfg_file"
    else
      ip=""
    fi
  fi

  if [ -z "$ip" ] && [ -f "$cfg_file" ]; then
    ip="$(grep -Eo '(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[0-1])(\.[0-9]{1,3}){2})' "$cfg_file" 2>/dev/null | grep -Ev '^127\.' | head -n1 || true)"
    if [ -n "$ip" ]; then
      source="$cfg_file (private-ip fallback)"
    fi
  fi

  if [ -z "$ip" ]; then
    ip="$(grep -RhsE "set network\.lan\.ipaddr='(([0-9]{1,3}\.){3}[0-9]{1,3})'" package target 2>/dev/null | sed -nE "s/.*set network\.lan\.ipaddr='(([0-9]{1,3}\.){3}[0-9]{1,3})'.*/\1/p" | head -n1 || true)"
    if [ -n "$ip" ] && [[ ! "$ip" =~ ^127\. ]]; then
      source="package/target search"
    else
      ip=""
    fi
  fi

  if [ -z "$ip" ]; then
    ip="$(find build_dir -type f \( -path "*/root-*/etc/uci-defaults/*" -o -path "*/root-*/etc/board.d/*" -o -path "*/root-*/bin/config_generate" \) -exec grep -hEo '(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[0-1])(\.[0-9]{1,3}){2})' {} + 2>/dev/null | head -n1 || true)"
    if [ -n "$ip" ]; then
      source="rootfs script private-ip scan"
    fi
  fi

  if [ -z "$ip" ]; then
    ip="$(find package target -type f \( -path "*/etc/uci-defaults/*" -o -path "*/etc/board.d/*" -o -path "*/bin/config_generate" \) -exec grep -hEo '(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[0-1])(\.[0-9]{1,3}){2})' {} + 2>/dev/null | head -n1 || true)"
    if [ -n "$ip" ]; then
      source="source script private-ip scan"
    fi
  fi

  if [ -z "$ip" ]; then
    ip="unknown (not detected from source/rootfs)"
    source="n/a"
  fi

  printf '%s\n%s\n' "$ip" "$source"
}

detect_password() {
  local shadow_file=""
  local pw_state=""
  local state=""
  local source=""
  local board_json=""
  local board_cred=""

  shadow_file="$(find_rootfs_file "etc/shadow")"
  if [ -n "$shadow_file" ] && [ -f "$shadow_file" ]; then
    source="$shadow_file"
  else
    shadow_file="package/base-files/files/etc/shadow"
    source="$shadow_file"
  fi

  if [ -f "$shadow_file" ]; then
    pw_state="$(awk -F: '$1=="root"{print $2; exit}' "$shadow_file")"
    case "$pw_state" in
      "")
        state="none (empty root password; set on first login)"
        ;;
      "!"|"*"|"!!")
        state="locked (no login password)"
        ;;
      \$*)
        state="preset hash in shadow (not plain text)"
        ;;
      *)
        state="defined in shadow (non-empty)"
        ;;
    esac
  else
    if grep -RqsE "(passwd|chpasswd).*(root|password)" package/base-files/files target/linux/*/base-files 2>/dev/null; then
      state="customized by source scripts"
    else
      state="unknown (not detected from source/rootfs)"
    fi
  fi

  board_json="$(find_rootfs_file "etc/board.json")"
  if [ -n "$board_json" ] && [ -f "$board_json" ]; then
    board_cred="$(grep -E '"root_password_(hash|plain)"[[:space:]]*:[[:space:]]*"[^"]+"' "$board_json" | head -n1 || true)"
    if [ -n "$board_cred" ]; then
      state="$state; overridden by board.json credentials"
    fi
  fi

  printf '%s\n%s\n' "$state" "$source"
}

mapfile -t ip_info < <(detect_ip)
mapfile -t pw_info < <(detect_password)

DEFAULT_IP="${ip_info[0]:-unknown (not detected from source/rootfs)}"
DEFAULT_IP_SOURCE="${ip_info[1]:-n/a}"
DEFAULT_PASSWORD="${pw_info[0]:-unknown (not detected from source/rootfs)}"
DEFAULT_PASSWORD_SOURCE="${pw_info[1]:-n/a}"

if [ -n "${ENV_OUT}" ]; then
  {
    echo "DEFAULT_IP=$DEFAULT_IP"
    echo "DEFAULT_IP_SOURCE=$DEFAULT_IP_SOURCE"
    echo "DEFAULT_PASSWORD=$DEFAULT_PASSWORD"
    echo "DEFAULT_PASSWORD_SOURCE=$DEFAULT_PASSWORD_SOURCE"
  } >> "${ENV_OUT}"
fi

echo "Detected default IP: $DEFAULT_IP (source: $DEFAULT_IP_SOURCE)"
echo "Detected default password state: $DEFAULT_PASSWORD (source: $DEFAULT_PASSWORD_SOURCE)"
