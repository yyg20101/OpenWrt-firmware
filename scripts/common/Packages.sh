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

  require_cmds git find awk grep cut tail rm cp mv

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
    latest_tag="$(git ls-remote --tags --refs --sort='v:refname' "https://github.com/$pkg_repo.git" 2>/dev/null \
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
  git clone --depth=1 --single-branch --branch "$branch_or_tag" "https://github.com/$pkg_repo.git"

  if [[ "$pkg_special" == "pkg" ]]; then
    # Extract matched package dirs from monorepo-style source
    # 从大仓库中提取匹配包目录
    local matched=0
    while IFS= read -r -d '' dir; do
      cp -rf "$dir" ./
      matched=1
    done < <(find "./$repo_name" -mindepth 2 -maxdepth 4 -type d -iname "*$pkg_name*" -print0 2>/dev/null || true)
    if [ "$matched" -ne 1 ]; then
      echo "ERROR: pkg mode enabled but no directory matched pattern '*$pkg_name*' in $repo_name" >&2
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

  require_cmds find grep curl jq sha256sum dpkg sed

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
    pkg_ver="$(curl -fsSL "https://api.github.com/repos/$pkg_repo/releases" \
      | jq -r "map(select(.prerelease|$prerelease_mark)) | first | .tag_name" || true)"
    [ -z "$pkg_ver" ] || [ "$pkg_ver" = "null" ] && continue

    local new_ver new_hash old_ver
    new_ver="$(echo "$pkg_ver" | sed 's/.*v//g; s/_/./g')"
    new_hash="$(curl -fsSL "https://codeload.github.com/$pkg_repo/tar.gz/$pkg_ver" | sha256sum | cut -b -64 || true)"
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
# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选"
# UPDATE_VERSION "sing-box"
