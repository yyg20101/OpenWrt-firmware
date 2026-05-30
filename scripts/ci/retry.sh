#!/usr/bin/env bash

run_with_retries() {
  local description="$1"
  shift
  local attempts="${CI_RETRY_ATTEMPTS:-3}"
  local delay="${CI_RETRY_DELAY_SECONDS:-10}"
  local attempt=1
  local status=0

  while true; do
    if "$@"; then
      return 0
    fi

    status="$?"
    if [ "${attempt}" -ge "${attempts}" ]; then
      echo "ERROR: ${description} failed after ${attempts} attempt(s)." >&2
      return "${status}"
    fi

    echo "WARNING: ${description} failed on attempt ${attempt}/${attempts}; retrying in ${delay}s." >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
