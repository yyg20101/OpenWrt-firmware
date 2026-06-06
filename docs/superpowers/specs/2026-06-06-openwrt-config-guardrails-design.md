# OpenWrt Config Guardrails PRD

## 1. Executive Summary

**Problem Statement**: The firmware must keep user-required plugins and LuCI web access stable while following upstream OpenWrt/ImmortalWrt defaults wherever they are sufficient. Over-configuring LuCI runtime details or relying blindly on upstream defaults for known conflicts can create build drift, missing web UI components, or Samba integration conflicts.

**Proposed Solution**: Adopt Strategy A: keep explicit guardrails only where they protect required behavior, and otherwise use upstream feed and LuCI collection defaults. Specifically, keep Samba4 enabled and `autosamba` explicitly disabled, preserve required plugins through shared or source-specific config fragments, keep OpenVPN in LEDE-only config, keep only `CONFIG_PACKAGE_luci=y` and `CONFIG_LUCI_LANG_zh_Hans=y` for LuCI, pull PassWall from the official PassWall overlay for all supported source trees, and verify the expanded defconfig result through CI.

**Success Criteria**:

- All enabled profiles keep every currently selected required plugin from `devices/*.config` and `scripts/common/config/*.config`.
- If Samba4 is enabled, `CONFIG_PACKAGE_autosamba` must not be enabled in requested or effective config.
- Requested LuCI application packages must not disappear after `make defconfig`; `config-audit/missing-luci-apps.txt` must be empty.
- x86 config-audit artifacts show LuCI web availability: `luci-base`, at least one LuCI theme, `uHTTPd`, `uHTTPd ubus`, and `rpcd-mod-luci`.
- x86 config-audit artifacts show Simplified Chinese support through `CONFIG_LUCI_LANG_zh_Hans=y` and `luci-i18n-base-zh-cn`.
- `Firmware CI` with `target=x86_64_all` produces firmware artifacts whose checksums pass and whose smoke reports show `Static checks: passed`.

## 2. User Experience & Functionality

**User Personas**:

- **Firmware owner**: Maintains a personal OpenWrt firmware with a known plugin set and expects builds to remain reproducible enough to debug.
- **Router administrator**: Flashes the firmware and expects LuCI web access, theme assets, Chinese language support, Samba4, proxy plugins, storage tools, and networking plugins to be available after boot.
- **CI maintainer**: Uses GitHub Actions artifacts and config-audit summaries to detect plugin loss, LuCI dependency drift, and Samba/autosamba conflicts before release.

**User Stories**:

- As the firmware owner, I want all currently configured plugins to be treated as required so that optimization work does not silently remove personal functionality.
- As the router administrator, I want the LuCI web interface, theme, uHTTPd bridge, rpcd LuCI module, and Simplified Chinese support to exist so that the firmware is manageable from the browser.
- As the firmware owner, I want Samba4 to be present without autosamba so that file sharing does not depend on conflicting block hotplug behavior.
- As the CI maintainer, I want official upstream defaults to provide LuCI internals where possible so that local config does not fight source-specific feed behavior.
- As the firmware owner, I want source-specific plugins such as OpenVPN to remain in their matching source fragment so that each firmware keeps its upstream character instead of forcing every profile into the same package set.

**Acceptance Criteria**:

- All enabled profiles in `devices/profiles.yml` include `scripts/common/config/base.config`, `scripts/common/config/luci-zh-cn.config`, and `scripts/common/config/samba.config`.
- `scripts/common/config/base.config` keeps `CONFIG_PACKAGE_luci=y` and does not hard-code LuCI runtime, uHTTPd, rpcd, theme, or per-plugin i18n package selections.
- `scripts/common/config/luci-zh-cn.config` contains only the official language selector `CONFIG_LUCI_LANG_zh_Hans=y` plus comments explaining the upstream LuCI language mechanism.
- `scripts/common/config/samba.config` keeps `CONFIG_PACKAGE_luci-app-samba4=y` and `# CONFIG_PACKAGE_autosamba is not set`.
- Current required third-party and LuCI application selections in `scripts/common/config/base.config`, `scripts/common/config/proxy.config`, `scripts/common/config/storage.config`, `scripts/common/config/usb-mobile.config`, and platform fragments remain present unless the user explicitly approves a later removal.
- `scripts/common/config/lede-extra.config` contains LEDE-oriented selections, including `luci-app-openvpn`; non-LEDE fragments do not request OpenVPN.
- `scripts/common/package` overlays required third-party apps that are not reliably available from active official feeds, and applies the official PassWall dependency/app repositories to all supported source trees.
- `scripts/ci/audit-config.sh` fails when requested LuCI application packages are removed by defconfig, or when LuCI web dependencies, LuCI Chinese, Samba4/autosamba policy, or required performance guardrails are missing from effective config.
- `scripts/ci/validate-plugin-overlay.sh` fails when shared third-party overlay packages, LEDE-only package placement, or profile fragment boundaries drift.
- The latest accepted x86 proof is `Firmware CI` run `27050273854` on commit `7a21daeddc8aa0391e7703473708b5f661e56296`, with artifacts downloaded to `/private/tmp/openwrt-artifacts-27050273854`.

