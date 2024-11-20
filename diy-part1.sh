#!/bin/bash
#
# https://github.com/P3TERX/Actions-OpenWrt
# File name: diy-part1.sh
# Description: OpenWrt DIY script part 1 (Before Update feeds)
#
# Copyright (c) 2019-2024 P3TERX <https://p3terx.com>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# Uncomment a feed source
sed -i '/helloworld/d' feeds.conf.default
sed -i '/luci/d' feeds.conf.default

# Add luci
sed -i '2isrc-git luci https://github.com/yyg20101/luci.git;openwrt-23.05' feeds.conf.default

# Add passwall
# 定义 Git 仓库地址和 Feed 名称
REPO_URL="https://github.com/xiaorouji/openwrt-passwall.git"
FEED_NAME="passwall"

# 获取并过滤最新的 tag，排除包含 "smartdns" 的 tag
LATEST_TAG=$(git ls-remote --tags --sort="v:refname" "$REPO_URL" | awk -F'/' '{print $3}' | grep -v 'smartdns' | tail -n1)
# 指定tag版本
#LATEST_TAG="4.78-4"

# 判断是否成功获取到最新 tag
if [ -z "$LATEST_TAG" ]; then
  echo "未找到符合条件的 tag，使用默认分支"
  FEED_SOURCE="$REPO_URL"
else
  echo "最新的符合条件的 tag 是: $LATEST_TAG"
  FEED_SOURCE="$REPO_URL^$LATEST_TAG"
fi

# 添加 feed source 到 feeds.conf.default
echo "src-git $FEED_NAME $FEED_SOURCE" >> feeds.conf.default

echo "已将 $FEED_NAME feed source 添加到 feeds.conf.default"

# Add a feed source
echo 'src-git helloworld https://github.com/fw876/helloworld.git' >>feeds.conf.default
