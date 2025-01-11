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
fetch_code "https://github.com/xiaorouji/openwrt-passwall2.git" "luci-app-passwall2" "main"
fetch_code "https://github.com/sbwml/luci-app-alist.git" "luci-app-alist" "main"

# # 安装和更新软件包
# UPDATE_PACKAGE() {
#   local PKG_NAME=$1       # 包名
#   local PKG_REPO=$2       # Git 项目地址（不包含 https://github.com/）
#   local DEFAULT_BRANCH=$3 # 默认分支
#   local PKG_SPECIAL=$4    # 特殊处理类型（可选，pkg: 提取插件；name: 重命名包）

#   local REPO_URL="https://github.com/$PKG_REPO.git" # 完整仓库地址
#   local REPO_NAME=$(echo $PKG_REPO | cut -d '/' -f 2) # 提取仓库名称
#   local TEMP_DIR=$(mktemp -d) # 创建临时目录

#   # 克隆仓库（仅元数据）
#   git clone --bare "$REPO_URL" "$TEMP_DIR" > /dev/null 2>&1

#   # 获取最新的 tag，按创建时间排序并排除包含 "smartdns" 的 tag
#   local LATEST_TAG=$(git -C "$TEMP_DIR" tag --sort=-creatordate | grep -v 'smartdns' | head -n1)

#   # 删除临时目录
#   rm -rf "$TEMP_DIR"

#   # 判断是否成功获取到最新 tag
#   local BRANCH_OR_TAG
#   if [ -z "$LATEST_TAG" ]; then
#     echo "未找到符合条件的 tag，使用默认分支: $DEFAULT_BRANCH"
#     BRANCH_OR_TAG=$DEFAULT_BRANCH
#   else
#     echo "最新的符合条件的 tag 是: $LATEST_TAG"
#     BRANCH_OR_TAG=$LATEST_TAG
#   fi

#   # 删除可能存在的旧版本包
#   echo "清理旧版本包: $PKG_NAME"
#   find ./ ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -name "*$PKG_NAME*" -exec rm -rf {} +

#   # 克隆仓库指定分支或 tag
#   echo "开始拉取代码，分支或 tag: $BRANCH_OR_TAG"
#   git clone --depth=1 --branch "$BRANCH_OR_TAG" "$REPO_URL"

#   # 根据特殊处理类型进行处理
#   if [ "$PKG_SPECIAL" = "pkg" ]; then
#     echo "提取包名插件: $REPO_NAME"
#     find ./$REPO_NAME -maxdepth 3 -type d -name "*$PKG_NAME*" -exec cp -rf {} ./ \;
#     rm -rf ./$REPO_NAME/
#   elif [ "$PKG_SPECIAL" = "name" ]; then
#     echo "重命名包: $REPO_NAME to $PKG_NAME"
#     mv -f $REPO_NAME $PKG_NAME
#   fi

#   # 确认处理结果
#   if [ $? -eq 0 ]; then
#     echo "代码已成功拉取并处理，版本: $BRANCH_OR_TAG"
#   else
#     echo "代码处理失败，请检查仓库地址或网络连接。"
#     exit 1
#   fi
# }

# # 如果需要支持其他包，只需再次调用 UPDATE_PACKAGE
# # UPDATE_PACKAGE "包名" "项目地址" "默认分支" "pkg/name"
# # 使用示例
# UPDATE_PACKAGE "passwall" "xiaorouji/openwrt-passwall" "main" "pkg"
# UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "master" "pkg"
# UPDATE_PACKAGE "alist" "sbwml/luci-app-alist" "main"

# ./scripts/feeds update -a
./scripts/feeds install -a