**Non-Goals**:

- Do not pin upstream source branches to fixed commits.
- Do not make `autosamba` follow upstream defaults while Samba4 is required.
- Do not hard-code every LuCI translation package or web runtime dependency in local config.
- Do not remove currently enabled plugins to reduce image size, compile time, or cache use.
- Do not force LEDE-only plugins such as OpenVPN into non-LEDE profiles.
- Do not change runtime LuCI language defaults beyond selecting the official Simplified Chinese language build option.

## 3. AI System Requirements

**Tool Requirements**:

- Local repository inspection with `rg`, `git status`, and targeted file reads.
- Local validators: `validate-profiles.sh`, `validate-luci-zh-cn-config.sh`, `validate-passwall-overlay.sh`, `validate-plugin-overlay.sh`, `test-config-audit.sh`, `test-config-feeds.sh`, `test-artifacts-release.sh`, `test-smoke-x86.sh`, `validate-cache-key-policy.sh`, `validate-cache-maintenance.sh`, `test-optimization-report.sh`, and `validate-release-maintenance.sh`.
- GitHub CLI access for `Firmware CI` run inspection, artifact inventory, and artifact download.
- Artifact-level verification using `shasum -a 256 -c sha256sums.txt` and smoke/config-audit summaries.

**Evaluation Strategy**:

- Treat current worktree files and downloaded CI artifacts as authoritative evidence.
- Verify requested config and effective config separately: requested config proves local intent, effective config proves upstream/default dependency expansion.
- Prefer upstream defaults when the effective config proves the needed LuCI component exists.
- Treat missing or indirect evidence as incomplete; rerun local validators or inspect artifacts before marking the requirement satisfied.

## 4. Technical Specifications

**Architecture Overview**:

Configuration is layered through `devices/profiles.yml`. Each enabled profile points to a device config and shared config fragments. The shared fragments choose required user-facing capabilities, while upstream feeds and OpenWrt defconfig resolve package dependencies.

Data flow:

1. `devices/profiles.yml` selects source repo, upstream-following source branch, cache group, device config, and config fragments.
2. `scripts/ci/config-feeds.sh` applies source defaults, config fragments, files overlay, and package overlay.
3. OpenWrt defconfig expands official package dependencies.
4. `scripts/ci/audit-config.sh` inspects the effective config and writes config-audit artifacts.
5. `scripts/ci/build-artifacts.sh` compiles firmware and writes manifests, provenance, size reports, and checksums.
6. `scripts/ci/smoke-x86.sh` validates x86 image integrity and early boot evidence.

**Integration Points**:

- `scripts/common/config/base.config`: required LuCI application and core package selections, including `CONFIG_PACKAGE_luci=y`.
- `scripts/common/config/lede-extra.config`: LEDE-only plugin selections such as OpenVPN and other LEDE-oriented LuCI apps.
- `scripts/common/config/luci-zh-cn.config`: official Simplified Chinese language selector.
- `scripts/common/config/samba.config`: Samba4/autosamba policy.
- `scripts/common/config/proxy.config` and `scripts/common/package`: proxy plugin selections and PassWall overlay source policy.
- `scripts/ci/audit-config.sh`: requested/effective config validation for LuCI apps, LuCI web, Samba4/autosamba, and performance guardrails.
- `scripts/ci/validate-plugin-overlay.sh`: static guardrail for third-party plugin overlay sources and source-specific plugin placement.
- `.github/workflows/firmware-ci.yml` and `.github/workflows/firmware-build.yml`: remote build and artifact proof.

**Security & Privacy**:

- Do not add secrets or credentials to config fragments, documentation, or artifact manifests.
- Package overlay provenance must identify repositories, refs, tags, and commits, but not expose tokens.
- Cache maintenance remains dry-run-first; real deletion requires explicit user approval and a concrete `ref` or `prefix`.

