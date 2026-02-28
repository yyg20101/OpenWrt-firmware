#!/usr/bin/env bash
set -euo pipefail

status=0

for env_file in devices/*/env; do
  [ -f "${env_file}" ] || continue
  echo "Validating ${env_file}"

  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    if ! [[ "$line" =~ ^[A-Z0-9_]+:[[:space:]]*.+$ ]]; then
      echo "Invalid line in ${env_file}: ${line}" >&2
      status=1
    fi
  done < "${env_file}"

  for key in REPO_URL REPO_BRANCH FIRMWARE_TAG; do
    if ! grep -Eq "^${key}:[[:space:]]*.+$" "${env_file}"; then
      echo "Missing key ${key} in ${env_file}" >&2
      status=1
    fi
  done

  if ! grep -Eq '^REPO_URL:[[:space:]]*https?://.+' "${env_file}"; then
    echo "REPO_URL is invalid in ${env_file}" >&2
    status=1
  fi
done

exit "${status}"
