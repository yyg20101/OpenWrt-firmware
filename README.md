# OpenWrt Firmware Build (GitHub Actions)

这个仓库用于构建多设备 OpenWrt/ImmortalWrt 固件，并通过 GitHub Actions 自动化完成：

- 设备参数解析
- 源码拉取、feeds 与自定义脚本处理
- 编译与产物整理
- Release 发布与清理
- CI Lint 与 Dependabot 依赖升级检测

## Workflows

- `OpenWrt Builder`
  - 支持手动触发：`workflow_dispatch`
  - 支持事件触发：`repository_dispatch`（`source-code-update`）
  - `build_all=true` 时并行构建全部设备

- `Update Checker`
  - 对比上游源码 commit
  - 包含自动触发开关 `auto_trigger_build`（默认 `false`）
  - 仅当检测到更新且开关开启时，才触发构建

- `CI Lint`
  - workflow YAML 校验
  - shell 语法校验
  - 设备 `env` 规则校验
  - Dependabot 覆盖检测（npm/pip/docker 清单与配置一致性）

## Device Profiles

设备配置位于 `devices/<model>/`，当前支持：

- `x86_64_LEDE`
- `x86_64_immortalWrt`
- `Qualcommax_LEDE`
- `Qualcommax_V`
- `Qualcommax_B`

常见文件：

- `.config`
- `env`
- `diy-part1.sh` / `diy-part2.sh`（可选）
- `package`（可选）

## CI Scripts

CI 逻辑已拆分到 `scripts/ci/`，便于维护与复用。完整说明见：

- [CI Workflow Architecture](/Users/wajie/PycharmProjects/OpenWrt-firmware/docs/ci-workflow-architecture.md)

共享构建资产默认位于 `scripts/common/`（如 `Driver.config`、`General.sh`、`Packages.sh`、`diy-part*.sh`），并可通过 workflow env 覆盖：
- `DRIVER_CONFIG_PATH` / `DRIVER_CONFIG_GLOB`
- `GENERAL_SCRIPT_PATH`
- `PACKAGE_BASE_SCRIPT_PATH`

## Dependabot

已启用 Dependabot（`github-actions` 生态）：

- 配置文件：`.github/dependabot.yml`
- 调度：每周一（Asia/Shanghai）

当仓库新增 npm/pip/docker 清单但未配置对应 Dependabot 生态时，`CI Lint` 会失败并给出提示。

## License

- [MIT](/Users/wajie/PycharmProjects/OpenWrt-firmware/LICENSE)
