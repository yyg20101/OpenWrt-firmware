#!/usr/bin/env bash
set -euo pipefail

# Remove region-specific mirrors for better cross-region stability in GitHub Actions.
# 在 GitHub Actions 场景下移除区域镜像项，减少镜像不可达导致的下载失败。
strip_cn_mirror_entries() {
  local file_path="$1"
  if [ -f "$file_path" ]; then
    sed -i '/\.cn\//d; /tencent/d; /aliyun/d' "$file_path"
    echo "Sanitized mirror entries: $file_path"
  else
    echo "Skip missing file: $file_path"
  fi
}

strip_cn_mirror_entries "scripts/projectsmirrors.json"
strip_cn_mirror_entries "scripts/download.pl"
