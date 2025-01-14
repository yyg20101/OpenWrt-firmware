#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part2.sh
# Description: OpenWrt DIY script part 2 (After Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Modify default IP
#sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname
#sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

## 更新golang版本
#rm -rf feeds/packages/lang/golang
#git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang

# 通用拉取代码方法
fetch_code() {
  REPO_URL=$1          # Git 仓库地址
  TARGET_DIR=$2        # 拉取代码的目标路径
  DEFAULT_BRANCH=${3:-main}  # 默认分支（如果未指定则使用 main）

  rm -rf feeds/luci/applications/$TARGET_DIR
  rm -rf package/feeds/luci/$TARGET_DIR

  # 创建临时目录以获取仓库信息
  TEMP_DIR=$(mktemp -d)

  # 克隆仓库（仅元数据）
  git clone --bare "$REPO_URL" "$TEMP_DIR" > /dev/null 2>&1

  # 获取最新的 tag，按创建时间排序并排除包含 "smartdns" 的 tag
  LATEST_TAG=$(git -C "$TEMP_DIR" tag --sort=-creatordate | grep -v 'smartdns' | head -n1)

  # 删除临时目录
  rm -rf "$TEMP_DIR"

  # 判断是否成功获取到最新 tag
  if [ -z "$LATEST_TAG" ]; then
    echo "未找到符合条件的 tag，使用默认分支: $DEFAULT_BRANCH"
    BRANCH_OR_TAG=$DEFAULT_BRANCH
  else
    echo "最新的符合条件的 tag 是: $LATEST_TAG"
    BRANCH_OR_TAG=$LATEST_TAG
  fi

  # 克隆仓库指定分支或 tag
  echo "开始拉取代码，分支或 tag: $BRANCH_OR_TAG"
  git clone --depth=1 --branch "$BRANCH_OR_TAG" "$REPO_URL" "feeds/luci/applications/$TARGET_DIR"

  # 确认拉取结果
  if [ $? -eq 0 ]; then
    echo "代码已成功拉取到 $TARGET_DIR，版本: $BRANCH_OR_TAG"
  else
    echo "代码拉取失败，请检查仓库地址或网络连接。"
    exit 1
  fi
}
fetch_code "https://github.com/xiaorouji/openwrt-passwall.git" "luci-app-passwall" "main"

# ./scripts/feeds update -a
./scripts/feeds install -a

#coremark修复
sed -i 's/mkdir \$(PKG_BUILD_DIR)\/\$(ARCH)/mkdir -p \$(PKG_BUILD_DIR)\/\$(ARCH)/g' feeds/packages/utils/coremark/Makefile
