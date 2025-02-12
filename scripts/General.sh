#!/bin/bash

# GitHub Action 移除国内下载源
PROJECT_MIRRORS_FILE="scripts/projectsmirrors.json"

if [ -f "$PROJECT_MIRRORS_FILE" ]; then
    sed -i '/.cn\//d; /tencent/d; /aliyun/d' "$PROJECT_MIRRORS_FILE"
fi

# 修改开源站地址
sed -i '/.cn\//d; /tencent/d; /aliyun/d' scripts/download.pl
# sed -i 's/mirror.iscas.ac.cn/mirrors.mit.edu/g' scripts/download.pl
# sed -i 's/mirrors.aliyun.com/mirror.netcologne.de/g' scripts/download.pl