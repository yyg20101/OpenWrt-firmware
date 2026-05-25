#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-}"
ENV_OUT="${2:-${GITHUB_ENV:-}}"
WORKSPACE="${3:-${GITHUB_WORKSPACE:-$(pwd)}}"
OUTPUT_OUT="${4:-${GITHUB_OUTPUT:-}}"

if [ -z "${PROFILE}" ]; then
  echo "ERROR: profile is required" >&2
  exit 1
fi

bash "${WORKSPACE}/scripts/ci/profiles.sh" export-env "${PROFILE}" "${ENV_OUT}" "${WORKSPACE}" "${OUTPUT_OUT}"
