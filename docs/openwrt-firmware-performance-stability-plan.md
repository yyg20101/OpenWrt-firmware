# OpenWrt 固件性能与稳定性优化实施计划

## 1. 背景与目标

本文档用于沉淀后续 OpenWrt/ImmortalWrt 固件性能与稳定性优化的实施路线。目标不是替代现有 PRD 或 CI 架构说明，而是把已经确认的约束、当前基线、后续阶段任务和验收方式整理成可执行计划。

核心目标：

- 保证 `x86_64_LEDE`、`x86_64_immortalWrt` 优先稳定生成固件。
- 在不移除必要插件的前提下，通过配置分层、审计和运行时默认值提升固件性能。
- 降低上游源码、feeds、包 overlay、GitHub Actions Cache 和 runner 变化对构建稳定性的影响。
- 让每次优化都有可回溯证据：profile、源码 commit、配置审计、缓存命中、构建耗时、产物完整性。

## 2. 已确认约束

| 编号 | 约束 | 实施含义 |
|------|------|----------|
| CON-001 | profile 继续跟随上游分支。 | `devices/profiles.yml` 中的 `source_branch` 不做强制 pin；改为增加漂移报告与构建证据。 |
| CON-002 | 插件是必要能力，不能通过移除插件解决问题。 | 优化方向放在配置分层、依赖审计、编译并行度、缓存与产物验证。 |
| CON-003 | Samba4 和 autosamba 不需要共存。 | 保持 Samba4 优先，`autosamba` 必须禁用，并由配置审计阻止共存。 |
| CON-004 | x86 固件优先。 | 先保障 `x86_64_LEDE` 和 `x86_64_immortalWrt`，再扩展到 Qualcommax profile。 |
| CON-005 | GitHub Actions Cache 容量需要可控。 | 不用盲目扩大缓存；优先提高复用率、可观测性和清理边界。 |
| CON-006 | 优先使用官方 feeds、LuCI 和 uHTTPd 默认。 | 当前 profile 不覆盖 `feeds.conf.default`；本地只选择官方 LuCI 简体中文语言项，主题/uHTTPd/rpcd/LuCI runtime 由 LuCI 元包默认依赖提供并由审计确认。 |

## 3. 当前基线

当前仓库已经具备以下基础能力：

- `devices/profiles.yml` 是 profile 唯一入口，当前启用 5 个 profile。
- `scripts/common/config/network-performance.config` 启用 BBR、SQM、CAKE 和 IFB。
- `scripts/common/config/x86-performance.config` 启用 irqbalance、CPU microcode、x86 网卡与虚拟化驱动。
- `scripts/common/config/samba.config` 启用 Samba4，并显式禁用 `autosamba`。
- `scripts/common/config/luci-zh-cn.config` 只选择 `CONFIG_LUCI_LANG_zh_Hans=y`，让官方 LuCI 规则为已安装模块带出中文翻译包。
- `files/etc/uci-defaults/99-performance-defaults` 设置保守的运行时网络 sysctl 默认值。
- `scripts/ci/audit-config.sh` 已检查 x86 分区、GRUB、irqbalance、BBR/SQM/CAKE/IFB、LuCI/uHTTPd/rpcd、Samba4/autosamba 互斥和 VM 镜像裁剪要求。
- `.github/workflows/firmware-build.yml` 已包含缓存 restore/save、配置审计、依赖下载、编译 fallback、产物整理、Release 元数据。
- `.github/workflows/optimization-health.yml` 已能生成 profile、matrix 和缓存健康报告。
- `.github/workflows/cache-maintenance.yml` 已提供 dry-run 优先的缓存清理入口，并要求真实删除时指定 `prefix` 或 `ref`。

本计划基于以上能力继续推进，避免重复建设。

## 4. P0：稳定生成优先

P0 的目标是让固件是否能稳定生成变得可验证、可复盘。P0 完成前，不扩大 profile 数量，不新增大体量插件。

| 任务 | 范围 | 预期改动 | 验收标准 |
|------|------|----------|----------|
| P0-01 上游漂移报告 | `devices/profiles.yml`、`scripts/ci/optimization-report.sh`、`.github/workflows/optimization-health.yml` | 在健康报告中列出每个 profile 的 `source_repo`、`source_branch`、当前远端 HEAD、最近构建使用的 source commit。 | 手动运行 Optimization Health 可以看到 profile 是否跟上游发生漂移；报告不触发构建、不修改缓存。 |
| P0-02 x86 QEMU smoke | `scripts/ci/build-artifacts.sh` 或新增 `scripts/ci/smoke-x86.sh`、`.github/workflows/firmware-build.yml` | 对 x86 `combined.img.gz` 或 `combined-efi.img.gz` 做轻量启动验证，至少确认镜像可解压、分区可识别、启动流程进入 OpenWrt 早期日志。 | x86 构建成功后上传 smoke 日志；失败时构建失败并保留诊断 artifact。 |
| P0-03 构建失败定位增强 | `scripts/ci/build-artifacts.sh` | 在失败上下文中记录失败包、最后 300 行日志、磁盘空间、内存、ccache 状态、OpenWrt target 信息。 | 编译失败 artifact 中能直接定位失败包或确认失败发生在工具链/下载/磁盘阶段。 |
| P0-04 x86 配置守护补强 | `scripts/ci/audit-config.sh`、`scripts/ci/test-config-audit.sh` | 继续扩大 x86 effective config 审计，关注 rootfs 空间、EFI/legacy 启动、关键网卡、virtio、microcode、Samba4/autosamba 互斥。 | 本地 fixture 测试覆盖新增审计规则；x86 profile defconfig 后仍通过审计。 |

