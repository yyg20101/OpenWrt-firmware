# OpenWrt Firmware CI

这个仓库用于通过 GitHub Actions 构建多设备 OpenWrt/ImmortalWrt 固件。当前架构已重构为“声明式设备配置 + 动态构建矩阵 + 标准化 Release”的固件 CI 系统。

## Workflows

- `Firmware CI`
  - 文件：`.github/workflows/firmware-ci.yml`
  - 手动触发参数：
    - `target`: 下拉选择单个 profile、`x86_64_all`、`qualcommax_all` 或 `all`
    - `release`: 是否发布 GitHub Release，默认不发布
  - 事件触发：`repository_dispatch`，事件类型为 `firmware-ci`
  - 只有单 profile 发布会标记为 GitHub Latest；分组或 `all` 发布不会覆盖 Latest 标记。

- `Firmware Build`
  - 文件：`.github/workflows/firmware-build.yml`
  - 可复用构建实现，负责环境初始化、源码克隆、缓存、配置、feeds、编译、产物整理、默认访问检测、Artifact 和 Release。

- `Cache Maintenance`
  - 文件：`.github/workflows/cache-maintenance.yml`
  - 手动清理 GitHub Actions Cache，默认 dry-run 并保留匹配范围内最新 2 个缓存。
  - 真实删除时必须指定 `prefix` 或 `ref`，避免误删全部缓存。

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
  make_compile_jobs: 2
  groups:
    - my_group
  config: devices/my_profile/.config
  config_fragments:
    - scripts/common/config/<platform>.config
```

通用固件能力由多个 `scripts/common/config/*.config` 片段组合：

- `base.config`：基础 LuCI 应用、核心工具、网络与隧道支持
- `network-performance.config`：BBR、SQM/CAKE、IFB 等网络吞吐和低延迟队列能力
- `storage.config`：磁盘、文件系统、NVMe/SATA/NFS 支持
- `usb-mobile.config`：USB 外设、USB 网卡、移动网络支持
- `proxy.config`：DNS/代理相关共享包
- `samba.config`：Samba4 文件共享栈，并显式禁用 autosamba

平台、源码系、设备族和性能优化差异继续通过 profile 的 `config_fragments` 追加，例如 `x86.config`、`x86-performance.config`、`qualcommax-ipq60xx.config`、`lede-extra.config`。x86 性能片段同时启用 Intel/AMD microcode，降低 CPU errata 和虚拟化/软路由场景下的稳定性风险。

`make_compile_jobs` 是可选项。缺省时构建会使用 runner CPU 数；当某个上游源码或 profile 在 GitHub hosted runner 上容易因为内存压力失败时，为该 profile 设置较小的正整数。当前 `x86_64_immortalWrt` 使用 `make_compile_jobs: 2`，`x86_64_LEDE` 保持自动并行。

3. 运行本地校验：

```bash
bash scripts/ci/sync-workflow-target-options.sh "$PWD"
bash scripts/ci/validate-profiles.sh
bash scripts/ci/profiles.sh target-options "" "" "$PWD"
bash scripts/ci/profiles.sh matrix all "" "$PWD"
bash scripts/ci/profiles.sh matrix x86_64_all "" "$PWD"
```

## Local Validation

提交前建议运行：

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/sync-workflow-target-options.sh "$PWD"
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
```

## Operations Order

优化或全量构建前建议按以下顺序执行：

1. 手动运行 `Optimization Health`，确认 profile、上游漂移、matrix 和 cache 分组状态。
2. 先触发 `Firmware CI` 的 `target=x86_64_all`，确认两个 x86 profile 生成 artifact 并通过 x86 smoke。
3. x86 稳定后再触发 `target=qualcommax_all` 或 `target=all`。
4. Cache 接近容量上限时，先运行 `Cache Maintenance` dry-run；真实删除必须指定 `prefix` 或 `ref`，并保留匹配范围内最新缓存。
5. 需要发布固件时，对单个 profile 使用 `release=true`；分组或 `all` 发布不会抢占 GitHub Latest。

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

单 profile 发布会被标记为 GitHub Latest；分组或 `all` 发布会创建独立 Release，但不会让最后完成的 profile 抢占 Latest。

## Documentation

- [PRD](docs/firmware-ci-prd.md)
- [CI Workflow Architecture](docs/ci-workflow-architecture.md)
- [Codebase Notes](docs/codebase/)

## License

- [MIT](LICENSE)
