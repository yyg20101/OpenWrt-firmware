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
#sed -i '/helloworld/d' feeds.conf.default
#sed -i '/luci/d' feeds.conf.default

# Add luci
#sed -i '2isrc-git luci https://github.com/yyg20101/luci.git;openwrt-23.05' feeds.conf.default

# Add passwall
# 定义 Git 仓库地址和 Feed 名称
#REPO_URL="https://github.com/xiaorouji/openwrt-passwall.git"
#FEED_NAME="passwall"

# 获取并过滤最新的 tag，排除包含 "smartdns" 的 tag
#LATEST_TAG=$(git ls-remote --tags --sort="v:refname" "$REPO_URL" | awk -F'/' '{print $3}' | grep -v 'smartdns' | tail -n1)
# 指定tag版本
#LATEST_TAG="4.78-4"

# 判断是否成功获取到最新 tag
#if [ -z "$LATEST_TAG" ]; then
#  echo "未找到符合条件的 tag，使用默认分支"
#  FEED_SOURCE="$REPO_URL"
#else
#  echo "最新的符合条件的 tag 是: $LATEST_TAG"
#  FEED_SOURCE="$REPO_URL^$LATEST_TAG"
#fi

# 添加 feed source 到 feeds.conf.default
#echo "src-git $FEED_NAME $FEED_SOURCE" >> feeds.conf.default

#echo "已将 $FEED_NAME feed source 添加到 feeds.conf.default"

# Add a feed source
# echo 'src-git helloworld https://github.com/fw876/helloworld.git' >>feeds.conf.default
echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git" >> feeds.conf.default

# 提取最终地址部分
REPO_NAME=$(echo "$REPO_URL" | awk -F'/' '{print $NF}')

# 检查提取的地址是否是 immortalwrt
if [ "$REPO_NAME" = "immortalwrt" ]; then
  echo "仓库地址是 immortalwrt，无需添加 wwan_packages 源。"
else
  echo "仓库地址不是 immortalwrt，添加 wwan_packages 源到 feeds.conf.default..."
  
  # 追加 wwan_packages 源到 feeds.conf.default
  echo "src-git wwan_packages https://github.com/immortalwrt/wwan-packages.git" >> feeds.conf.default
  
  echo "添加完成。"
fi

#取消nss相关feed
# echo "CONFIG_FEED_nss_packages=n" >> ./.config
# echo "CONFIG_FEED_sqm_scripts_nss=n" >> ./.config
#设置NSS版本
echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