P0 推荐执行顺序：

1. 先做 P0-01，因为它不会影响构建路径。
2. 再做 P0-03，提高失败时的信息密度。
3. 然后做 P0-04，把已确认的 x86 必备能力固化到审计。
4. 最后做 P0-02，避免 smoke 误报影响现有构建成功率。

## 5. P1：编译加速与配置性能分层

P1 的目标是缩短构建反馈周期，并把性能配置从“启用了一批包”升级为“可解释、可验证、可按设备族调整”。

| 任务 | 范围 | 预期改动 | 验收标准 |
|------|------|----------|----------|
| P1-01 缓存命中与耗时报告 | `.github/workflows/firmware-build.yml`、`scripts/ci/optimization-report.sh` | 记录 ccache/build-accel 是否精确命中、matched key、缓存保存条件、下载耗时、编译耗时、产物整理耗时。 | 每次构建 summary 能看到命中状态和阶段耗时；Optimization Health 能汇总缓存体积和最近访问时间。 |
| P1-02 cache key 分组策略复核 | `devices/profiles.yml`、`.github/workflows/firmware-build.yml` | 保持 key 由 source slug、branch、cache group、monthly cache period 构成；restore 使用同 source/branch/group 的前缀 fallback；save 仅在 `cache-matched-key` 为空时执行。 | x86 两个 profile 不因不同源码混用工具链缓存；Qualcommax profile 按 source/branch 形成隔离；命中 fallback 时不会额外保存重复 cache。 |
| P1-03 编译并行度策略 | `devices/profiles.yml`、`scripts/ci/build-artifacts.sh` | 按 profile 设置 `make_compile_jobs`，对内存敏感源码保持保守值，对稳定源码允许使用 runner CPU 数。 | 构建日志明确显示实际 jobs、runner cores、profile limit；失败 fallback 到 `-j1` 后仍保留完整日志。 |
| P1-04 性能配置分层 | `scripts/common/config/*.config`、`devices/profiles.yml` | 保持基础插件不移除；把网络性能、存储、x86 硬件、代理、Samba 等能力按片段保持清晰边界。 | 新增或调整 profile 时能通过 `config_fragments` 看出性能能力来源；低存储目标可评估是否需要独立 profile，而不是删插件。 |
| P1-05 运行时默认值审计 | `files/etc/uci-defaults/99-performance-defaults`、`scripts/ci/audit-config.sh` | 确保 sysctl 默认值保守，不强制启用会破坏用户网络的激进参数；审计 overlay 必须存在。 | 配置审计缺少 overlay 时失败；默认值说明清晰，可在产物 config-audit 中追溯。 |
| P1-06 LuCI 官方默认审计 | `scripts/common/config/luci-zh-cn.config`、`scripts/ci/audit-config.sh` | 不手写每个插件中文包或 LuCI runtime/lib 依赖；只选择官方 `CONFIG_LUCI_LANG_zh_Hans=y`，并让 `luci`/`luci-light` 默认带主题、uHTTPd 和 rpcd 依赖。 | defconfig 后审计看到 `luci-base`、`luci-i18n-base-zh-cn`、uHTTPd、uHTTPd ubus、rpcd LuCI 和至少一个 LuCI 主题。 |

## 6. P2：供应链与长期稳定性

P2 的目标是降低“本地无改动但构建结果变化”的风险，同时不破坏 profile 跟随上游的约束。

