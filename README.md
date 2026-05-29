# OpenWrt Firmware CI

这个仓库用于通过 GitHub Actions 构建多设备 OpenWrt/ImmortalWrt 固件。当前架构已重构为“声明式设备配置 + 动态构建矩阵 + 标准化 Release”的固件 CI 系统。

## Workflows

- `Firmware CI`
  - 文件：`.github/workflows/firmware-ci.yml`
  - 手动触发参数：
    - `target`: 下拉选择单个 profile、`x86_64_all`、`qualcommax_all` 或 `all`
    - `release`: 是否发布 GitHub Release
  - 事件触发：`repository_dispatch`，事件类型为 `firmware-ci`

- `Firmware Build`
  - 文件：`.github/workflows/firmware-build.yml`
  - 可复用构建实现，负责环境初始化、源码克隆、缓存、配置、feeds、编译、产物整理、默认访问检测、Artifact 和 Release。

- `CI Lint`
  - 文件：`.github/workflows/ci-lint.yml`
  - 校验 workflow YAML、shell 语法、固件 profile、Dependabot 覆盖。

## Device Profiles

设备不再使用分散的 `devices/<model>/env`。所有构建元数据集中在：

- `devices/profiles.yml`

当前 profile：

- `x86_64_LEDE`
- `x86_64_immortalWrt`
- `Qualcommax_LEDE`
- `Qualcommax_V`
- `Qualcommax_B`

新增设备的最小步骤：

1. 新增 `devices/<profile-id>/.config`，只保留 target/subtarget/device 选择。
2. 在 `devices/profiles.yml` 的 `profiles` 下新增一段 profile：

```yaml
my_profile:
  title: My Profile
  enabled: true
  source_repo: https://github.com/example/openwrt
  source_branch: main
  firmware_tag: my-platform
  cache_group: my-cache-group
  config: devices/my_profile/.config
  config_fragments:
    - scripts/common/config/<platform>.config
```

通用固件能力由多个 `scripts/common/config/*.config` 片段组合：

- `base.config`：基础 LuCI 应用、核心工具、网络与隧道支持
- `storage.config`：磁盘、文件系统、NVMe/SATA/NFS 支持
- `usb-mobile.config`：USB 外设、USB 网卡、移动网络支持
- `proxy.config`：DNS/代理相关共享包
- `samba.config`：Samba4 文件共享栈，并显式禁用 autosamba

平台、源码系、设备族和性能优化差异继续通过 profile 的 `config_fragments` 追加，例如 `x86.config`、`x86-performance.config`、`qualcommax-ipq60xx.config`、`lede-extra.config`。

3. 运行本地校验：

```bash
bash scripts/ci/validate-profiles.sh
bash scripts/ci/profiles.sh matrix all "" "$PWD"
bash scripts/ci/profiles.sh matrix x86_64_all "" "$PWD"
```

## Local Validation

提交前建议运行：

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
```

## Release Contract

成功构建后会上传 GitHub Artifact；当 `release=true` 时发布 GitHub Release。Release 内容必须包含：

- profile id 和 title
- platform tag
- source repo、branch、commit、commit date、commit subject
- profile hash
- workflow run link
- default IP 和检测来源
- root password state 和检测来源
- artifact 文件名和大小表
- Packages.tar.gz 内插件/包文件数量和清单

Release tag 格式：

```text
firmware-<profile>-<source>-<branch>-<commit>-run<run-number>
```

## Documentation

- [PRD](docs/firmware-ci-prd.md)
- [CI Workflow Architecture](docs/ci-workflow-architecture.md)
- [Codebase Notes](docs/codebase/)

## License

- [MIT](LICENSE)