## 5. Risks & Roadmap

**Phased Rollout**:

- **MVP**: Keep Strategy A as the documented policy; preserve current config behavior and x86 proof.
- **v1.1**: Add or extend local validators if future edits make plugin preservation or LuCI dependency checks too implicit.
- **v2.0**: Expand the same artifact-level proof to `qualcommax_all` after x86 remains stable.

**Technical Risks**:

- Upstream LuCI dependency chains can change. Mitigation: keep local config minimal and audit effective config after defconfig.
- Upstream feeds may reintroduce autosamba through dependencies. Mitigation: keep explicit disable and effective config audit.
- Required plugin growth can increase rootfs pressure. Mitigation: use firmware size reports and profile-specific tuning instead of removing plugins.
- GitHub artifact download can fail due to transient network EOF. Mitigation: rely on remote run conclusion for build status and use retried/resumable downloads for local checksum proof.

## Strategy A Design Decision

The approved policy is **stable guardrails plus official dependency defaults**.

| Area | Local Policy | Validation |
|------|--------------|------------|
| `autosamba` | Keep explicit disable because Samba4 is required and coexistence is not desired. | Requested config contains `# CONFIG_PACKAGE_autosamba is not set`; effective config summary reports `autosamba: n`. |
| Samba4 | Keep `CONFIG_PACKAGE_luci-app-samba4=y`. | Requested and effective config report Samba4 enabled. |
| Required plugins | Treat current enabled config selections as required, while respecting source-specific fragments. | Static profile audit, plugin overlay validator, and config-audit artifacts must not lose selected packages. |
| Source-specific plugins | Keep OpenVPN and LEDE-oriented selections in `lede-extra.config`; do not request them from non-LEDE profiles. | `validate-plugin-overlay.sh` enforces fragment placement and profile boundaries. |
| LuCI web | Keep only `CONFIG_PACKAGE_luci=y` locally. | Effective config must include `luci-base`, theme, `uhttpd`, `uhttpd-mod-ubus`, and `rpcd-mod-luci`. |
| LuCI Chinese | Keep only `CONFIG_LUCI_LANG_zh_Hans=y` locally. | Effective config must include `luci-i18n-base-zh-cn`. |
| Theme | Do not hard-code a theme if official LuCI collection provides one. | Effective config must include at least one `CONFIG_PACKAGE_luci-theme-*=y`; current x86 proof shows `luci-theme-bootstrap`. |

## Current Evidence

- `devices/profiles.yml` has 5 enabled profiles and all keep upstream-following `source_branch` values.
- `scripts/common/config/samba.config` currently enables Samba4 and disables autosamba.
- `scripts/common/config/base.config` currently includes `CONFIG_PACKAGE_luci=y` and shared required LuCI applications such as PassWall, HomeProxy, ZeroTier, Alist, Docker/Dockerman, Diskman, DDNS-Go, UPnP, WireGuard, and related support packages.
- `scripts/common/config/lede-extra.config` keeps LEDE-oriented applications, including OpenVPN, separate from non-LEDE profiles.
- `scripts/common/package` now overlays required third-party packages from verified GitHub repositories and keeps the official PassWall package/app overlay for all supported source trees.
- `scripts/common/config/luci-zh-cn.config` currently selects `CONFIG_LUCI_LANG_zh_Hans=y`.
- `Firmware CI` run `27050273854` completed successfully for `x86_64_LEDE` and `x86_64_immortalWrt`.
- Downloaded config-audit summaries for both x86 profiles confirm LuCI meta, LuCI Chinese, LuCI base zh-cn, Bootstrap theme, uHTTPd, uHTTPd ubus, rpcd LuCI, Samba4, autosamba disabled, WireGuard, BBR, SQM, and CAKE.
- Downloaded firmware artifacts for both x86 profiles passed `shasum -a 256 -c sha256sums.txt`.
- A stricter requested-vs-effective audit after run `27050273854` found several requested LuCI apps were dropped by defconfig; the current implementation adds overlay sources and audit checks so the next x86 run must prove they remain present.

## Review Checklist

- No placeholder requirements remain.
- Strategy A is the only approved strategy in scope.
- The document separates local intent from effective defconfig proof.
- The document does not authorize plugin removal.
- The document does not authorize replacing official LuCI dependency defaults with local hard-coding.
- The document keeps source-specific plugins source-specific instead of forcing every profile to request LEDE-only applications.
