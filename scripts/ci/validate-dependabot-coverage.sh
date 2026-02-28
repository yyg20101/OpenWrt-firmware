#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-.}"
CONFIG_FILE="${ROOT_DIR}/.github/dependabot.yml"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: missing ${CONFIG_FILE}" >&2
  exit 1
fi

find_any() {
  local pattern="$1"
  find "${ROOT_DIR}" -type f -not -path "${ROOT_DIR}/.git/*" -name "${pattern}" -print -quit 2>/dev/null
}

has_file_glob() {
  local pattern="$1"
  local found
  found="$(find_any "${pattern}" || true)"
  [ -n "${found}" ]
}

has_npm=false
has_pip=false
has_docker=false

if has_file_glob "package.json" || has_file_glob "package-lock.json" || has_file_glob "yarn.lock" || has_file_glob "pnpm-lock.yaml"; then
  has_npm=true
fi

if has_file_glob "requirements.txt" || has_file_glob "requirements-*.txt" || has_file_glob "pyproject.toml" || has_file_glob "Pipfile" || has_file_glob "Pipfile.lock" || has_file_glob "poetry.lock"; then
  has_pip=true
fi

if has_file_glob "Dockerfile" || has_file_glob "Dockerfile.*" || has_file_glob "docker-compose.yml" || has_file_glob "docker-compose.yaml" || has_file_glob "compose.yml" || has_file_glob "compose.yaml"; then
  has_docker=true
fi

ecosystems="$(ruby -e "require 'yaml'; cfg=YAML.load_file('${CONFIG_FILE}'); puts Array(cfg['updates']).map{|u| u['package-ecosystem']}.compact.join(\"\\n\")")"

has_ecosystem() {
  local target="$1"
  printf '%s\n' "${ecosystems}" | grep -Fxq "${target}"
}

status=0

if [ "${has_npm}" = true ] && ! has_ecosystem "npm"; then
  echo "ERROR: npm manifests detected but dependabot 'npm' ecosystem is not configured." >&2
  status=1
fi

if [ "${has_pip}" = true ] && ! has_ecosystem "pip"; then
  echo "ERROR: pip manifests detected but dependabot 'pip' ecosystem is not configured." >&2
  status=1
fi

if [ "${has_docker}" = true ] && ! has_ecosystem "docker"; then
  echo "ERROR: docker manifests detected but dependabot 'docker' ecosystem is not configured." >&2
  status=1
fi

echo "Dependabot coverage check:"
echo "  npm manifests: ${has_npm}"
echo "  pip manifests: ${has_pip}"
echo "  docker manifests: ${has_docker}"
echo "  configured ecosystems:"
printf '%s\n' "${ecosystems}" | sed 's/^/    - /'

exit "${status}"
