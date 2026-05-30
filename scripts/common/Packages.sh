#!/usr/bin/env bash
set -euo pipefail

AUTO_LATEST_TAG="${AUTO_LATEST_TAG:-true}"
LATEST_TAG_EXCLUDE_PATTERN="${LATEST_TAG_EXCLUDE_PATTERN:-smartdns}"
ALLOWED_CLEAN_ROOTS=(./ ../feeds/luci/ ../feeds/packages/)

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $cmd" >&2
    exit 1
  fi
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    require_cmd "$cmd"
  done
}

RUN_WITH_RETRIES_ATTEMPTS="${RUN_WITH_RETRIES_ATTEMPTS:-3}"
RUN_WITH_RETRIES_DELAY_SECONDS="${RUN_WITH_RETRIES_DELAY_SECONDS:-10}"

run_with_retries() {
  local description="$1"
  shift
  local attempt=1
  local delay="${RUN_WITH_RETRIES_DELAY_SECONDS}"
  local status=0

  while true; do
    if "$@"; then
      return 0
    fi

    status="$?"
    if [ "${attempt}" -ge "${RUN_WITH_RETRIES_ATTEMPTS}" ]; then
      echo "ERROR: ${description} failed after ${RUN_WITH_RETRIES_ATTEMPTS} attempt(s)." >&2
      return "${status}"
    fi

    echo "WARNING: ${description} failed on attempt ${attempt}/${RUN_WITH_RETRIES_ATTEMPTS}; retrying in ${delay}s." >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

run_capture_with_retries() {
  local description="$1"
  shift
  local attempt=1
  local delay="${RUN_WITH_RETRIES_DELAY_SECONDS}"
  local status=0
  local tmp_output

  tmp_output="$(mktemp)"
  while true; do
    : > "$tmp_output"
    if "$@" > "$tmp_output"; then
      cat "$tmp_output"
      rm -f "$tmp_output"
      return 0
    fi

    status="$?"
    if [ "${attempt}" -ge "${RUN_WITH_RETRIES_ATTEMPTS}" ]; then
      rm -f "$tmp_output"
      echo "ERROR: ${description} failed after ${RUN_WITH_RETRIES_ATTEMPTS} attempt(s)." >&2
      return "${status}"
    fi

    echo "WARNING: ${description} failed on attempt ${attempt}/${RUN_WITH_RETRIES_ATTEMPTS}; retrying in ${delay}s." >&2
    sleep "${delay}"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

record_package_source() {
  local pkg_name="$1"
  local pkg_repo="$2"
  local ref="$3"
  local commit="$4"
  local mode="${5:-}"
  local manifest="${PACKAGE_SOURCE_MANIFEST:-../package-source-manifest.tsv}"

  if [ ! -f "$manifest" ]; then
    printf 'package\trepository\tref\tcommit\tmode\n' > "$manifest"
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$pkg_name" "$pkg_repo" "$ref" "$commit" "$mode" >> "$manifest"
}

validate_pkg_name() {
  local name="$1"
  [[ "$name" =~ ^[A-Za-z0-9._+-]+$ ]]
}

validate_pkg_repo() {
  local repo="$1"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]
}

resolve_existing_dir_abs() {
  local path="$1"
  [ -d "$path" ] || return 1
  (cd "$path" && pwd -P)
}

safe_remove_dir() {
  local dir="$1"
  local dir_abs root root_abs
  dir_abs="$(resolve_existing_dir_abs "$dir")" || return 0

  for root in "${ALLOWED_CLEAN_ROOTS[@]}"; do
    root_abs="$(resolve_existing_dir_abs "$root")" || continue
    case "$dir_abs" in
      "$root_abs")
        echo "Skip deleting root itself: $dir_abs"
        return 0
        ;;
      "$root_abs"/*)
        rm -rf "$dir"
        echo "Deleted: $dir"
        return 0
        ;;
    esac
  done

  echo "Skip unsafe delete target: $dir_abs" >&2
  return 0
}

# install/update package from GitHub
# 从 GitHub 拉取并覆盖本地/feeds 中的包
UPDATE_PACKAGE() {
  local pkg_name="$1"
  local pkg_repo="$2"
  local pkg_branch="$3"
  local pkg_special="${4:-}"
  local custom_aliases="${5:-}"

  require_cmds git find awk grep cut tail rm cp mv dirname tr mktemp

  if ! validate_pkg_name "$pkg_name"; then
    echo "ERROR: invalid package name: $pkg_name" >&2
    return 1
  fi
  if ! validate_pkg_repo "$pkg_repo"; then
    echo "ERROR: invalid repo format (owner/repo expected): $pkg_repo" >&2
    return 1
  fi

  local repo_name
  repo_name="$(echo "$pkg_repo" | cut -d '/' -f 2)"

  local -a names_to_cleanup
  names_to_cleanup=("$pkg_name")
  if [ -n "$custom_aliases" ]; then
    local -a alias_arr
    read -r -a alias_arr <<< "$custom_aliases"
    names_to_cleanup+=("${alias_arr[@]}")
  fi

  echo ""
  echo "==> UPDATE_PACKAGE: $pkg_name from $pkg_repo"

  # cleanup conflicting directories
  # 清理本地与 feeds 中可能冲突的同名目录
  for name in "${names_to_cleanup[@]}"; do
    if [ -z "$name" ] || ! validate_pkg_name "$name"; then
      echo "Skip invalid cleanup alias: $name" >&2
      continue
    fi
    echo "Searching existing dirs by exact name: $name"
    while IFS= read -r -d '' dir; do
      safe_remove_dir "$dir"
    done < <(find ./ ../feeds/luci/ ../feeds/packages/ -mindepth 1 -maxdepth 3 -type d -iname "$name" -print0 2>/dev/null || true)
  done

  # pick latest stable-ish tag (excluding smartdns tags), fallback to branch
  # 选取最新 tag（排除 smartdns），失败则回退到 branch
  local latest_tag=""
  if [ "$AUTO_LATEST_TAG" = "true" ]; then
    latest_tag="$(run_capture_with_retries "list tags for $pkg_repo" git ls-remote --tags --refs --sort='v:refname' "https://github.com/$pkg_repo.git" \
      | awk -F'/' '{print $3}' \
      | grep -Ev "${LATEST_TAG_EXCLUDE_PATTERN}" \
      | tail -n1 || true)"
  fi

  local branch_or_tag="$pkg_branch"
  if [ -n "$latest_tag" ]; then
    branch_or_tag="$latest_tag"
    echo "Using latest tag: $branch_or_tag"
  else
    echo "No suitable tag found (or AUTO_LATEST_TAG disabled), fallback ref: $branch_or_tag"
  fi

  [ -d "./$repo_name" ] && rm -rf "./$repo_name"
  run_with_retries "clone $pkg_repo@$branch_or_tag" git clone --depth=1 --single-branch --branch "$branch_or_tag" "https://github.com/$pkg_repo.git"
  local cloned_commit
  cloned_commit="$(git -C "$repo_name" rev-parse HEAD)"
  echo "Package source: $pkg_name $pkg_repo $branch_or_tag $cloned_commit"
  record_package_source "$pkg_name" "$pkg_repo" "$branch_or_tag" "$cloned_commit" "$pkg_special"

  if [[ "$pkg_special" == "pkg" ]]; then
    # Extract matched package dirs from monorepo-style source
    # 从大仓库中提取匹配包目录
    local matched=0
    while IFS= read -r -d '' makefile; do
      local dir
      local dir_name
      local dir_name_lc
      local pkg_name_lc
      dir="$(dirname "$makefile")"
      dir_name="${dir##*/}"
      dir_name_lc="$(printf '%s' "$dir_name" | tr '[:upper:]' '[:lower:]')"
      pkg_name_lc="$(printf '%s' "$pkg_name" | tr '[:upper:]' '[:lower:]')"
      [[ "$dir_name_lc" == *"$pkg_name_lc"* ]] || continue
      cp -rf "$dir" ./
      matched=1
    done < <(find "./$repo_name" -mindepth 2 -maxdepth 5 -type f -name "Makefile" -print0 2>/dev/null || true)
    if [ "$matched" -ne 1 ]; then
      echo "ERROR: pkg mode enabled but no directory matched pattern '*$pkg_name*' in $repo_name" >&2
      rm -rf "./$repo_name/"
      return 1
    fi
    rm -rf "./$repo_name/"
  elif [[ "$pkg_special" == "all" ]]; then
    # Extract every top-level package directory that contains a Makefile.
    # 从大仓库中提取所有顶层 OpenWrt 包目录。
    local copied=0
    while IFS= read -r -d '' makefile; do
      cp -rf "$(dirname "$makefile")" ./
      copied=1
    done < <(find "./$repo_name" -mindepth 2 -maxdepth 2 -type f -name "Makefile" -print0 2>/dev/null || true)
    if [ "$copied" -ne 1 ]; then
      echo "ERROR: all mode enabled but no top-level package Makefile found in $repo_name" >&2
      rm -rf "./$repo_name/"
      return 1
    fi
    rm -rf "./$repo_name/"
  elif [[ "$pkg_special" == "name" ]]; then
    [ -e "$pkg_name" ] && rm -rf "$pkg_name"
    mv -f "$repo_name" "$pkg_name"
  fi
}

