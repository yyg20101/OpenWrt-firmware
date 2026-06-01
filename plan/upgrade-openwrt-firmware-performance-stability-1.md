---
goal: OpenWrt firmware performance and stability optimization
version: 1.3
date_created: 2026-06-01
last_updated: 2026-06-02
owner: wajie
status: Completed
tags:
  - openwrt
  - firmware
  - ci
  - performance
  - stability
  - cache
---

# Introduction

![Status: Completed](https://img.shields.io/badge/status-Completed-brightgreen)

This implementation plan defines the concrete work required to keep the OpenWrt firmware builds stable, fast, and observable while preserving upstream-following profiles and all user-required plugins. The plan prioritizes `x86_64_LEDE` and `x86_64_immortalWrt`, then expands the same guardrails to Qualcommax targets after the x86 path is proven.

The current baseline includes profile drift reporting, x86 smoke validation, failure-context artifacts, cache grouping, cache maintenance guardrails, layered config fragments, Samba4/autosamba exclusion, conservative runtime performance defaults, firmware size reporting, package overlay provenance, and build environment provenance. The x86 proof and cache dry-run proof are complete for branch `codex-openwrt-optimization-execution`; Qualcommax expansion remains a follow-up operating task after this branch is merged.

## 1. Requirements & Constraints

- **REQ-001**: `x86_64_LEDE` and `x86_64_immortalWrt` must remain the first stability targets before widening to `qualcommax_all` or `all`.
- **REQ-002**: `devices/profiles.yml` must keep `source_branch` following upstream branches; do not pin profile sources to local commits.
- **REQ-003**: User-required plugins must remain enabled; optimization must not remove required packages only to make builds pass.
- **REQ-004**: Samba4 is the preferred file-sharing baseline; `autosamba` must remain disabled and must not coexist with Samba4.
- **REQ-005**: Cache optimization must improve reuse, visibility, cleanup boundaries, and retention safety without simply increasing cache size.
- **REQ-006**: Every build must preserve configuration audit output, compile logs, cache status, source commit evidence, and failure-context artifacts.
- **REQ-007**: x86 firmware artifacts must include usable raw compressed images and smoke validation logs when compile succeeds.
- **REQ-008**: Release assets must retain `Packages.tar.gz` and must exclude VM-only image formats from release publishing.
- **REQ-009**: This plan document must remain the execution source of truth; do not mark the plan `Completed` until the implementation commit's x86 CI artifacts are verified and evidence is recorded.
- **SEC-001**: Remote build environment scripts and package overlay sources must be logged so provenance can be reviewed after a failure.
- **CON-001**: Changes must remain compatible with the existing GitHub Actions split between `firmware-ci.yml`, `firmware-build.yml`, `optimization-health.yml`, `cache-maintenance.yml`, and `release-maintenance.yml`.
- **CON-002**: `devices/profiles.yml` remains the single source of truth for profile matrix membership, source repository, source branch, config path, cache group, and config fragments.
- **CON-003**: Real GitHub Actions cache deletion must require an explicit `prefix` or `ref` filter and must be preceded by a dry-run review.
- **CON-004**: Build acceleration cache keys must not cross source repository, source branch, or cache group boundaries.
- **GUD-001**: Keep performance configuration split into base, network, storage, USB/mobile, proxy, Samba, x86, x86 performance, and platform-specific fragments.
- **GUD-002**: Keep x86 audit hard failures limited to invariant requirements; report upstream-specific optional driver variance as advisory output.
- **PAT-001**: Prefer CI helper scripts in `scripts/ci/` for reusable logic instead of duplicating shell snippets inside workflows.
- **PAT-002**: Use dry-run-first maintenance workflows and local validators for cache, release, workflow YAML, shell syntax, and profile matrix changes.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Make x86 builds observable and prevent upstream-specific config variance from hiding real failures.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add profile drift reporting in `scripts/ci/optimization-report.sh` and `.github/workflows/optimization-health.yml` so the report shows source repository, source branch, remote HEAD, and last build commit for every enabled profile in `devices/profiles.yml`. | ✅ | 2026-06-01 |
| TASK-002 | Add x86 smoke validation in `scripts/ci/smoke-x86.sh`, `scripts/ci/test-smoke-x86.sh`, and `.github/workflows/firmware-build.yml` to verify gzip integrity, partition visibility, and early boot diagnostics for x86 images. | ✅ | 2026-06-01 |
| TASK-003 | Capture failure context in `scripts/ci/build-artifacts.sh` and upload `failure-context-*` artifacts from `.github/workflows/firmware-build.yml` containing failed package hints, last compile log lines, disk state, memory state, ccache state, and OpenWrt target metadata. | ✅ | 2026-06-01 |
| TASK-004 | Relax x86 virtio checks in `scripts/ci/audit-config.sh` and `scripts/ci/test-config-audit.sh` so advisory modules are reported without blocking valid upstream variants. | ✅ | 2026-06-01 |
| TASK-005 | Treat gzip warning exit code `2` from `gzip -t` as non-fatal in `scripts/ci/smoke-x86.sh` when the output confirms `decompression OK, trailing garbage ignored`, and keep real gzip errors fatal. | ✅ | 2026-06-01 |

### Implementation Phase 2

- GOAL-002: Improve cache reuse and compile throughput without crossing source, branch, or profile boundaries.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-006 | Keep cache keys in `.github/workflows/firmware-build.yml` grouped by cache type, cache version, source slug, source branch, cache group, and calendar week. | ✅ | 2026-06-01 |
| TASK-007 | Show ccache and build accelerator exact hit state, matched key, cache group, total cache size, and recent access data through `.github/workflows/firmware-build.yml` and `scripts/ci/optimization-report.sh`. | ✅ | 2026-06-01 |
| TASK-008 | Tune `make_compile_jobs` per profile in `devices/profiles.yml` and keep fallback compilation behavior in `scripts/ci/build-artifacts.sh` so memory-sensitive sources can retry with safer parallelism. | ✅ | 2026-06-01 |
| TASK-009 | Preserve layered config fragments in `scripts/common/config/*.config` and `devices/profiles.yml` so required plugins and performance capabilities remain traceable to specific fragments. | ✅ | 2026-06-01 |
| TASK-010 | Keep cache maintenance reviewable through `.github/workflows/cache-maintenance.yml` and `scripts/ci/validate-cache-maintenance.sh`, with real deletion blocked unless a `prefix` or `ref` filter is supplied. | ✅ | 2026-06-01 |
| TASK-011 | Fix `.github/workflows/cache-maintenance.yml` so a dry run with `ref=refs/heads/main`, `older_than_days=0`, and `keep_latest=1` discovers current main-branch caches through the Actions cache API and reports four previous-week cleanup candidates. | ✅ | 2026-06-01 |

### Implementation Phase 3

- GOAL-003: Improve firmware runtime performance while keeping the package set intact.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-012 | Keep `scripts/common/config/network-performance.config` enabling BBR, SQM, CAKE, scheduler support, and IFB while ensuring these packages do not force traffic shaping until the user configures it. | ✅ | 2026-06-01 |
| TASK-013 | Keep `scripts/common/config/x86-performance.config` enabling irqbalance, microcode, common physical NIC drivers, virtio drivers, and QEMU guest agent for physical and virtual x86 deployments. | ✅ | 2026-06-01 |
| TASK-014 | Keep `files/etc/uci-defaults/99-performance-defaults` limited to conservative sysctl defaults: `fq_codel`, BBR, TCP Fast Open, MTU probing, backlog, and TCP buffer ranges. | ✅ | 2026-06-01 |
| TASK-015 | Extend `scripts/ci/audit-config.sh` and `scripts/ci/test-config-audit.sh` when new performance defaults are added so missing overlay files, missing core packages, Samba4/autosamba conflicts, and x86 boot capability regressions fail during configuration. Current x86 config-audit artifacts verify Samba4/autosamba, BBR, SQM, CAKE, performance overlay, and x86 hardware checks. | ✅ | 2026-06-02 |
| TASK-016 | Add size and rootfs pressure reporting to `scripts/ci/build-artifacts.sh` or `scripts/ci/optimization-report.sh` so required plugin growth is visible without removing plugins. | ✅ | 2026-06-01 |

### Implementation Phase 4

- GOAL-004: Strengthen supply-chain and release stability while keeping upstream-following profile behavior.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-017 | Keep release and artifact integrity checks in `scripts/ci/test-artifacts-release.sh`, `scripts/ci/validate-release-maintenance.sh`, and `.github/workflows/release-maintenance.yml`. | ✅ | 2026-06-01 |
| TASK-018 | Document the maintenance cadence and operating order in `docs/ci-workflow-architecture.md`, `docs/firmware-ci-prd.md`, `docs/openwrt-firmware-performance-stability-plan.md`, `README.md`, and this plan. | ✅ | 2026-06-01 |
| TASK-019 | Add package overlay provenance reporting for `scripts/common/Packages.sh` and `scripts/common/package` so artifact metadata can distinguish local config regressions from upstream package changes. | ✅ | 2026-06-01 |
| TASK-020 | Add explicit build-environment provenance to `.github/workflows/firmware-build.yml`, including runner image, remote initialization script URL, script download timestamp, and script checksum when available. | ✅ | 2026-06-01 |

### Implementation Phase 5

- GOAL-005: Prove the current branch in GitHub Actions before merging or deleting old branches.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-021 | Re-run `Optimization Health` on branch `codex-openwrt-optimization-execution` and record the successful run URL and commit SHA in the evidence section of this plan. | ✅ | 2026-06-01 |
| TASK-022 | Re-run `Firmware CI` with `target=x86_64_all` on branch `codex-openwrt-optimization-execution` after the gzip warning fix and confirm both `x86_64_LEDE` and `x86_64_immortalWrt` produce firmware, config audit, compile log, and smoke artifacts. Run `26763561699` succeeded on commit `c4577fbfced2d800fd6192954fac4a96d78305ec` and produced all eight expected artifacts. | ✅ | 2026-06-02 |
| TASK-023 | Re-run `Cache Maintenance` dry-run with `dry_run=true`, `older_than_days=0`, `keep_latest=1`, and `ref=refs/heads/main`; confirm it reports eight matched caches, four cache groups, and four cleanup candidates for the previous week. | ✅ | 2026-06-01 |
| TASK-024 | After TASK-022 and TASK-023 pass, update this plan to `Completed`, commit the plan update, and only then consider merging this branch into `main`. | ✅ | 2026-06-02 |

### Implementation Phase 6

- GOAL-006: Turn the x86 proof into a repeatable release-readiness operating loop.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-025 | Inspect implementation commit Firmware CI run `26763561699` on branch `codex-openwrt-optimization-execution`; if it succeeds, download artifacts and verify both x86 profiles include `build.config`, `artifact-manifest.txt`, `firmware-size-report.md`, `build-environment-provenance.md`, `Packages.tar.gz`, raw compressed x86 images, `sha256sums.txt`, compile logs, config audit artifacts, and smoke reports. Downloaded artifacts to `/private/tmp/openwrt-artifacts-26763561699` and verified both x86 profiles. | ✅ | 2026-06-02 |
| TASK-026 | If run `26763561699` fails, inspect `gh run view 26763561699 --log-failed`, fix the root cause without removing required plugins, rerun `target=x86_64_all`, and record the new run URL, commit SHA, failed package evidence, and fix commit in this plan. No failure path was required because run `26763561699` completed successfully. | ✅ | 2026-06-02 |
| TASK-027 | Record Qualcommax expansion as post-x86 follow-up work: after this branch is merged, trigger `Firmware CI` with `target=qualcommax_all`, keep the same cache and artifact evidence requirements, and record any rootfs pressure or upstream package failures before attempting `target=all`. | ✅ | 2026-06-02 |
| TASK-028 | Review `firmware-size-report.md` across successful x86 profiles and decide whether future size pressure should be handled by rootfs/image-size tuning, profile-specific config fragments, or package-source fixes; do not remove required plugins as the first response. Current x86 reports show LEDE package archive input `279140 KiB` and ImmortalWrt package archive input `207620 KiB` against `1024 MiB` rootfs partsize. | ✅ | 2026-06-02 |
| TASK-029 | Define the recurring cache maintenance cadence: run `Optimization Health` cache reporting first, run `Cache Maintenance` dry-run second, and perform real deletion only with explicit user approval plus a concrete `ref` or `prefix` filter. | ✅ | 2026-06-02 |
| TASK-030 | Prepare the merge checklist for `main`: local validators pass, implementation commit x86 CI passes, cache dry-run evidence is recorded, old branch cleanup candidates are listed, and `devices/profiles.yml` still follows upstream branches. | ✅ | 2026-06-02 |

## 3. Alternatives

- **ALT-001**: Pin every profile to a fixed upstream commit. Rejected because it violates REQ-002 and stops profiles from following upstream branches.
- **ALT-002**: Remove required plugins to reduce image size and rootfs pressure. Rejected because it violates REQ-003; use rootfs reporting, config audit, and build evidence instead.
- **ALT-003**: Increase GitHub Actions cache size or retain all weekly caches. Rejected because the failure mode is cache reuse and cleanup control, not only capacity.
- **ALT-004**: Share build acceleration caches across all x86 and Qualcommax profiles. Rejected because cross-source and cross-branch cache reuse can pollute toolchains and hide upstream incompatibilities.
- **ALT-005**: Make QEMU smoke validation advisory-only permanently. Rejected as the end state because x86 artifact bootability must eventually be a build-quality signal; temporary advisory behavior is acceptable only while false positives are being eliminated.

## 4. Dependencies

- **DEP-001**: GitHub Actions cache, artifact, checkout, and github-script actions used by `.github/workflows/*.yml`.
- **DEP-002**: `gh` CLI with repository access for workflow dispatch, run inspection, cache inventory, and cache maintenance evidence.
- **DEP-003**: `qemu-system-x86`, `qemu-utils`, `gzip`, `file`, and GNU shell tooling for x86 smoke validation.
- **DEP-004**: OpenWrt, LEDE, ImmortalWrt, and selected Qualcommax upstream repositories referenced by `devices/profiles.yml`.
- **DEP-005**: `ccache` plus OpenWrt `staging_dir/host`, `staging_dir/hostpkg`, and `staging_dir/toolchain-*` directories for build acceleration.
- **DEP-006**: Runtime packages declared in `scripts/common/config/*.config`, especially BBR, SQM, CAKE, IFB, irqbalance, x86 NIC drivers, microcode, Samba4, USB/mobile support, storage support, and proxy plugins.

## 5. Files

- **FILE-001**: `plan/upgrade-openwrt-firmware-performance-stability-1.md` records this implementation plan and evidence.
- **FILE-002**: `docs/openwrt-firmware-performance-stability-plan.md` contains the human-readable optimization roadmap.
- **FILE-003**: `docs/ci-workflow-architecture.md` documents workflow responsibilities and maintenance order.
- **FILE-004**: `docs/firmware-ci-prd.md` documents CI requirements and product-level behavior.
- **FILE-005**: `README.md` documents user-facing workflow usage.
- **FILE-006**: `devices/profiles.yml` defines source repositories, upstream-following branches, config paths, groups, cache groups, compile job limits, and config fragments.
- **FILE-007**: `.github/workflows/firmware-ci.yml` dispatches profile-group builds.
- **FILE-008**: `.github/workflows/firmware-build.yml` builds firmware, restores and saves caches, uploads artifacts, and publishes releases.
- **FILE-009**: `.github/workflows/optimization-health.yml` reports profile, matrix, release, and cache health.
- **FILE-010**: `.github/workflows/cache-maintenance.yml` performs dry-run-first cache cleanup.
- **FILE-011**: `.github/workflows/release-maintenance.yml` manages release retention.
- **FILE-012**: `scripts/ci/load-device-profile.sh` converts profile definitions to workflow environment variables and outputs.
- **FILE-013**: `scripts/ci/config-feeds.sh` applies feeds, config fragments, package overlays, and custom scripts.
- **FILE-014**: `scripts/ci/audit-config.sh` validates effective configuration and overlay requirements.
- **FILE-015**: `scripts/ci/build-artifacts.sh` downloads dependencies, compiles firmware, records failure context, organizes artifacts, and writes metadata.
- **FILE-016**: `scripts/ci/smoke-x86.sh` validates x86 image integrity and boot diagnostics.
- **FILE-017**: `scripts/ci/optimization-report.sh` reports profile, matrix, cache, summary, and release health.
- **FILE-018**: `scripts/ci/validate-cache-maintenance.sh` validates cache maintenance workflow guardrails.
- **FILE-019**: `scripts/ci/test-config-audit.sh` tests config audit behavior.
- **FILE-020**: `scripts/ci/test-smoke-x86.sh` tests x86 smoke behavior.
- **FILE-021**: `scripts/ci/test-optimization-report.sh` tests optimization report behavior.
- **FILE-022**: `scripts/ci/test-artifacts-release.sh` tests artifact and release behavior.
- **FILE-023**: `scripts/ci/validate-profiles.sh` validates profile matrix and config fragment wiring.
- **FILE-024**: `scripts/common/config/base.config` contains base package selections.
- **FILE-025**: `scripts/common/config/network-performance.config` contains network performance packages.
- **FILE-026**: `scripts/common/config/storage.config` contains storage packages.
- **FILE-027**: `scripts/common/config/usb-mobile.config` contains USB and mobile network support packages.
- **FILE-028**: `scripts/common/config/proxy.config` contains required proxy packages.
- **FILE-029**: `scripts/common/config/samba.config` enables Samba4 and disables autosamba.
- **FILE-030**: `scripts/common/config/x86.config` contains x86 target image settings.
- **FILE-031**: `scripts/common/config/x86-performance.config` contains x86 performance and hardware packages.
- **FILE-032**: `scripts/common/config/qualcommax-ipq60xx.config` contains Qualcommax platform settings.
- **FILE-033**: `scripts/common/config/lede-extra.config` contains LEDE-specific package selections.
- **FILE-034**: `scripts/common/config/immortalwrt-extra.config` contains ImmortalWrt-specific package selections.
- **FILE-035**: `files/etc/uci-defaults/99-performance-defaults` writes conservative runtime network defaults.
- **FILE-036**: `scripts/common/Packages.sh` and `scripts/common/package` provide package overlay behavior that must be traceable.

## 6. Testing

- **TEST-001**: Run `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"` to verify workflow YAML parses.
- **TEST-002**: Run `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n` to verify shell syntax.
- **TEST-003**: Run `bash scripts/ci/validate-profiles.sh` to verify profile matrix and config fragment paths.
- **TEST-004**: Run `bash scripts/ci/test-config-audit.sh` to verify x86 audit rules, Samba4/autosamba exclusion, performance package checks, and overlay checks.
- **TEST-005**: Run `bash scripts/ci/test-smoke-x86.sh` to verify x86 smoke fixtures, gzip warning handling, image selection, and failure behavior.
- **TEST-006**: Run `bash scripts/ci/test-optimization-report.sh` to verify profile, matrix, cache, summary, and release report behavior.
- **TEST-007**: Run `bash scripts/ci/test-artifacts-release.sh` to verify artifact packaging and release metadata rules.
- **TEST-008**: Run `bash scripts/ci/validate-cache-maintenance.sh` to verify cache cleanup guardrails, input handling, per-group retention, and candidate logging.
- **TEST-009**: Run `bash scripts/ci/validate-release-maintenance.sh` to verify release maintenance constraints.
- **TEST-010**: Run `bash scripts/ci/optimization-report.sh cache yyg20101/OpenWrt-firmware` to verify live cache inventory, total size, refs, groups, and last-access timestamps.
- **TEST-011**: Run `gh workflow run optimization-health.yml --repo yyg20101/OpenWrt-firmware --ref codex-openwrt-optimization-execution` and inspect the resulting run for success.
- **TEST-012**: Run `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref codex-openwrt-optimization-execution -f target=x86_64_all -f release=false -f make_latest=false` and confirm both x86 jobs succeed.
- **TEST-013**: Run `gh workflow run cache-maintenance.yml --repo yyg20101/OpenWrt-firmware --ref codex-openwrt-optimization-execution -f dry_run=true -f older_than_days=0 -f keep_latest=1 -f ref=refs/heads/main` and confirm the dry-run candidate count matches the live cache inventory.

## 7. Risks & Assumptions

- **RISK-001**: Upstream branches can change behavior without local changes, making identical profiles build differently over time. Mitigation: keep source commit evidence, profile drift reporting, and profile hash output.
- **RISK-002**: x86 audit rules can become too strict for one upstream and too loose for another. Mitigation: hard-fail only invariant requirements and keep optional driver variance advisory.
- **RISK-003**: Aggressive cache cleanup can remove useful reuse and slow the next build. Mitigation: require dry-run review, explicit filter boundaries, and newest-per-group retention.
- **RISK-004**: The GitHub Actions cache API can behave differently between branch workflow runs and main-branch cache refs. Mitigation: compare workflow dry-run output with `gh api` and fix API pagination or request path before deleting caches.
- **RISK-005**: Required plugin growth can increase rootfs pressure over time. Mitigation: add artifact size and rootfs pressure reporting instead of removing required plugins.
- **RISK-006**: QEMU smoke can fail on harmless image quirks such as gzip trailing data. Mitigation: classify known warning patterns precisely and keep unknown smoke failures fatal.
- **RISK-007**: Remote build initialization scripts or package overlays can change outside this repository. Mitigation: record provenance, timestamps, and checksums where available.
- **ASSUMPTION-001**: `devices/profiles.yml` remains the only profile matrix source used by CI and documentation generators.
- **ASSUMPTION-002**: GitHub-hosted `ubuntu-22.04` runners remain available for the current OpenWrt build toolchain.
- **ASSUMPTION-003**: `x86_64_all` is the correct first GitHub Actions target for release-readiness validation.
- **ASSUMPTION-004**: Live cache inventory currently contains eight caches on `refs/heads/main`, split into four cache groups with current-week and previous-week entries.

## 8. Related Specifications / Further Reading

- [docs/openwrt-firmware-performance-stability-plan.md](../docs/openwrt-firmware-performance-stability-plan.md)
- [docs/firmware-ci-prd.md](../docs/firmware-ci-prd.md)
- [docs/ci-workflow-architecture.md](../docs/ci-workflow-architecture.md)
- [docs/codebase/ARCHITECTURE.md](../docs/codebase/ARCHITECTURE.md)
- [docs/codebase/CONCERNS.md](../docs/codebase/CONCERNS.md)

## 9. Execution Order

1. Completed TASK-022 and TASK-025 by verifying Firmware CI run `26763561699` on commit `c4577fbfced2d800fd6192954fac4a96d78305ec`.
2. Completed TASK-023 by verifying Cache Maintenance dry-run `26762407724`; do not delete caches unless the user explicitly approves a real cleanup with a concrete `ref` or `prefix`.
3. Completed TASK-015 by confirming current x86 config-audit artifacts enforce Samba4/autosamba exclusion, performance overlay presence, BBR, SQM, CAKE, and x86 hardware checks.
4. Completed TASK-028 by reviewing successful x86 `firmware-size-report.md` outputs and preserving all required plugins.
5. Completed TASK-029 and TASK-030 by documenting the cache cadence, confirming profiles still follow upstream, and keeping branch cleanup after `main` merge.
6. Completed TASK-024 by marking this plan `Completed`; merge into `main` can be considered after this plan evidence commit is pushed.

## 10. Evidence Log

| Evidence | Result | Date |
|----------|--------|------|
| Local validators: `test-smoke-x86.sh`, `test-config-audit.sh`, `validate-profiles.sh`, `test-artifacts-release.sh`, `test-optimization-report.sh`, and shell syntax checks | Passed after gzip warning handling change. | 2026-06-01 |
| Optimization Health run `26744975093` on branch `codex-openwrt-optimization-execution` | Successful on commit `dc2ff87`. | 2026-06-01 |
| Firmware CI run `26746273479` on branch `codex-openwrt-optimization-execution` | `x86_64_immortalWrt` succeeded; `x86_64_LEDE` compile succeeded but smoke failed due to gzip warning exit code `2`. | 2026-06-01 |
| Gzip warning fix commit `447f449` | Implemented non-fatal handling for confirmed gzip trailing-data warnings in x86 smoke validation. | 2026-06-01 |
| Cache maintenance run `26761013711` | Workflow succeeded but reported `Matched caches: 0`; this does not match the live cache inventory and keeps TASK-011 open. | 2026-06-01 |
| Live cache inventory from `scripts/ci/optimization-report.sh cache yyg20101/OpenWrt-firmware` | Reported eight caches on `refs/heads/main`, about `5095.58 MiB` total, with four previous-week caches expected as cleanup candidates when `keep_latest=1`. | 2026-06-01 |
| Direct GitHub cache API check | `GET /repos/yyg20101/OpenWrt-firmware/actions/caches?ref=refs/heads/main` returned eight caches; `ref=main` returned zero, confirming the maintenance workflow must preserve the full ref string. | 2026-06-01 |
| Cache maintenance workflow local validation | `.github/workflows/cache-maintenance.yml` now uses explicit REST pagination through `github.request("GET /repos/{owner}/{repo}/actions/caches", ...)`; `scripts/ci/validate-cache-maintenance.sh` prevents returning to `getActionsCacheList`. | 2026-06-01 |
| Cache maintenance dry-run `26762407724` | Successful on commit `8092f61`; log reported `Matched caches: 8`, `Matched cache groups: 4`, `Cleanup candidates: 4`, and listed only `Would delete` entries for the four `2026-21` caches. | 2026-06-01 |
| Artifact and provenance enhancement local validation | `test-artifacts-release.sh`, `test-config-feeds.sh`, workflow YAML parsing, shell syntax checks, `test-config-audit.sh`, `test-smoke-x86.sh`, `test-optimization-report.sh`, `validate-profiles.sh`, `validate-cache-maintenance.sh`, and `validate-release-maintenance.sh` passed after adding `firmware-size-report.md`, local overlay script provenance, and build environment provenance. | 2026-06-01 |
| Firmware CI run `26763561699` | Successful on branch `codex-openwrt-optimization-execution`, commit `c4577fbfced2d800fd6192954fac4a96d78305ec`; jobs `x86_64_LEDE` and `x86_64_immortalWrt` both completed with conclusion `success`. | 2026-06-02 |
| Firmware CI run `26763561699` artifact inventory | Produced all expected x86 artifacts: `config-audit-x86_64_LEDE-26763561699`, `config-audit-x86_64_immortalWrt-26763561699`, `compile-log-x86_64_LEDE-26763561699`, `compile-log-x86_64_immortalWrt-26763561699`, `firmware-x86_64_LEDE-26763561699`, `firmware-x86_64_immortalWrt-26763561699`, `smoke-x86-x86_64_LEDE-26763561699`, and `smoke-x86-x86_64_immortalWrt-26763561699`. | 2026-06-02 |
| Firmware CI run `26763561699` downloaded artifact verification | Downloaded to `/private/tmp/openwrt-artifacts-26763561699`; both firmware artifacts include `build.config`, `artifact-manifest.txt`, `firmware-size-report.md`, `build-environment-provenance.md`, `package-source-manifest.tsv`, `Packages.tar.gz`, raw compressed x86 images, and `sha256sums.txt`; `shasum -a 256 -c sha256sums.txt` passed for both profiles. | 2026-06-02 |
| Firmware CI run `26763561699` x86 smoke verification | Both smoke artifacts include `summary.txt`, `partition-table.txt`, `qemu.log`, and `image.raw`; both summaries report `Boot status: boot-visible` and `Static checks: passed`. LEDE reported the known gzip warning classification; ImmortalWrt reported no gzip warning. | 2026-06-02 |
| Firmware CI run `26763561699` config audit verification | Both x86 config-audit summaries report `Samba4: y`, `autosamba: n`, `Performance defaults overlay: present`, `TCP BBR: y`, `SQM scripts: y`, and `CAKE scheduler: y`. | 2026-06-02 |

## 11. OpenWrt 固件性能与稳定性优化实施计划

本节是给人工执行和复盘使用的完整中文路线图。执行时以第 2 节任务表为准，状态变更必须同步回任务表和第 10 节证据日志。

| 阶段 | 目标 | 关键动作 | 验收标准 | 当前状态 |
|------|------|----------|----------|----------|
| P0: x86 稳定生成 | 先保障 `x86_64_LEDE` 和 `x86_64_immortalWrt` 稳定产出。 | 跟踪 run `26763561699`；验证 firmware、compile-log、config-audit、smoke 四类 artifact；失败时基于失败日志修复并重新触发 `x86_64_all`。 | 两个 x86 profile 均成功，且 artifact 内含 raw compressed image、`Packages.tar.gz`、`firmware-size-report.md`、provenance、`sha256sums.txt` 和 smoke 报告。 | 已完成 |
| P1: 配置守护 | 让必要插件、启动能力和性能能力变成可审计约束。 | 保持 `devices/profiles.yml` 跟上游分支；继续维护 `scripts/common/config/*.config` 分层；在 `scripts/ci/audit-config.sh` 中守护 Samba4/autosamba 互斥、x86 boot、性能包和 overlay。 | 新增性能默认值或关键插件时，本地 `test-config-audit.sh` 必须覆盖；不能通过移除必要插件解决构建问题。 | 已完成 |
| P2: 构建加速 | 提升复用率并降低 cache 容量风险。 | 保持 cache key 按 cache 类型、版本、source slug、source branch、cache group 和周序隔离；每周先 dry-run；真实删除必须有用户确认和 `ref` 或 `prefix`。 | Cache Health 能展示命中、体积、最近访问时间；dry-run 能列出候选但不会误删当前周或跨组最新缓存。 | 已完成 |
| P3: 产物可观测 | 让每个成功或失败的构建都能复盘。 | 保留 compile log、failure context、firmware size report、package overlay provenance、build environment provenance 和 artifact manifest。 | 成功构建可以判断固件体积、包来源、runner 环境和镜像完整性；失败构建可以定位到包、下载、磁盘、内存或工具链阶段。 | 已完成 |
| P4: 运行时性能 | 在不破坏用户网络的前提下提升默认性能。 | 保持 BBR、fq_codel、TCP Fast Open、MTU probing、backlog、TCP buffer、irqbalance、microcode、virtio、常见 x86 NIC、SQM/CAKE/IFB 等配置。 | 默认值保守，不强制启用会改变用户拓扑的流控策略；缺失 overlay 或关键包时配置审计失败。 | 已实现基础能力 |
| P5: 扩展到 Qualcommax | x86 通过后再扩大验证范围。 | 触发 `qualcommax_all`，复用 x86 的 cache、audit、size、provenance 和 failure-context 机制；记录 rootfs 压力和上游包变更。 | Qualcommax profile 失败时有足够证据判断是上游、包 overlay、rootfs、配置还是 runner 问题。 | 后续执行 |
| P6: 合入与清理 | 主分支只接收可证明稳定的优化结果。 | 完成实现提交的 x86 证明、cache dry-run 证据、local validators、profile upstream-following 检查，再合入 `main`；合入后清理旧分支。 | `main` 拥有最新计划证据和稳定构建链路；旧分支只在确认不再需要后删除。 | 已完成 |

### 11.1 Completion Audit

1. Cache redundancy is confirmed: eight caches exist on `refs/heads/main`, grouped into four cache prefix groups with current-week `2026-22` and previous-week `2026-21` entries.
2. Cache cleanup behavior is confirmed dry-run only: run `26762407724` matched eight caches, four groups, and four previous-week cleanup candidates; no cache was deleted.
3. x86 firmware generation is confirmed: Firmware CI run `26763561699` completed successfully for `x86_64_LEDE` and `x86_64_immortalWrt`.
4. x86 artifacts are confirmed by file-level checks: both profiles include firmware metadata, size reports, provenance reports, package archives, compressed x86 images, sha256 files, compile logs, config audits, and smoke reports.
5. Required plugin and performance constraints are confirmed by config-audit artifacts: Samba4 is enabled, `autosamba` is disabled, and BBR/SQM/CAKE/performance overlay checks pass.
6. Profile upstream-following behavior remains intact: this plan does not pin `devices/profiles.yml` source branches and keeps upstream-following as a requirement.
