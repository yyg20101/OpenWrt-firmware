#!/bin/bash

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local CUSTOM_NAMES=($5)  # 第5个参数为自定义名称列表
	local REPO_NAME=$(echo $PKG_REPO | cut -d '/' -f 2)

	echo " "

	# 将 PKG_NAME 加入到需要查找的名称列表中
	if [ ${#CUSTOM_NAMES[@]} -gt 0 ]; then
		CUSTOM_NAMES=("$PKG_NAME" "${CUSTOM_NAMES[@]}")  # 将 PKG_NAME 添加到自定义名称列表的开头
	else
		CUSTOM_NAMES=("$PKG_NAME")  # 如果没有自定义名称，则只使用 PKG_NAME
	fi

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${CUSTOM_NAMES[@]}"; do
		# 查找匹配的目录
		echo "Searching directory: $NAME"
		local FOUND_DIRS=$(find ./ ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			echo "$FOUND_DIRS" | while read -r DIR; do
				rm -rf "$DIR"
				echo "Deleted directory: $DIR"
			done
		else
			echo "No directories found matching name: $NAME"
		fi
	done

	# 克隆仓库（仅元数据）
  git clone --bare "https://github.com/$PKG_REPO.git" "$TEMP_DIR" > /dev/null 2>&1

  # 获取最新的 tag，按创建时间排序并排除包含 "smartdns" 的 tag
  LATEST_TAG=$(git -C "$TEMP_DIR" tag --sort=-creatordate | grep -v 'smartdns' | head -n1)

  # 删除临时目录
  rm -rf "$TEMP_DIR"

  # 判断是否成功获取到最新 tag
  if [ -z "$LATEST_TAG" ]; then
    echo "未找到符合条件的 tag，使用默认分支: $PKG_BRANCH"
    BRANCH_OR_TAG=$PKG_BRANCH
  else
    echo "最新的符合条件的 tag 是: $LATEST_TAG"
    BRANCH_OR_TAG=$LATEST_TAG
  fi

  # 克隆 GitHub 仓库指定分支或 tag
  echo "开始拉取代码，分支或 tag: $BRANCH_OR_TAG"
	git clone --depth=1 --single-branch --branch $BRANCH_OR_TAG "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ $PKG_SPECIAL == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ $PKG_SPECIAL == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。
# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name，可选，pkg为从大杂烩中单独提取包名插件；name为重命名为包名"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-not}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	echo " "

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo "$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Pho 'PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)' $PKG_FILE | head -n 1)
		local PKG_VER=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease|$PKG_MARK)) | first | .tag_name")
		local NEW_VER=$(echo $PKG_VER | sed "s/.*v//g; s/_/./g")
		local NEW_HASH=$(curl -sL "https://codeload.github.com/$PKG_REPO/tar.gz/$PKG_VER" | sha256sum | cut -b -64)
		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")

		echo "$OLD_VER $PKG_VER $NEW_VER $NEW_HASH"

		if [[ $NEW_VER =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"
#UPDATE_VERSION "tailscale"