| 任务 | 范围 | 预期改动 | 验收标准 |
|------|------|----------|----------|
| P2-01 包 overlay 风险清单 | `scripts/common/Packages.sh`、Release metadata | 记录每个 overlay 仓库的 ref、commit、来源和失败重试次数。 | Release 或 artifact 中能看到包 overlay 来源；失败时可以判断是上游包变化还是本地配置问题。 |
| P2-02 远程脚本风险跟踪 | `.github/workflows/firmware-build.yml`、文档 | 对 build environment 远程脚本记录下载 URL、下载时间，后续评估 checksum 或固定版本。 | 构建日志能说明 runner 初始化脚本来源；安全风险在文档中可见。 |
| P2-03 Release/Artifact 合规检查 | `scripts/ci/optimization-report.sh`、`scripts/ci/build-artifacts.sh` | 持续检查 `Packages.tar.gz` 必须保留、VM 专用镜像必须裁剪、x86 raw 压缩镜像必须存在。 | `optimization-report.sh release <repo> <tag>` 能验证 Release 资产是否符合规则。 |
| P2-04 维护策略固化 | `docs/ci-workflow-architecture.md`、`README.md`、本计划文档 | 把 cache maintenance、release maintenance、profile 修改流程写成固定运维节奏。 | 新增 profile 或触发全量构建前，有明确的健康报告、构建、清理 dry-run 顺序。 |
| P2-05 PassWall 官方 tag 覆盖 | `scripts/common/Packages.sh`、`scripts/common/package` | 清理本地/feeds 冲突目录；依赖包仓按官方 `main` 刷新，`luci-app-passwall` 主仓强制拉取最新官方 tag。 | `validate-passwall-overlay.sh` 通过；包来源 manifest 记录官方仓库、ref 和 commit。 |

## 7. 验证计划

每次实施优化后，至少执行以下本地验证：

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/sync-workflow-target-options.sh "$PWD"
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-luci-zh-cn-config.sh
bash scripts/ci/validate-passwall-overlay.sh
bash scripts/ci/validate-dependabot-coverage.sh
bash scripts/ci/optimization-report.sh summary "$PWD"
```

涉及审计脚本时，补充执行：

```bash
bash scripts/ci/test-config-audit.sh
bash scripts/ci/test-optimization-report.sh
bash scripts/ci/validate-cache-maintenance.sh
```

涉及 artifact 或 Release 逻辑时，补充执行：

```bash
bash scripts/ci/test-artifacts-release.sh
bash scripts/ci/validate-release-maintenance.sh
```

GitHub Actions 侧建议顺序：

1. 运行 `Optimization Health`，确认 profile、matrix、cache 报告正常。
2. 触发 `Firmware CI` 的 `target=x86_64_all`，先验证两个 x86 profile。
3. x86 稳定后再触发 `target=qualcommax_all`。
4. 全部通过后再触发 `target=all`，并按需设置 `release=true`。
5. 如 cache 接近容量上限，先运行 `Cache Maintenance` dry-run，再按 `prefix` 或 `ref` 做真实清理。

## 8. 风险与假设

| 风险 | 影响 | 缓解方式 |
|------|------|----------|
| 上游源码和 feeds 跟随分支变化。 | 同一 profile 在不同时间构建结果不同。 | 保持 source commit、profile hash、包 overlay manifest 和漂移报告。 |
| 插件体积持续增长。 | rootfs 可能逼近容量上限，尤其是 x86 以外目标。 | 不删必要插件；通过 rootfs 分区、配置分层和产物体积报告管理。 |
| QEMU smoke 误报。 | 可能阻塞本来可用的固件产物。 | 先作为 x86 artifact 日志上传，稳定后再升级为强制 gate。 |
| Cache 清理过度。 | 下次构建变慢，甚至重新编译工具链。 | 真实删除必须使用 `prefix` 或 `ref`，并保留匹配范围内最新缓存。 |
| runner 镜像或远程初始化脚本变化。 | 构建环境不可预测。 | 记录 runner、脚本来源和初始化日志，后续评估 checksum 或固定版本。 |

## 9. 完成定义

本计划视为完成实施时，需要满足：

- x86 两个 profile 在 GitHub Actions 中可以稳定生成 artifact。
- 每次构建有可读的配置审计、缓存命中、阶段耗时和失败上下文。
- Samba4 与 autosamba 互斥由配置片段和审计共同保证。
- 必要插件未被移除，性能配置来源可以从 `config_fragments` 追溯。
- Cache 总量、命中情况和清理候选可以从健康报告中判断。
- Release/Artifact 资产保留 `Packages.tar.gz`，并排除 VM 专用镜像格式。

## 10. 相关文件

- `README.md`
- `docs/firmware-ci-prd.md`
- `docs/ci-workflow-architecture.md`
- `docs/codebase/ARCHITECTURE.md`
- `docs/codebase/CONCERNS.md`
- `devices/profiles.yml`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `.github/workflows/optimization-health.yml`
- `.github/workflows/cache-maintenance.yml`
- `scripts/ci/audit-config.sh`
- `scripts/ci/build-artifacts.sh`
- `scripts/ci/optimization-report.sh`
- `scripts/common/config/network-performance.config`
- `scripts/common/config/x86-performance.config`
- `scripts/common/config/samba.config`
- `files/etc/uci-defaults/99-performance-defaults`
