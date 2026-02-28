#!/usr/bin/env bash
# Default post-feeds hook.
# 默认的 feeds 后置脚本。

# Modify default IP / 修改默认 IP
# sed -i 's/192.168.1.1/192.168.50.5/g' package/base-files/files/bin/config_generate

# Modify default theme / 修改默认主题
# sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# Modify hostname / 修改主机名
# sed -i 's/OpenWrt/P3TERX-Router/g' package/base-files/files/bin/config_generate

# Update Golang feed example / 更新 Golang feed 示例
# rm -rf feeds/packages/lang/golang
# git clone https://github.com/sbwml/packages_lang_golang -b 23.x feeds/packages/lang/golang
