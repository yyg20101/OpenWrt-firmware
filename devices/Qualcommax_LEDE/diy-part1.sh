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

# Add a feed source
echo 'src-git helloworld https://github.com/fw876/helloworld.git' >>feeds.conf.default
# echo "src-git passwall_packages https://github.com/xiaorouji/openwrt-passwall-packages.git" >> feeds.conf.default