# update package version by GitHub release metadata
# 根据 GitHub release 元数据更新版本
UPDATE_VERSION() {
  local pkg_name="$1"
  local prerelease_mark="${2:-not}"
  local pkg_files

  require_cmds find grep curl jq sha256sum dpkg sed mktemp

  pkg_files="$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$pkg_name/Makefile" 2>/dev/null || true)"

  echo ""
  if [ -z "$pkg_files" ]; then
    echo "$pkg_name not found!"
    return
  fi

  echo "$pkg_name version update started"

  while IFS= read -r pkg_file; do
    [ -z "$pkg_file" ] && continue

    local pkg_repo
    pkg_repo="$(grep -Pho 'PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)' "$pkg_file" | head -n 1 || true)"
    [ -z "$pkg_repo" ] && continue

    local pkg_ver
    pkg_ver="$(run_capture_with_retries "fetch release metadata for $pkg_repo" curl -fsSL "https://api.github.com/repos/$pkg_repo/releases" \
      | jq -r "map(select(.prerelease|$prerelease_mark)) | first | .tag_name" || true)"
    [ -z "$pkg_ver" ] || [ "$pkg_ver" = "null" ] && continue

    local new_ver new_hash old_ver
    new_ver="$(echo "$pkg_ver" | sed 's/.*v//g; s/_/./g')"
    local source_archive
    source_archive="$(mktemp)"
    if run_with_retries "download source archive for $pkg_repo@$pkg_ver" curl -fsSL "https://codeload.github.com/$pkg_repo/tar.gz/$pkg_ver" -o "$source_archive"; then
      new_hash="$(sha256sum "$source_archive" | cut -b -64 || true)"
    else
      new_hash=""
    fi
    rm -f "$source_archive"
    old_ver="$(grep -Po 'PKG_VERSION:=\K.*' "$pkg_file" || true)"

    if [[ -n "$new_ver" && -n "$new_hash" && "$new_ver" =~ ^[0-9].* ]] \
      && dpkg --compare-versions "$old_ver" lt "$new_ver"; then
      sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$new_ver/g" "$pkg_file"
      sed -i "s/PKG_HASH:=.*/PKG_HASH:=$new_hash/g" "$pkg_file"
      echo "Updated: $pkg_file ($old_ver -> $new_ver)"
    else
      echo "Already latest or unable to update: $pkg_file"
    fi
  done <<< "$pkg_files"
}

# Usage examples:
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf"
# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name/all，可选"
# UPDATE_VERSION "sing-box"
