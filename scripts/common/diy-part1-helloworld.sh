#!/usr/bin/env bash
#
# Shared pre-feeds hook for profiles that require helloworld feed.
# 供多个设备复用的 feeds 前置脚本（追加 helloworld 源）。
#

set -euo pipefail

echo "src-git helloworld https://github.com/fw876/helloworld.git" >> feeds.conf.default
