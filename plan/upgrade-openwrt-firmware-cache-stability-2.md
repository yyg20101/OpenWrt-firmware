---
goal: OpenWrt firmware cache reuse, build performance, and stability hardening
version: 2.0
date_created: 2026-06-02
last_updated: 2026-06-06
owner: wajie
status: In progress
tags:
  - openwrt
  - firmware
  - ci
  - performance
  - stability
  - cache
  - github-actions
---

# Introduction

![Status: In progress](https://img.shields.io/badge/status-In%20progress-yellow)

This implementation plan defines the next optimization pass after `plan/upgrade-openwrt-firmware-performance-stability-1.md`. The goal is to keep OpenWrt/ImmortalWrt firmware builds stable and fast while reducing GitHub Actions cache churn caused by branch, version, and date-based cache keys.

This plan preserves upstream-following profiles, keeps all user-required plugins, keeps Samba4 as the file sharing baseline, and prevents `autosamba` from coexisting with Samba4. The implementation must prove the x86 path first, then expand the same guardrails to Qualcommax and all-profile builds.

## 1. Requirements & Constraints

- **REQ-001**: `devices/profiles.yml` must keep profile `source_branch` values following upstream branches. Do not pin profile sources to local commits or fixed upstream SHAs.
- **REQ-002**: User-required plugins must remain enabled. Build success must not be achieved by removing required packages.
- **REQ-003**: Samba4 is the preferred file sharing baseline. `scripts/common/config/samba.config` must keep `CONFIG_PACKAGE_autosamba` disabled, and `scripts/ci/audit-config.sh` must continue to fail when Samba4 and autosamba coexist.
- **REQ-004**: Cache reuse must remain isolated by cache type, cache version, source repository slug, source branch, and `cache_group`. No cache key may cross source repository, source branch, or cache group boundaries.
- **REQ-005**: Cache optimization must reduce redundant period-based cache creation. A restored fallback cache must not cause a new cache to be saved only because the primary key period changed.
- **REQ-006**: Cache cleanup must remain dry-run-first. Real GitHub Actions cache deletion requires explicit user approval plus a concrete `ref` or `prefix` filter.
- **REQ-007**: The x86 profiles `x86_64_LEDE` and `x86_64_immortalWrt` remain the first proof targets before `qualcommax_all` or `all`.
- **REQ-008**: Successful firmware artifacts must continue to include `build.config`, `artifact-manifest.txt`, `firmware-size-report.md`, `build-environment-provenance.md`, `Packages.tar.gz`, firmware images, and `sha256sums.txt`.
- **REQ-009**: Failed builds must continue to upload compile logs and failure-context artifacts with failed package hints, disk state, memory state, ccache state, and OpenWrt target metadata.
- **REQ-010**: The implementation branch may be merged into `main` only after local validators pass, x86 GitHub Actions evidence is recorded, and cache maintenance dry-run behavior is verified.
- **REQ-011**: After a successful merge to `main`, obsolete local and remote implementation branches must be deleted and the final branch state must be audited.
- **REQ-012**: Current profiles must preserve upstream `feeds.conf.default` and use the official LuCI feed declared by each source tree unless a future profile explicitly documents a local feeds override.
- **REQ-013**: LuCI Simplified Chinese support must use the official LuCI language option and feed-provided i18n package defaults. Do not hard-code per-plugin translation packages in local config.
- **REQ-014**: LuCI theme, uHTTPd, and rpcd defaults should come from the official LuCI collection dependencies and package post-install behavior, with local audit verifying the defconfig result instead of replacing those defaults.
- **REQ-015**: PassWall must clean local/feed conflicts and pull `Openwrt-Passwall/openwrt-passwall` from the latest upstream tag for supported source trees.
- **SEC-001**: Workflow changes must not add new secrets, broaden token permissions beyond the existing need, or hide remote script and package overlay provenance.
- **CON-001**: Changes must stay compatible with the existing workflow split: `.github/workflows/firmware-ci.yml`, `.github/workflows/firmware-build.yml`, `.github/workflows/optimization-health.yml`, `.github/workflows/cache-maintenance.yml`, `.github/workflows/release-maintenance.yml`, and `.github/workflows/ci-lint.yml`.
- **CON-002**: `devices/profiles.yml` remains the single source of truth for profile matrix membership, source repository, source branch, config path, cache group, compile limits, and config fragments.
- **CON-003**: GitHub Actions cache entries are immutable after save. The cache strategy must account for immutable cache keys instead of assuming a stable key can be overwritten.
- **CON-004**: Live cache deletion is outside this implementation unless the user explicitly approves a deletion operation after reviewing dry-run output.
- **GUD-001**: Keep OpenWrt configuration split into base, network performance, storage, USB/mobile, proxy, Samba, x86, x86 performance, and platform-specific fragments.
- **GUD-002**: Prefer workflow policy validation in `scripts/ci/` so cache behavior regressions are caught by `ci-lint.yml`.
- **GUD-003**: Prefer upstream OpenWrt/ImmortalWrt/LuCI defaults when they already provide the needed behavior; add local config only to select required capabilities or audit their expanded results.
- **PAT-001**: Use explicit local validators before triggering expensive firmware builds.
- **PAT-002**: Record run IDs, commit SHAs, artifact checks, and cache dry-run results in this plan before marking it `Completed`.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Capture the current cache failure mode and preserve the implementation plan as the execution source of truth.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Confirm the current branch and worktree state with `git status --short --branch` and `git branch --show-current` before implementation. Expected branch: `codex/cache-stability-optimization`. | ✅ | 2026-06-02 |
| TASK-002 | Record the cache failure mode in this plan: `.github/workflows/firmware-build.yml` uses weekly `CACHE_WEEK` primary keys and saves a new cache when `cache-hit != 'true'`, even when `cache-matched-key` restored a fallback cache. | ✅ | 2026-06-02 |
| TASK-003 | Keep `plan/upgrade-openwrt-firmware-performance-stability-1.md` unchanged as completed historical evidence and create this v2 plan for the new cache stability implementation. | ✅ | 2026-06-02 |

### Implementation Phase 2

- GOAL-002: Reduce cache key churn while keeping source, branch, and cache group isolation.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-004 | In `.github/workflows/firmware-build.yml`, replace the source step variable `cache_week="$(date +%Y-%W)"` with `cache_period="$(date +%Y-%m)"`. Export `CACHE_PERIOD` to `GITHUB_ENV` and `cache_period` to `GITHUB_OUTPUT`. | ✅ | 2026-06-03 |
| TASK-005 | In `.github/workflows/firmware-build.yml`, update ccache primary keys from `ccache-v2-${source_slug}-${repo_branch}-${ccache_group}-${cache_week}` to `ccache-v2-${source_slug}-${repo_branch}-${ccache_group}-${cache_period}`. Keep restore prefix `ccache-v2-${source_slug}-${repo_branch}-${ccache_group}-`. | ✅ | 2026-06-03 |
| TASK-006 | In `.github/workflows/firmware-build.yml`, update build accelerator primary keys from `build-accel-v2-${source_slug}-${repo_branch}-${ccache_group}-${cache_week}` to `build-accel-v2-${source_slug}-${repo_branch}-${ccache_group}-${cache_period}`. Keep restore prefix `build-accel-v2-${source_slug}-${repo_branch}-${ccache_group}-`. | ✅ | 2026-06-03 |
| TASK-007 | In `.github/workflows/firmware-build.yml`, change `Save ccache` to run only when compile succeeds on `refs/heads/main` and `steps.cache-ccache.outputs.cache-matched-key == ''`. Do not use `steps.cache-ccache.outputs.cache-hit != 'true'` as the save condition. | ✅ | 2026-06-03 |
| TASK-008 | In `.github/workflows/firmware-build.yml`, change `Save Build Accelerator Cache` to run only when compile succeeds on `refs/heads/main` and `steps.cache-build-accel.outputs.cache-matched-key == ''`. Do not use `steps.cache-build-accel.outputs.cache-hit != 'true'` as the save condition. | ✅ | 2026-06-03 |
| TASK-009 | Extend the `Show Cache Status` step in `.github/workflows/firmware-build.yml` to print the cache period and the save policy: `save only when no matched cache key exists`. | ✅ | 2026-06-03 |

### Implementation Phase 3

- GOAL-003: Add automated guardrails so future edits cannot reintroduce redundant cache saving.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-010 | Add `scripts/ci/validate-cache-key-policy.sh` to validate `.github/workflows/firmware-build.yml` contains `CACHE_PERIOD` and `cache_period`, does not contain `CACHE_WEEK` or `cache_week`, and keeps cache keys isolated by source slug, repo branch, and cache group. | ✅ | 2026-06-03 |
| TASK-011 | In `scripts/ci/validate-cache-key-policy.sh`, fail if either save step uses `cache-hit != 'true'` and fail unless both save conditions use `cache-matched-key == ''`. | ✅ | 2026-06-03 |
| TASK-012 | Add a `Validate Cache Key Policy` step to `.github/workflows/ci-lint.yml` that runs `bash scripts/ci/validate-cache-key-policy.sh`. | ✅ | 2026-06-03 |
| TASK-013 | Update `scripts/ci/test-optimization-report.sh` cache fixtures from weekly suffixes such as `2026-22` to monthly suffixes such as `2026-06`, while preserving prefix grouping assertions. | ✅ | 2026-06-03 |
| TASK-014 | Update `docs/firmware-ci-prd.md`, `docs/openwrt-firmware-performance-stability-plan.md`, `docs/ci-workflow-architecture.md`, and `README.md` to describe cache period keys, fallback restore behavior, and matched-key-only save policy. | ✅ | 2026-06-03 |

### Implementation Phase 4

- GOAL-004: Keep firmware performance and stability constraints intact while changing cache behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-015 | Run `bash scripts/ci/validate-profiles.sh` and confirm profiles still follow upstream branches and `devices/profiles.yml` remains valid. | ✅ | 2026-06-03 |
| TASK-016 | Run `bash scripts/ci/test-config-audit.sh` and confirm Samba4/autosamba exclusion, BBR, SQM, CAKE, performance overlay, and x86 hardware checks still pass. | ✅ | 2026-06-03 |
| TASK-017 | Run `bash scripts/ci/validate-cache-maintenance.sh` and confirm cache cleanup still requires dry-run review and explicit deletion boundaries. | ✅ | 2026-06-03 |
| TASK-018 | Run `bash scripts/ci/test-optimization-report.sh` and confirm cache prefix grouping still works with monthly cache period suffixes. | ✅ | 2026-06-03 |
| TASK-019 | Run workflow and shell syntax validators: `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"` and `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n`. | ✅ | 2026-06-03 |

### Implementation Phase 4B

- GOAL-004B: Keep LuCI, feeds, uHTTPd, theme, and PassWall behavior aligned with official upstream defaults.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-019A | Inspect upstream `feeds.conf.default` for `coolsnowwolf/lede`, `immortalwrt/immortalwrt`, `VIKINGYFY/immortalwrt`, and `LiBwrt/openwrt-6.x`; confirm all declare an official LuCI feed and current profiles do not set local `feeds_conf` overrides. | ✅ | 2026-06-06 |
| TASK-019B | Inspect upstream LuCI `luci.mk` and `/etc/config/luci` defaults for active LuCI feeds; confirm `CONFIG_LUCI_LANG_zh_Hans` maps to `zh-cn` translation packages while default runtime language remains `auto`. | ✅ | 2026-06-06 |
| TASK-019C | Inspect ImmortalWrt LuCI default theme and uHTTPd/rpcd chain; confirm `luci` depends on `luci-light`, `luci-light` depends on `luci-theme-bootstrap`, `uhttpd`, and `uhttpd-mod-ubus`, and `luci-base` depends on rpcd modules and adds the uHTTPd LuCI ucode handler. | ✅ | 2026-06-06 |
| TASK-019D | Add the minimal `scripts/common/config/luci-zh-cn.config` fragment with only `CONFIG_LUCI_LANG_zh_Hans=y`, attach it to enabled profiles, and keep plugin translations governed by LuCI feed defaults. | ✅ | 2026-06-06 |
| TASK-019E | Extend config audit and fixtures to require `CONFIG_LUCI_LANG_zh_Hans=y` and defconfig-expanded `CONFIG_PACKAGE_luci-i18n-base-zh-cn=y`, proving the official LuCI i18n mechanism is active without hard-coded per-plugin i18n config. | ✅ | 2026-06-06 |
| TASK-019F | Update PassWall overlay logic so supported source trees clean conflicting PassWall directories, refresh `Openwrt-Passwall/openwrt-passwall-packages` from `main`, and pull `Openwrt-Passwall/openwrt-passwall` with latest-tag-required policy. | ✅ | 2026-06-06 |
| TASK-019G | Add `validate-luci-zh-cn-config.sh` and `validate-passwall-overlay.sh` to `ci-lint.yml` so future edits cannot reintroduce local feeds overrides, hard-coded per-plugin LuCI i18n packages, or non-tag PassWall main app overlays. | ✅ | 2026-06-06 |
| TASK-019H | Remove local hard-coded LuCI runtime/library package selections from `base.config`; keep `CONFIG_PACKAGE_luci=y` as the official collection selector and let config audit verify the defconfig-expanded LuCI/uHTTPd/rpcd result. | ✅ | 2026-06-06 |

### Implementation Phase 5

- GOAL-005: Prove the optimized cache policy in GitHub Actions before merging.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-020 | Commit the cache policy, validator, documentation, LuCI, and PassWall changes on branch `codex/cache-stability-optimization`. Latest pushed implementation commit: `1de9d38c700598e499d98c7e167ba21c83dc2f89`. | ✅ | 2026-06-06 |
| TASK-021 | Push branch `codex/cache-stability-optimization` to `origin`. | ✅ | 2026-06-06 |
| TASK-022 | Trigger `Optimization Health` on branch `codex/cache-stability-optimization` and record the run ID, commit SHA, and cache report result in this plan. Run `27031576058` succeeded on commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`; report showed five enabled profiles, eight caches, about `5095.58 MiB`, and four prefix groups. | ✅ | 2026-06-06 |
| TASK-023 | Trigger `Firmware CI` with `target=x86_64_all` and `release=false` on branch `codex/cache-stability-optimization`; confirm both x86 profiles succeed. Run `27031596559` succeeded on commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`; `x86_64_immortalWrt` completed at `2026-06-05T20:44:12Z` and `x86_64_LEDE` completed at `2026-06-05T20:49:09Z`. | ✅ | 2026-06-06 |
| TASK-024 | Download or inspect the x86 artifacts from TASK-023 and confirm both profiles include firmware, compile log, config audit, smoke report, size report, provenance, package archive, and checksum evidence. Downloaded and verified artifacts under `/private/tmp/openwrt-artifacts-27031596559`; both firmware zip archives passed `unzip -tq`, both `sha256sums.txt` checks passed, both smoke summaries reported `Boot status: boot-visible` and `Static checks: passed`, and both package source manifests recorded PassWall official tag `26.6.2-1`. | ✅ | 2026-06-06 |
| TASK-025 | Run `Cache Maintenance` dry-run with `dry_run=true`, `older_than_days=0`, `keep_latest=1`, and `ref=refs/heads/main`; record matched cache count, matched group count, and cleanup candidate count in this plan. Run `27031576253` succeeded, matched eight caches and four cache groups, and listed four cleanup candidates without deleting caches. | ✅ | 2026-06-06 |

### Implementation Phase 6

- GOAL-006: Merge proven changes into `main` and remove obsolete implementation branches.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-026 | Switch to `main`, run `git pull --ff-only origin main`, and verify `main` is clean before merging. |  |  |
| TASK-027 | Fast-forward merge `codex/cache-stability-optimization` into `main` with `git merge --ff-only codex/cache-stability-optimization`. |  |  |
| TASK-028 | Push `main` to `origin` and verify `origin/main` points to the merged commit. |  |  |
| TASK-029 | Delete the remote branch with `git push origin --delete codex/cache-stability-optimization` after `main` contains the commit. |  |  |
| TASK-030 | Delete the local branch with `git branch -d codex/cache-stability-optimization` after switching away from it. |  |  |
| TASK-031 | Run final branch audit commands: `git status --short --branch`, `git branch --format='%(refname:short)'`, `git branch -r --format='%(refname:short)'`, `git rev-parse HEAD origin/main`, and `git ls-remote --heads origin`. Record the result in this plan or final response. |  |  |

### Implementation Phase 7

- GOAL-007: Establish the post-merge operating loop for stable firmware generation.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-032 | After merge, trigger `Firmware CI` on `main` with `target=x86_64_all` to prove the main branch remains buildable. |  |  |
| TASK-033 | Review the first post-merge cache behavior. Expected result: if an existing fallback cache is restored, no redundant new period cache is saved; if no matched cache exists, exactly one new monthly-period cache per cache type and cache group can be saved. |  |  |
| TASK-034 | Defer real deletion of old weekly caches until the user explicitly approves a deletion command after reviewing `Cache Maintenance` dry-run output. |  |  |
| TASK-035 | After x86 remains stable, trigger `qualcommax_all`; record any upstream package, rootfs pressure, or runner memory issue before attempting `target=all`. |  |  |

## 3. Alternatives

- **ALT-001**: Pin every profile to a fixed upstream commit. Rejected because it violates REQ-001 and stops profiles from following upstream branches.
- **ALT-002**: Remove required plugins to reduce compile time or image size. Rejected because it violates REQ-002; use configuration audit, size reporting, rootfs tuning, and build evidence instead.
- **ALT-003**: Share caches across all x86 and Qualcommax profiles. Rejected because cross-source and cross-branch build accelerator caches can pollute toolchains and hide upstream incompatibilities.
- **ALT-004**: Use one fully stable cache key without any date or period suffix. Rejected because GitHub Actions caches are immutable and a stable key would never refresh after the first save.
- **ALT-005**: Keep weekly keys and continue saving whenever `cache-hit != 'true'`. Rejected because fallback restores would still create redundant new weekly caches and consume cache quota.
- **ALT-006**: Delete existing caches immediately as part of the implementation. Rejected because cache deletion requires explicit user approval and dry-run review.
- **ALT-007**: Increase cache capacity or retention without changing key policy. Rejected because the observed failure is cache churn and reuse policy, not only capacity.

## 4. Dependencies

- **DEP-001**: GitHub Actions cache restore/save actions used by `.github/workflows/firmware-build.yml`.
- **DEP-002**: GitHub Actions cache REST API behavior used by `.github/workflows/cache-maintenance.yml` and `scripts/ci/optimization-report.sh`.
- **DEP-003**: `gh` CLI access to `yyg20101/OpenWrt-firmware` for workflow dispatch, run inspection, artifact download, cache inventory, and branch cleanup verification.
- **DEP-004**: `devices/profiles.yml` for source repository slug, upstream branch, cache group, and matrix generation.
- **DEP-005**: `scripts/ci/load-device-profile.sh` and `scripts/ci/profiles.sh` for exporting profile metadata to workflow outputs.
- **DEP-006**: OpenWrt, LEDE, ImmortalWrt, and Qualcommax upstream repositories referenced by firmware profiles.
- **DEP-007**: `ccache` and OpenWrt build accelerator directories: `.ccache`, `staging_dir/host`, `staging_dir/hostpkg`, and `staging_dir/toolchain-*`.
- **DEP-008**: Existing validators in `scripts/ci/`: `validate-profiles.sh`, `validate-cache-maintenance.sh`, `test-config-audit.sh`, `test-optimization-report.sh`, `test-artifacts-release.sh`, and `test-smoke-x86.sh`.

## 5. Files

- **FILE-001**: `plan/upgrade-openwrt-firmware-cache-stability-2.md` records this implementation plan, progress, and evidence.
- **FILE-002**: `plan/upgrade-openwrt-firmware-performance-stability-1.md` remains the completed baseline plan and historical evidence.
- **FILE-003**: `.github/workflows/firmware-build.yml` owns cache period calculation, restore keys, save conditions, cache status output, firmware compile, artifacts, x86 smoke, and release publishing.
- **FILE-004**: `.github/workflows/ci-lint.yml` must run the new cache key policy validator.
- **FILE-005**: `.github/workflows/cache-maintenance.yml` owns dry-run-first cache cleanup and must not be weakened.
- **FILE-006**: `.github/workflows/optimization-health.yml` owns read-only profile, matrix, release, and cache reporting.
- **FILE-007**: `scripts/ci/validate-cache-key-policy.sh` will validate cache period naming, save conditions, and isolation boundaries.
- **FILE-008**: `scripts/ci/test-optimization-report.sh` contains cache report fixtures that must match the new period suffix convention.
- **FILE-009**: `scripts/ci/optimization-report.sh` reports live cache inventory and prefix groups.
- **FILE-010**: `scripts/ci/validate-cache-maintenance.sh` validates cache cleanup guardrails.
- **FILE-011**: `scripts/ci/audit-config.sh` validates effective firmware config and Samba4/autosamba exclusion.
- **FILE-012**: `scripts/ci/test-config-audit.sh` tests firmware config audit behavior.
- **FILE-013**: `devices/profiles.yml` defines upstream-following profiles, cache groups, compile job limits, and config fragments.
- **FILE-014**: `scripts/common/config/samba.config` keeps Samba4 enabled and autosamba disabled.
- **FILE-015**: `scripts/common/config/network-performance.config` keeps BBR, SQM, CAKE, scheduler support, and IFB available.
- **FILE-016**: `scripts/common/config/x86-performance.config` keeps x86 performance, microcode, NIC, and virtualization support.
- **FILE-017**: `files/etc/uci-defaults/99-performance-defaults` applies conservative runtime network defaults.
- **FILE-018**: `docs/firmware-ci-prd.md` documents product-level cache and CI requirements.
- **FILE-019**: `docs/openwrt-firmware-performance-stability-plan.md` documents the human-readable optimization roadmap.
- **FILE-020**: `docs/ci-workflow-architecture.md` documents workflow responsibilities and operating order.
- **FILE-021**: `README.md` documents user-facing build, validation, and cache maintenance operations.
- **FILE-022**: `scripts/common/config/luci-zh-cn.config` selects the official LuCI Simplified Chinese language option.
- **FILE-023**: `scripts/ci/validate-luci-zh-cn-config.sh` validates LuCI language policy and absence of local feeds overrides.
- **FILE-024**: `scripts/ci/validate-passwall-overlay.sh` validates PassWall latest-tag overlay policy.

## 6. Testing

- **TEST-001**: Run `bash scripts/ci/validate-cache-key-policy.sh`; expect success only when cache keys use `cache_period`, no `CACHE_WEEK` remains, and save conditions use `cache-matched-key == ''`.
- **TEST-002**: Run `bash scripts/ci/validate-cache-maintenance.sh`; expect success and no weakening of dry-run-first cache cleanup guardrails.
- **TEST-003**: Run `bash scripts/ci/validate-profiles.sh`; expect all enabled firmware profiles to validate and keep upstream-following branches.
- **TEST-004**: Run `bash scripts/ci/test-config-audit.sh`; expect Samba4/autosamba exclusion, BBR, SQM, CAKE, performance overlay, and x86 hardware checks to pass.
- **TEST-005**: Run `bash scripts/ci/test-optimization-report.sh`; expect cache prefix grouping to pass with monthly period suffix fixtures.
- **TEST-006**: Run `bash scripts/ci/test-artifacts-release.sh`; expect artifact packaging and Release metadata rules to pass.
- **TEST-007**: Run `bash scripts/ci/test-smoke-x86.sh`; expect x86 image smoke fixtures and gzip warning handling to pass.
- **TEST-008**: Run `bash scripts/ci/test-config-feeds.sh`; expect config fragment and package overlay behavior to pass.
- **TEST-009**: Run `bash scripts/ci/validate-release-maintenance.sh`; expect release cleanup guardrails to pass.
- **TEST-010**: Run `bash scripts/ci/validate-dependabot-coverage.sh`; expect dependency update coverage to pass.
- **TEST-011**: Run `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"`; expect all workflow YAML files to parse.
- **TEST-012**: Run `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n`; expect all shell scripts to pass syntax validation.
- **TEST-012A**: Run `bash scripts/ci/validate-luci-zh-cn-config.sh`; expect enabled profiles to include the shared LuCI language fragment, avoid `feeds_conf` overrides, and avoid hard-coded per-plugin i18n packages in the fragment.
- **TEST-012B**: Run `bash scripts/ci/validate-passwall-overlay.sh`; expect PassWall main app to use latest-tag-required overlay and dependency packages to use the official dependency repository.
- **TEST-013**: Run `bash scripts/ci/optimization-report.sh cache yyg20101/OpenWrt-firmware`; expect live cache inventory, refs, prefix groups, sizes, and last-access timestamps to render.
- **TEST-014**: Trigger `Optimization Health` on branch `codex/cache-stability-optimization`; expect the workflow conclusion to be `success`.
- **TEST-015**: Trigger `Firmware CI` with `target=x86_64_all` and `release=false` on branch `codex/cache-stability-optimization`; expect both x86 jobs to conclude `success`.
- **TEST-016**: Trigger `Cache Maintenance` dry-run with `ref=refs/heads/main`, `older_than_days=0`, and `keep_latest=1`; expect matched cache counts and cleanup candidates to match live cache inventory without deleting caches.
- **TEST-017**: After merge, trigger `Firmware CI` with `target=x86_64_all` on `main`; expect both x86 jobs to conclude `success`.

## 7. Risks & Assumptions

- **RISK-001**: Existing weekly caches may continue to be restored by the prefix restore key after switching to monthly primary keys. Mitigation: do not save redundant monthly caches when a weekly fallback exists; use cache maintenance dry-run and explicit approval before deleting old weekly caches.
- **RISK-002**: If old fallback caches are always restored, cache contents may not refresh until old caches are deleted or evicted. Mitigation: document this behavior and create a monthly baseline only when no matched cache exists or after approved cleanup.
- **RISK-003**: GitHub Actions `cache-matched-key` output behavior can differ from assumptions. Mitigation: verify through branch workflow output and keep local validator focused on the intended policy expression.
- **RISK-004**: Changing cache save policy can slow a build after approved cleanup because the next run may need to rebuild and save a fresh monthly cache. Mitigation: first prove x86 and run cleanup only when the user accepts the rebuild cost.
- **RISK-005**: Upstream branches can change while the local repository has no changes. Mitigation: keep profile drift reports, source commit metadata, profile hash, and artifact provenance.
- **RISK-006**: Required plugin growth can increase rootfs or compile pressure. Mitigation: keep `firmware-size-report.md`, config audit, compile job caps, and failure context rather than removing required plugins.
- **RISK-007**: Cache key isolation mistakes can share incompatible toolchains. Mitigation: validate source slug, repo branch, and cache group in cache keys and restore prefixes.
- **RISK-008**: Branch cleanup can delete the implementation branch before `main` is pushed. Mitigation: audit `HEAD`, `origin/main`, and remote branches before deletion.
- **ASSUMPTION-001**: `actions/cache/restore@v5` exposes `cache-matched-key` as an empty string when no exact or fallback cache is restored.
- **ASSUMPTION-002**: The repository owner/name for GitHub Actions evidence remains `yyg20101/OpenWrt-firmware`.
- **ASSUMPTION-003**: `x86_64_all` remains the correct first build target for stability proof.
- **ASSUMPTION-004**: `devices/profiles.yml` remains the only matrix source used by workflows and validators.
- **ASSUMPTION-005**: `ubuntu-22.04` GitHub-hosted runners remain available for the current OpenWrt build toolchain.
- **ASSUMPTION-006**: The user will approve any real cache deletion separately after reviewing dry-run results.
- **ASSUMPTION-007**: The active LuCI feeds keep the observed `zh_Hans` language symbol and `zh-cn` i18n package alias behavior.
- **ASSUMPTION-008**: `Openwrt-Passwall/openwrt-passwall-packages` does not provide a coherent whole-repository release tag; using `main` for dependency packages is safer than forcing package-specific tags such as `dns2socks`.

## 8. Related Specifications / Further Reading

- [plan/upgrade-openwrt-firmware-performance-stability-1.md](upgrade-openwrt-firmware-performance-stability-1.md)
- [docs/openwrt-firmware-performance-stability-plan.md](../docs/openwrt-firmware-performance-stability-plan.md)
- [docs/firmware-ci-prd.md](../docs/firmware-ci-prd.md)
- [docs/ci-workflow-architecture.md](../docs/ci-workflow-architecture.md)
- [README.md](../README.md)
- [GitHub Actions cache dependency caching reference](https://docs.github.com/actions/using-workflows/caching-dependencies-to-speed-up-workflows)

## 9. Execution Order

1. Complete TASK-004 through TASK-009 in `.github/workflows/firmware-build.yml`.
2. Complete TASK-010 through TASK-014 to add validator coverage and update documentation.
3. Run TEST-001 through TEST-012 locally.
4. Commit and push branch `codex/cache-stability-optimization`.
5. Complete TEST-014 through TEST-016 on GitHub Actions and record evidence in this plan.
6. If GitHub Actions evidence passes, merge into `main`, push `main`, and delete obsolete local and remote implementation branches.
7. Complete TEST-017 on `main`.
8. Keep real cache deletion pending until the user approves a dry-run-reviewed cleanup.

## 10. Evidence Log

| Evidence | Result | Date |
|----------|--------|------|
| Current branch audit | `git status --short --branch` reported `## codex/cache-stability-optimization`; `git branch --show-current` reported `codex/cache-stability-optimization`. | 2026-06-02 |
| Existing cache redundancy finding | `.github/workflows/firmware-build.yml` currently uses `cache_week="$(date +%Y-%W)"` and saves when `cache-hit != 'true'`, which creates a new period cache after fallback restore. | 2026-06-02 |
| Previous x86 proof baseline | Firmware CI run `26763561699` succeeded on commit `c4577fbfced2d800fd6192954fac4a96d78305ec` and produced all expected x86 artifacts for `x86_64_LEDE` and `x86_64_immortalWrt`. | 2026-06-02 |
| Previous cache dry-run baseline | Cache Maintenance run `26762407724` matched eight `refs/heads/main` caches, four cache groups, and four previous-week cleanup candidates without deleting caches. | 2026-06-02 |
| Cache policy implementation | `.github/workflows/firmware-build.yml` now uses monthly `CACHE_PERIOD`, primary keys with `steps.source.outputs.cache_period`, and save conditions based on empty `cache-matched-key`; `scripts/ci/validate-cache-key-policy.sh` validates the policy through `ci-lint.yml`. | 2026-06-03 |
| Local validation set | Passed `validate-cache-key-policy.sh`, workflow YAML parsing, shell syntax, `validate-profiles.sh`, `test-config-audit.sh`, `validate-cache-maintenance.sh`, `test-optimization-report.sh`, `test-artifacts-release.sh`, `test-smoke-x86.sh`, `test-config-feeds.sh`, `validate-release-maintenance.sh`, `validate-dependabot-coverage.sh`, and `optimization-report.sh summary`. | 2026-06-03 |
| Upstream feeds audit | `coolsnowwolf/lede` declares `src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12`; `immortalwrt/immortalwrt`, `VIKINGYFY/immortalwrt`, and `LiBwrt/openwrt-6.x` declare `src-git luci https://github.com/immortalwrt/luci.git`; current `devices/profiles.yml` has no `feeds_conf` overrides. | 2026-06-06 |
| Upstream LuCI language audit | Active upstream LuCI `luci.mk` defines `LUCI_LANG.zh_Hans`, maps `zh_Hans` to `zh-cn` translation package names, and sets i18n package defaults from the language option; upstream `/etc/config/luci` keeps `option lang auto`. | 2026-06-06 |
| Upstream LuCI theme/uHTTPd audit | ImmortalWrt `luci` depends on `luci-light`; `luci-light` depends on `luci-theme-bootstrap`, `uhttpd`, and `uhttpd-mod-ubus`; the Bootstrap theme sets `main.mediaurlbase` through its own uci-defaults, and `luci-base` depends on rpcd modules and adds the uHTTPd LuCI ucode handler in postinst. | 2026-06-06 |
| LuCI Chinese implementation | Added `scripts/common/config/luci-zh-cn.config` with only `CONFIG_LUCI_LANG_zh_Hans=y`, attached it to all enabled profiles, removed hard-coded LuCI runtime/library selections from `base.config`, and audited defconfig output for `CONFIG_PACKAGE_luci-base=y` and `CONFIG_PACKAGE_luci-i18n-base-zh-cn=y` without hard-coding per-plugin i18n packages. | 2026-06-06 |
| PassWall overlay implementation | `scripts/common/package` now applies PassWall overlay to LEDE and ImmortalWrt-family source trees; dependency packages use `Openwrt-Passwall/openwrt-passwall-packages` `main`, while `luci-app-passwall` uses `UPDATE_PACKAGE_LATEST_TAG` against `Openwrt-Passwall/openwrt-passwall`. Latest observed app tag: `26.6.2-1`. | 2026-06-06 |
| Local validation set after LuCI/PassWall changes | Passed after removing local LuCI runtime/library hard-coding: `validate-cache-key-policy.sh`, `validate-luci-zh-cn-config.sh`, `validate-passwall-overlay.sh`, `validate-profiles.sh`, `test-config-audit.sh`, `validate-cache-maintenance.sh`, `test-optimization-report.sh`, `test-artifacts-release.sh`, `test-smoke-x86.sh`, `test-config-feeds.sh`, workflow YAML parsing, shell syntax, `validate-release-maintenance.sh`, `validate-dependabot-coverage.sh`, `optimization-report.sh summary`, and `git diff --check`. | 2026-06-06 |
| Branch push proof | Branch `codex/cache-stability-optimization` was pushed to `origin` at commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`. | 2026-06-06 |
| Optimization Health run `27031576058` | Successful on branch `codex/cache-stability-optimization`, commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`; report showed five enabled profiles, eight caches, total cache size about `5095.58 MiB`, and four prefix groups. | 2026-06-06 |
| Cache Maintenance dry-run `27031576253` | Successful dry-run on branch `codex/cache-stability-optimization`; matched eight caches and four cache groups, reported four cleanup candidates, and deleted nothing. | 2026-06-06 |
| Firmware CI run `27031596559` config-audit artifacts | Successful branch run on `codex/cache-stability-optimization`, commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`; both x86 config-audit artifacts were uploaded and summaries show LuCI language `zh_Hans: y`, LuCI base zh-cn `y`, Bootstrap theme `y`, uHTTPd `y`, uHTTPd ubus `y`, rpcd luci `y`, Samba4 `y`, autosamba `n`, TCP BBR `y`, SQM scripts `y`, CAKE scheduler `y`, and performance defaults overlay present. Requested configs only include `CONFIG_LUCI_LANG_zh_Hans=y` for LuCI language and do not hard-code per-plugin i18n packages. | 2026-06-06 |
| Firmware CI run `27031596559` completion | Successful on branch `codex/cache-stability-optimization`, commit `1de9d38c700598e499d98c7e167ba21c83dc2f89`; `x86_64_immortalWrt` and `x86_64_LEDE` both completed with conclusion `success`. Compile, firmware upload, x86 smoke, and smoke upload steps all succeeded. Cache save steps were skipped on the branch run because saves are restricted to `refs/heads/main`, which matches the intended cache policy. | 2026-06-06 |
| Firmware CI run `27031596559` cache log | Logs show `cache period: 2026-06`, `cache save policy: save only when no matched cache key exists`, and matched ccache/build-accelerator keys for both x86 source groups. Branch run did not save duplicate caches. | 2026-06-06 |
| Firmware CI run `27031596559` artifact inventory | Produced all eight expected x86 artifacts: config audit, compile log, firmware, and smoke artifacts for both `x86_64_LEDE` and `x86_64_immortalWrt`. | 2026-06-06 |
| Firmware CI run `27031596559` firmware artifact verification | Downloaded firmware archives to `/private/tmp/openwrt-artifacts-27031596559/zips`; both firmware zip archives passed `unzip -tq`; extracted firmware artifacts include `build.config`, `artifact-manifest.txt`, `firmware-size-report.md`, `build-environment-provenance.md`, `package-source-manifest.tsv`, `Packages.tar.gz`, x86 images, `sha256sums`, and `sha256sums.txt`; `shasum -a 256 -c sha256sums.txt` passed for both profiles. | 2026-06-06 |
| Firmware CI run `27031596559` smoke verification | Downloaded smoke artifacts for both x86 profiles; both summaries report `Boot status: boot-visible` and `Static checks: passed`; QEMU logs reached `procd: - init -` and `Please press Enter to activate this console.` | 2026-06-06 |
| Firmware CI run `27031596559` PassWall source verification | Both `package-source-manifest.tsv` files record `Openwrt-Passwall/openwrt-passwall-packages` on `main` commit `9e9ed6d9f441821a837a150098f99c65a0818590` and `Openwrt-Passwall/openwrt-passwall` tag `26.6.2-1` commit `2be2586fe72f07024326f7e590f7c6de99aaf469`. | 2026-06-06 |
| Firmware CI run `27031596559` size and provenance verification | LEDE reports `281884 KiB` package archive input and ImmortalWrt reports `207388 KiB` package archive input against `1024 MiB` rootfs partsize; both artifacts record runner image `ubuntu22 20260525.156.1`, init script URL `https://build-scripts.immortalwrt.org/init_build_environment.sh`, and init script sha256 `85f4b2c2aa16f8178b57250f5d2bcf4a2e0707c6b569a3b07510f41fc6185dd8`. | 2026-06-06 |

## 11. OpenWrt 固件性能与稳定性优化实施计划

本节是当前执行版中文计划，用于把固件稳定生成、配置文件质量、运行时性能、GitHub Actions 缓存复用和后续合入清理放到同一张路线图中。第 2 节任务表仍是逐项打勾的执行来源，本节用于人工复盘、排期和验收。

### 11.1 总体目标

- **OBJ-001**: 优先保证 `x86_64_LEDE` 和 `x86_64_immortalWrt` 可以稳定生成完整固件产物。
- **OBJ-002**: profile 继续跟随上游分支，使用 source commit、profile drift、package provenance 和 artifact evidence 控制变化风险。
- **OBJ-003**: 保留用户必要插件，不通过删除插件换取构建成功；通过配置分层、审计、rootfs/size 报告和失败上下文解决压力。
- **OBJ-004**: 使用官方 LuCI、feeds、uHTTPd、rpcd、主题和语言机制；本地只选择必要能力并审计 defconfig 结果。
- **OBJ-005**: PassWall 使用官方 overlay，主应用按最新官方 tag 构建，依赖仓保持官方 `main` 并记录来源。
- **OBJ-006**: 缓存策略减少重复保存，保持 source repo、source branch 和 cache group 隔离，真实删除只在 dry-run 审核后执行。
- **OBJ-007**: 合入 `main` 前完成分支 CI 证明；合入后再次触发 `main` 的 `x86_64_all` 证明，再清理旧分支。

### 11.2 阶段计划

| Phase | Goal | Key Actions | Acceptance | Status |
|-------|------|-------------|------------|--------|
| P0: Profile 与上游基线 | profile 继续跟随上游，同时让上游变化可追踪。 | 保持 `devices/profiles.yml` 的 `source_branch` 不 pin；确认 enabled profiles 不使用 `feeds_conf` 覆盖；通过 Optimization Health 输出 source repo、branch、remote HEAD 和 profile hash。 | 每个 enabled profile 能追溯 source repo、source branch、source commit、config fragments 和 cache group；上游漂移不会静默发生。 | 已实施，分支证据已补齐 |
| P1: 固件配置守护 | 把必要插件、启动能力、LuCI 中文、Samba4 和 PassWall 变成可审计约束。 | 保持 `scripts/common/config/*.config` 分层；`luci-zh-cn.config` 只选择 `CONFIG_LUCI_LANG_zh_Hans=y`；Samba4 启用且 autosamba 禁用；PassWall 清理冲突目录并拉取最新官方 tag。 | `test-config-audit.sh`、`validate-luci-zh-cn-config.sh`、`validate-passwall-overlay.sh` 均通过；defconfig-expanded 结果包含 LuCI i18n、uHTTPd、rpcd、主题、Samba4、BBR、SQM 和 CAKE。 | 已实施 |
| P2: x86 稳定生成证明 | 先证明 x86 两个 profile 可以稳定产出。 | 在分支触发 `Firmware CI` 的 `target=x86_64_all`；检查 `x86_64_LEDE` 和 `x86_64_immortalWrt` 的 compile、config audit、firmware artifact、smoke artifact。 | 两个 x86 job 均 success；artifact 包含 `build.config`、`artifact-manifest.txt`、`firmware-size-report.md`、`build-environment-provenance.md`、`package-source-manifest.tsv`、`Packages.tar.gz`、x86 image、`sha256sums.txt` 和 smoke summary。 | 已完成，run `27031596559` 通过 |
| P3: 缓存复用与容量控制 | 降低 GitHub Actions cache 重复保存和容量超额风险。 | cache key 使用 monthly `cache_period`；restore prefix 只在同 source slug、branch、cache group 内 fallback；save 仅在 `cache-matched-key == ''` 时执行；维护 workflow 先 dry-run。 | Optimization Health 显示 cache count、size、prefix groups、last access；Cache Maintenance dry-run 能列出候选且不删除；无用户确认不执行真实删除。 | 已实施，dry-run 已通过 |
| P4: 运行时性能优化 | 使用保守默认值提升吞吐和响应，同时避免改变用户网络拓扑。 | 保持 BBR、fq_codel、TCP Fast Open、MTU probing、backlog、TCP buffer；启用 irqbalance、microcode、virtio、常见 x86 NIC、SQM、CAKE 和 IFB；不默认强制开启流控策略。 | 缺少 performance overlay 或关键性能包时配置审计失败；成功 artifact 能看到性能配置来源和固件体积压力。 | 已实施 |
| P5: 构建可观测与 provenance | 让成功和失败构建都能复盘。 | 保留 compile log、failure context、firmware size report、package source manifest、build environment provenance、release metadata 和 checksum。 | 失败时能定位下载、磁盘、内存、工具链或包编译阶段；成功时能校验产物完整性、包来源、runner 环境和固件大小。 | 已实施 |
| P6: 合入主分支与旧分支清理 | 只把有证据的优化合入 `main`。 | 分支 x86 CI 和 cache dry-run 通过后 fast-forward merge 到 `main`；push `main`；触发 `main` 的 `x86_64_all`；再删除 remote/local implementation branch。 | `origin/main` 指向合入 commit；main 上 x86 CI 通过；旧分支删除后 final branch audit 干净。 | 待执行 |
| P7: Qualcommax 扩展 | x86 稳定后扩大验证范围。 | 触发 `qualcommax_all`；复用同一套 config audit、cache、artifact、failure context、size report 和 provenance 检查。 | 失败能归类为上游源码、包 overlay、rootfs 空间、runner 内存或本地配置问题；通过后再考虑 `target=all`。 | 后续执行 |
| P8: 固化运维节奏 | 把稳定生成变成可重复流程。 | 每次大改先跑本地 validators；再跑 Optimization Health；再跑 `x86_64_all`；容量紧张时先 Cache Maintenance dry-run；Release 前做 artifact/release 检查。 | 新增 profile、插件或性能配置时有固定验证链路；缓存清理和 Release 发布都有证据记录。 | 持续执行 |

### 11.3 执行清单

| Step | Command or Check | Expected Result |
|------|------------------|-----------------|
| CHECK-001 | `bash scripts/ci/validate-cache-key-policy.sh` | cache period、matched-key save policy 和隔离边界有效。 |
| CHECK-002 | `bash scripts/ci/validate-luci-zh-cn-config.sh` | enabled profiles 都包含 LuCI 中文片段，且没有 local feeds override 或 per-plugin i18n 硬编码。 |
| CHECK-003 | `bash scripts/ci/validate-passwall-overlay.sh` | PassWall 主应用使用 latest-tag-required，依赖包使用官方 packages 仓。 |
| CHECK-004 | `bash scripts/ci/validate-profiles.sh` | profile matrix、config paths、config fragments 和 upstream-following branch 配置有效。 |
| CHECK-005 | `bash scripts/ci/test-config-audit.sh` | Samba4/autosamba、LuCI/uHTTPd/rpcd、BBR/SQM/CAKE、x86 boot 和 overlay 审计通过。 |
| CHECK-006 | `bash scripts/ci/test-artifacts-release.sh` and `bash scripts/ci/test-smoke-x86.sh` | artifact/release 规则和 x86 smoke fixture 通过。 |
| CHECK-007 | `gh workflow run optimization-health.yml --repo yyg20101/OpenWrt-firmware --ref codex/cache-stability-optimization` | profile、matrix、cache health 报告成功生成。 |
| CHECK-008 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref codex/cache-stability-optimization -f target=x86_64_all -f release=false` | 分支上的两个 x86 profile 均构建成功。当前跟踪 run `27031596559`。 |
| CHECK-009 | `gh workflow run cache-maintenance.yml --repo yyg20101/OpenWrt-firmware --ref codex/cache-stability-optimization -f dry_run=true -f older_than_days=0 -f keep_latest=1 -f ref=refs/heads/main` | 仅输出匹配缓存、分组和候选，不删除缓存。 |
| CHECK-010 | `git merge --ff-only codex/cache-stability-optimization` from clean `main` | 只在 CHECK-007 到 CHECK-009 通过并记录证据后合入。 |
| CHECK-011 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=x86_64_all -f release=false` | main 分支 x86 固件稳定生成。 |
| CHECK-012 | `git push origin --delete codex/cache-stability-optimization` and `git branch -d codex/cache-stability-optimization` | main 已包含实现且主分支 CI 证明通过后，清理旧分支。 |

### 11.4 性能与稳定性验收重点

- **AC-001**: `build.config` 中能看到 `CONFIG_LUCI_LANG_zh_Hans=y`，defconfig-expanded audit 中能看到 `CONFIG_PACKAGE_luci-i18n-base-zh-cn=y`。
- **AC-002**: `CONFIG_PACKAGE_samba4-server=y`，`CONFIG_PACKAGE_autosamba` 不启用。
- **AC-003**: BBR、SQM scripts、CAKE scheduler、IFB 和 performance defaults overlay 均通过 config audit。
- **AC-004**: x86 artifact 至少包含一个 raw compressed image，并且 `shasum -a 256 -c sha256sums.txt` 通过。
- **AC-005**: smoke summary 显示 static checks 通过，并能看到 boot-visible 或明确的早期启动证据。
- **AC-006**: `package-source-manifest.tsv` 能追溯 PassWall 官方仓库、ref/tag 和 commit。
- **AC-007**: cache log 显示 cache period、matched key、save policy；fallback 命中时不会因为 primary key 不同而保存重复 cache。
- **AC-008**: Cache Maintenance 真实删除保持挂起，直到用户基于 dry-run 输出批准具体 `ref` 或 `prefix`。
- **AC-009**: 合入后 `HEAD`、`main` 和 `origin/main` 一致，旧 implementation branch 不再保留。

### 11.5 后续优化方向

- **NEXT-001**: 在 `qualcommax_all` 首次证明后，按 profile 记录 rootfs 压力和编译失败包，必要时拆分 profile-specific size tuning，不移除必要插件。
- **NEXT-002**: 对 PassWall 及代理依赖增加更细的 artifact provenance 摘要，方便判断失败来自主应用 tag、依赖包仓、feeds 冲突还是上游源码变更。
- **NEXT-003**: 观察 main 分支第一轮 monthly cache 行为；如 fallback 一直命中过旧 weekly cache，再由用户确认是否按 dry-run 候选清理旧缓存。
- **NEXT-004**: 若 runner 内存成为瓶颈，优先调整 `make_compile_jobs` 和 fallback 策略，再考虑 profile 级别 rootfs/镜像大小参数。
- **NEXT-005**: Release 前新增一次 `optimization-report.sh release <repo> <tag>` 复核，确保 `Packages.tar.gz` 保留、VM-only 镜像排除、checksum 和 manifest 齐全。

## 12. Completion Criteria

- **DONE-001**: `.github/workflows/firmware-build.yml` uses `CACHE_PERIOD` and `cache_period`, not `CACHE_WEEK` or `cache_week`.
- **DONE-002**: ccache and build accelerator save steps use `cache-matched-key == ''` and do not use `cache-hit != 'true'`.
- **DONE-003**: Cache keys keep cache type, cache version, source slug, repo branch, cache group, and cache period.
- **DONE-004**: `scripts/ci/validate-cache-key-policy.sh` exists and is executed by `.github/workflows/ci-lint.yml`.
- **DONE-005**: Documentation describes period-based keys, fallback restore, matched-key save policy, and dry-run-first cleanup.
- **DONE-006**: Local validators TEST-001 through TEST-012 pass.
- **DONE-006A**: LuCI Chinese policy follows the official upstream language option, does not locally override `feeds.conf.default`, does not replace official theme/uHTTPd/runtime defaults, and does not hard-code per-plugin translation packages.
- **DONE-006B**: PassWall overlay uses latest-tag-required policy for `luci-app-passwall` and records source provenance through the package overlay manifest.
- **DONE-007**: Branch `codex/cache-stability-optimization` is pushed and GitHub Actions TEST-014 through TEST-016 pass.
- **DONE-008**: x86 artifacts from the implementation branch include firmware, compile logs, config audit, smoke reports, size reports, provenance, package archive, and checksum evidence.
- **DONE-009**: The implementation is fast-forward merged into `main` and `main` is pushed to `origin`.
- **DONE-010**: Obsolete local and remote implementation branches are deleted after merge.
- **DONE-011**: Final branch and worktree audit confirms `main` is clean, `HEAD` equals `origin/main`, and no obsolete implementation branch remains.
- **DONE-012**: This plan is updated to `Completed` only after DONE-001 through DONE-011 are satisfied.
