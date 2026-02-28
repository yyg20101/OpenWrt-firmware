#!/usr/bin/env bash
set -euo pipefail

OPENWRT_PATH_ARG="${1:-${OPENWRT_PATH:-}}"
ENV_OUT="${2:-${GITHUB_ENV:-}}"
REPO_URL_ARG="${3:-${REPO_URL:-}}"

if [ -z "${OPENWRT_PATH_ARG}" ] || [ ! -d "${OPENWRT_PATH_ARG}" ]; then
  echo "ERROR: OPENWRT_PATH is missing or invalid: ${OPENWRT_PATH_ARG}" >&2
  exit 1
fi

if [ -z "${ENV_OUT}" ]; then
  echo "ERROR: env output target is required" >&2
  exit 1
fi

if [ -z "${REPO_URL_ARG}" ]; then
  echo "ERROR: REPO_URL is required" >&2
  exit 1
fi

cd "${OPENWRT_PATH_ARG}"

SOURCE_REPO="$(echo "${REPO_URL_ARG}" | awk -F '/' '{print $(NF)}')"
WRT_HASH="$(git log -1 --pretty=format:'%h')"
CACHE_WEEK="$(date +%Y-%W)"

{
  echo "SOURCE_REPO=${SOURCE_REPO}"
  echo "WRT_HASH=${WRT_HASH}"
  echo "CACHE_WEEK=${CACHE_WEEK}"
} >> "${ENV_OUT}"
