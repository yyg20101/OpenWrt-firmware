#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"
bash "${ROOT_DIR}/scripts/ci/profiles.sh" validate "" "" "${ROOT_DIR}"
