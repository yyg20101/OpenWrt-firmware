---
goal: OpenWrt firmware performance and stability optimization
version: 1.5
date_created: 2026-06-01
last_updated: 2026-06-06
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

2026-06-06 current baseline update: the follow-up cache, LuCI, PassWall, x86 validation, merge, and branch cleanup work has been completed on `main`. Current proof includes successful x86 branch run `27031596559`, successful main run `27041924279`, monthly cache-period keys, matched-key-only cache saves, official LuCI Simplified Chinese language selection, official PassWall latest-tag overlay, Samba4/autosamba exclusion, and clean local/remote branch cleanup. The ongoing plan below now acts as the operating checklist for future firmware configuration, performance, and stability work.

2026-06-06 plan update: section 12 records the complete executable implementation plan for the next optimization round. It preserves upstream-following profiles, required plugins, official LuCI behavior, dry-run-first cache maintenance, x86-first proof, and artifact-level validation.

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

本节是给人工执行和复盘使用的当前中文路线图。历史实现任务仍以第 2 节任务表和第 10 节证据日志为准；从 2026-06-06 起，本节作为后续配置整理、性能优化、稳定构建和产物验收的主计划。

| 阶段 | 目标 | 关键动作 | 验收标准 | 当前状态 |
|------|------|----------|----------|----------|
| P0: Profile 与上游基线 | profile 继续跟随上游，同时让上游变化可追踪。 | 保持 `devices/profiles.yml` 的 `source_branch` 不 pin；不使用本地 `feeds_conf` 覆盖；通过 Optimization Health 输出 source repo、branch、remote HEAD、profile hash 和 cache group。 | 每个 enabled profile 能追溯 source repo、source branch、source commit、config fragments 和 cache group；上游漂移不会静默发生。 | 已实施，持续执行 |
| P1: 官方默认配置优先 | 对比上游默认配置，减少本地强行硬编码。 | 审计 OpenWrt/ImmortalWrt/LEDE 上游 `feeds.conf.default`、LuCI、uHTTPd、rpcd、x86 image 和 package 默认依赖；本地只保留必要能力选择与构建产物约束。 | LuCI 语言只使用 `CONFIG_LUCI_LANG_zh_Hans=y`；LuCI runtime、主题、uHTTPd 和 rpcd 由官方依赖带出；本地硬编码都有明确理由。 | 进行中 |
| P2: 固件配置守护 | 把必要插件、启动能力、LuCI 中文、Samba4 和 PassWall 变成可审计约束。 | 保持 `scripts/common/config/*.config` 分层；Samba4 启用且 autosamba 禁用；PassWall 清理冲突目录并拉取最新官方 tag；source-specific 插件只放对应片段；审计 defconfig-expanded 结果；不再维护固定插件 overlay 白名单。 | `test-config-audit.sh`、`validate-luci-zh-cn-config.sh`、`validate-passwall-overlay.sh` 均通过；defconfig-expanded 结果包含请求的 LuCI app、LuCI i18n、uHTTPd、rpcd、主题、Samba4、BBR、SQM 和 CAKE。 | 已实施，持续守护 |
| P3: x86 稳定生成证明 | 先证明 x86 两个 profile 可以稳定产出。 | 触发 `Firmware CI` 的 `target=x86_64_all`；检查 `x86_64_LEDE` 和 `x86_64_immortalWrt` 的 compile、config audit、firmware artifact、smoke artifact。 | 两个 x86 job 均 success；artifact 包含 `build.config`、`artifact-manifest.txt`、`firmware-size-report.md`、`build-environment-provenance.md`、`package-source-manifest.tsv`、`Packages.tar.gz`、x86 image、`sha256sums.txt` 和 smoke summary。 | 已完成，branch run `27031596559` 与 main run `27041924279` 通过 |
| P4: 缓存复用与容量控制 | 降低 GitHub Actions cache 重复保存和容量超额风险。 | cache key 使用 monthly `cache_period`；restore prefix 只在同 source slug、branch、cache group 内 fallback；save 仅在 `cache-matched-key == ''` 时执行；维护 workflow 先 dry-run。 | Optimization Health 显示 cache count、size、prefix groups、last access；Cache Maintenance dry-run 能列出候选且不删除；无用户确认不执行真实删除。 | 已实施，持续观察 |
| P5: 运行时性能优化 | 使用保守默认值提升吞吐和响应，同时避免改变用户网络拓扑。 | 保持 BBR、fq_codel、TCP Fast Open、MTU probing、backlog、TCP buffer；启用 irqbalance、microcode、virtio、常见 x86 NIC、SQM、CAKE 和 IFB；不默认强制开启流控策略。 | 缺少 performance overlay 或关键性能包时配置审计失败；成功 artifact 能看到性能配置来源和固件体积压力。 | 已实施，后续按实测微调 |
| P6: 构建可观测与 provenance | 让成功和失败构建都能复盘。 | 保留 compile log、failure context、firmware size report、package source manifest、build environment provenance、release metadata 和 checksum。 | 失败时能定位下载、磁盘、内存、工具链或包编译阶段；成功时能校验产物完整性、包来源、runner 环境和固件大小。 | 已实施 |
| P7: Qualcommax 扩展 | x86 稳定后扩大验证范围。 | 触发 `qualcommax_all`；复用同一套 config audit、cache、artifact、failure context、size report 和 provenance 检查。 | 失败能归类为上游源码、包 overlay、rootfs 空间、runner 内存或本地配置问题；通过后再考虑 `target=all`。 | 后续执行 |
| P8: 固化运维节奏 | 把稳定生成变成可重复流程。 | 每次大改先跑本地 validators；再跑 Optimization Health；再跑 `x86_64_all`；容量紧张时先 Cache Maintenance dry-run；Release 前做 artifact/release 检查。 | 新增 profile、插件或性能配置时有固定验证链路；缓存清理和 Release 发布都有证据记录。 | 持续执行 |

### 11.1 Completion Audit

1. Profile upstream-following behavior remains intact: `devices/profiles.yml` keeps upstream branches and does not pin source commits.
2. Upstream LuCI/feed behavior is confirmed: enabled profiles use each source tree's official `feeds.conf.default`, and LuCI Simplified Chinese is selected through official `CONFIG_LUCI_LANG_zh_Hans=y`.
3. Local LuCI hard-coding has been reduced: `base.config` keeps `CONFIG_PACKAGE_luci=y` as the official collection selector and no longer forces LuCI runtime/library internals.
4. Samba4/autosamba policy is confirmed: Samba4 stays enabled, `autosamba` stays disabled, and config audit prevents coexistence.
5. PassWall overlay policy is confirmed: local/feed conflicts are cleaned, dependency packages use the official packages repo, and `luci-app-passwall` uses the latest official tag policy.
6. Cache redundancy mitigation is confirmed: workflow cache keys use monthly `cache_period`; save steps require empty `cache-matched-key`, so fallback cache restores do not create duplicate saves.
7. Cache cleanup behavior remains dry-run-first: real deletion is not part of normal optimization and requires explicit user approval plus concrete `ref` or `prefix`.
8. x86 firmware generation is confirmed on branch run `27031596559` and main run `27041924279`; both `x86_64_LEDE` and `x86_64_immortalWrt` succeeded.
9. x86 artifacts are confirmed by file-level checks: both profiles include firmware metadata, size reports, provenance reports, package archives, compressed x86 images, sha256 files, compile logs, config audits, and smoke reports.
10. Required web, Samba, and performance constraints are confirmed by config-audit artifacts: LuCI Chinese, uHTTPd/rpcd, Samba4/autosamba, BBR/SQM/CAKE, and performance overlay checks pass. Requested LuCI application presence is guarded by requested-vs-effective config audit; the fixed plugin overlay whitelist has been removed so future plugin additions do not require a second policy list.

### 11.2 执行清单

| Step | Command or Check | Expected Result |
|------|------------------|-----------------|
| CHECK-001 | `bash scripts/ci/validate-cache-key-policy.sh` | cache period、matched-key save policy 和隔离边界有效。 |
| CHECK-002 | `bash scripts/ci/validate-luci-zh-cn-config.sh` | enabled profiles 都包含 LuCI 中文片段，且没有 local feeds override 或 per-plugin i18n 硬编码。 |
| CHECK-003 | `bash scripts/ci/validate-passwall-overlay.sh` | PassWall 主应用使用 latest-tag-required，依赖包使用官方 packages 仓。 |
| CHECK-003B | config-audit artifact `missing-luci-apps.txt` | 请求的 LuCI app 在 defconfig 后未丢失；PassWall 全固件覆盖由 `validate-passwall-overlay.sh` 守护。 |
| CHECK-004 | `bash scripts/ci/validate-profiles.sh` | profile matrix、config paths、config fragments 和 upstream-following branch 配置有效。 |
| CHECK-005 | `bash scripts/ci/test-config-audit.sh` | 请求的 LuCI app 不被 defconfig 丢弃；Samba4/autosamba、LuCI/uHTTPd/rpcd、BBR/SQM/CAKE、x86 boot 和 overlay 审计通过。 |
| CHECK-006 | `bash scripts/ci/test-config-feeds.sh` | config fragment、files overlay 和 package overlay 加载行为符合预期。 |
| CHECK-007 | `bash scripts/ci/test-artifacts-release.sh` and `bash scripts/ci/test-smoke-x86.sh` | artifact/release 规则和 x86 smoke fixture 通过。 |
| CHECK-008 | `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"` | workflow YAML 均可解析。 |
| CHECK-009 | `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n` | shell 脚本语法通过。 |
| CHECK-010 | `gh workflow run optimization-health.yml --repo yyg20101/OpenWrt-firmware --ref main` | profile、matrix、cache health 报告成功生成。 |
| CHECK-011 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=x86_64_all -f release=false` | main 分支两个 x86 profile 均构建成功。 |
| CHECK-012 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=qualcommax_all -f release=false` | x86 稳定后扩展到 Qualcommax，并保留失败诊断 artifact。 |

### 11.3 配置整理原则

- **CFG-001**: 优先查看上游源码默认配置和包依赖链，再决定是否保留本地配置。
- **CFG-002**: 本地配置只承担三类职责：选择用户必要插件、固定目标产物形态、守护已验证的性能和稳定性能力。
- **CFG-003**: 不把官方元包已经提供的依赖拆成一堆本地硬编码；例如 LuCI theme、uHTTPd、rpcd 和 i18n 默认应由官方 LuCI feed 提供。
- **CFG-004**: 不能通过移除必要插件解决 rootfs、编译耗时或依赖冲突；优先使用分层配置、rootfs/size 报告、失败上下文和上游来源追踪。
- **CFG-005**: x86 image、rootfs partsize、GRUB/EFI、VM-only image 裁剪属于产物约束，可以本地保留，但要由审计和 artifact 证明。
- **CFG-006**: `CONFIG_DEVEL`、`CONFIG_CCACHE`、initramfs、多 profile、per-device rootfs 等构建期配置需要逐项标注用途，避免无证据的强制开关。
- **CFG-007**: Broad hardware support 片段必须按设备族归档，后续新增设备优先新增 profile-specific fragment，而不是把所有能力继续堆进 base。

### 11.4 性能与稳定性验收重点

- **AC-001**: `build.config` 中能看到 `CONFIG_LUCI_LANG_zh_Hans=y`，defconfig-expanded audit 中能看到 `CONFIG_PACKAGE_luci-i18n-base-zh-cn=y`。
- **AC-002**: `CONFIG_PACKAGE_samba4-server=y`，`CONFIG_PACKAGE_autosamba` 不启用。
- **AC-003**: BBR、SQM scripts、CAKE scheduler、IFB 和 performance defaults overlay 均通过 config audit。
- **AC-004**: x86 artifact 至少包含一个 raw compressed image，并且 `shasum -a 256 -c sha256sums.txt` 通过。
- **AC-005**: smoke summary 显示 static checks 通过，并能看到 boot-visible 或明确的早期启动证据。
- **AC-006**: `package-source-manifest.tsv` 能追溯 PassWall 官方仓库、ref/tag 和 commit。
- **AC-007**: cache log 显示 cache period、matched key、save policy；fallback 命中时不会因为 primary key 不同而保存重复 cache。
- **AC-008**: Cache Maintenance 真实删除保持挂起，直到用户基于 dry-run 输出批准具体 `ref` 或 `prefix`。
- **AC-009**: main 分支构建产物包含 `build.config`、`artifact-manifest.txt`、`firmware-size-report.md`、`build-environment-provenance.md`、`Packages.tar.gz` 和 checksum。

### 11.5 后续优化方向

- **NEXT-001**: 完成一次上游默认配置对比审计，优先清理重复片段和无证据硬编码，尤其是 `base.config` 与 source-specific extra fragment 的重复项。
- **NEXT-002**: 在 `qualcommax_all` 首次证明后，按 profile 记录 rootfs 压力和编译失败包，必要时拆分 profile-specific size tuning。
- **NEXT-003**: 对 PassWall 及代理依赖增加更细的 artifact provenance 摘要，方便判断失败来自主应用 tag、依赖包仓、feeds 冲突还是上游源码变更。
- **NEXT-004**: 观察 main 分支第一轮 monthly cache 行为；如 fallback 一直命中过旧 weekly cache，再由用户确认是否按 dry-run 候选清理旧缓存。
- **NEXT-005**: 若 runner 内存成为瓶颈，优先调整 `make_compile_jobs` 和 fallback 策略，再考虑 profile 级别 rootfs/镜像大小参数。
- **NEXT-006**: Release 前新增一次 `optimization-report.sh release <repo> <tag>` 复核，确保 `Packages.tar.gz` 保留、VM-only 镜像排除、checksum 和 manifest 齐全。

### 11.6 上游默认配置对比记录

| Area | Upstream Evidence | Local Decision | Status |
|------|-------------------|----------------|--------|
| Feeds | `coolsnowwolf/lede` uses the official coolsnowwolf LuCI feed; ImmortalWrt-family sources use the official ImmortalWrt LuCI feed; enabled profiles do not set `feeds_conf`. | Keep upstream `feeds.conf.default`; do not add local feed overrides. | 已确认 |
| LuCI language | Active LuCI feeds expose `CONFIG_LUCI_LANG_zh_Hans` and generate `zh-cn` i18n packages from the official LuCI language mechanism. | Keep only `scripts/common/config/luci-zh-cn.config` with `CONFIG_LUCI_LANG_zh_Hans=y`; do not hard-code per-plugin i18n packages. | 已实施 |
| LuCI runtime, theme, uHTTPd, rpcd | Official LuCI collections provide default theme, uHTTPd, uHTTPd ubus, and rpcd dependencies through package metadata and post-install behavior. | Keep `CONFIG_PACKAGE_luci=y`; do not force local LuCI runtime/library internals; verify expanded result through config audit. | 已实施 |
| Samba | Upstream feeds may provide `autosamba`, and Samba4/autosamba can conflict on block hotplug paths. | Keep `luci-app-samba4` only in `samba.config`; keep `autosamba` disabled there; remove duplicate Samba declarations from other fragments. | 已整理 |
| Source-specific plugins | `luci-app-openvpn` exists in the checked LEDE LuCI feed but not in the checked ImmortalWrt LuCI feed. Several LEDE-oriented selections are intentionally carried in `lede-extra.config`. | Keep OpenVPN and LEDE-only apps in `lede-extra.config`; do not request them from non-LEDE profiles. | 已实施 |
| Third-party plugin overlays | Verified selected third-party repositories expose package Makefiles for GecoOS AC, mini-diskmanager, partexp, wolplus, and LEDE-only mwan3helper. `luci-app-alist` has been intentionally removed. | Overlay selected shared apps for supported source trees; overlay mwan3helper only for LEDE; audit requested apps after defconfig. | 已实施，待新 x86 产物证明 |
| ImmortalWrt extra fragment | Historical ImmortalWrt extra selections duplicated packages already selected by shared `base.config`, `network-performance.config`, `proxy.config`, and `samba.config`. | Keep `immortalwrt-extra.config` as an empty source-specific extension point; do not duplicate shared required plugin selections. | 已整理 |
| x86 images | ImmortalWrt defaults GRUB/EFI images on for x86; LEDE defaults differ, and x86 image Makefiles generate raw, EFI, and VM formats according to config. | Keep local x86 image/partsize and VM-format pruning as product artifact constraints; verify raw image and checksum in artifacts. | 已确认 |
| Build acceleration | Upstream `CONFIG_DEVEL` gates `CONFIG_CCACHE`; these are build-time options, not firmware runtime packages. | Keep `CONFIG_DEVEL=y` and `CONFIG_CCACHE=y` as CI build acceleration inputs, paired with Actions cache policy and local validators. | 已确认 |
| Initramfs and multi-profile | Upstream image logic changes artifact shape when initramfs, multi-profile, or per-device rootfs are enabled. | Keep explicit single-device/rootfs artifact guardrails in `base.config` because CI expects one declared profile and complete firmware artifacts. | 已确认 |

### 11.7 2026-06-06 配置整理验证记录

| Evidence | Result |
|----------|--------|
| Upstream source refresh | `/private/tmp/openwrt-upstream-config-audit/{lede,immortalwrt,viking,libwrt}` all reported `Already up to date`; `git fetch origin main` completed. |
| Config fragment cleanup | Removed duplicate `CONFIG_PACKAGE_luci-app-samba4` from `base.config`; removed duplicate `autosamba` guard from `lede-extra.config`; changed `immortalwrt-extra.config` into an empty source-specific extension point because its package selections duplicate shared fragments. |
| Required plugin static audit | All five enabled profiles still include LuCI, PassWall, HomeProxy, Samba4, WireGuard, LuCI Chinese, BBR, SQM, and CAKE through their combined device config and shared fragments. |
| Local validators | Passed `validate-profiles.sh`, `validate-luci-zh-cn-config.sh`, `validate-passwall-overlay.sh`, `test-config-audit.sh`, `test-config-feeds.sh`, `test-artifacts-release.sh`, `test-smoke-x86.sh`, `validate-cache-key-policy.sh`, `validate-cache-maintenance.sh`, `test-optimization-report.sh`, workflow YAML parsing, shell syntax checks, and `git diff --check`. |
| GitHub Actions final x86 run | `Firmware CI` run `27050273854` on `main`, commit `7a21daeddc8aa0391e7703473708b5f661e56296`, target `x86_64_all`, `release=false`, completed with conclusion `success`; both `x86_64_LEDE` and `x86_64_immortalWrt` jobs completed successfully. |
| Artifact download and firmware checksum verification | Downloaded artifacts to `/private/tmp/openwrt-artifacts-27050273854`; both firmware artifacts include `build.config`, `artifact-manifest.txt`, `firmware-size-report.md`, `build-environment-provenance.md`, `package-source-manifest.tsv`, `Packages.tar.gz`, x86 compressed images, and `sha256sums.txt`; `shasum -a 256 -c sha256sums.txt` passed for both profiles. |
| Smoke artifact verification | Both smoke summaries report `Boot status: boot-visible` and `Static checks: passed`; LEDE has the known classified gzip trailing-data warning, and ImmortalWrt reports `Gzip warning: none`. |
| Config-audit artifact verification | Both x86 config-audit summaries confirm `Samba4: y`, `autosamba: n`, `WireGuard kmod: y`, `TCP BBR: y`, `SQM scripts: y`, `CAKE scheduler: y`, `Performance defaults overlay: present`, `LuCI language zh_Hans: y`, `LuCI base zh-cn: y`, `LuCI bootstrap theme: y`, `uHTTPd: y`, `uHTTPd ubus: y`, and `rpcd luci: y`. |
| Requested plugin audit gap | A stricter requested-vs-effective comparison after run `27050273854` found several requested LuCI apps missing from effective config. This round adds third-party overlays and audit rules; the next x86 run must prove `missing-luci-apps.txt` is empty. |

## 12. 完整实施计划：OpenWrt 固件性能与稳定性优化

本节是后续实施的主计划。执行目标是在不移除个人必要插件的前提下，让 `x86_64_LEDE` 与 `x86_64_immortalWrt` 稳定生成可校验固件，并把同一套审计、缓存、产物和失败诊断机制扩展到 Qualcommax。

### 12.1 不可变约束

- **LOCK-001**: `devices/profiles.yml` 的 profile 必须继续跟随上游 `source_branch`；禁止为了稳定构建而 pin 到固定 commit。
- **LOCK-002**: 必要插件不能移除；包括 LuCI、PassWall、HomeProxy、Samba4、WireGuard、BBR、SQM、CAKE、LuCI 中文等现有必需能力。
- **LOCK-003**: LuCI、主题、中文、uHTTPd、rpcd 优先使用上游官方 feed 和官方元包依赖；本地只保留 `CONFIG_PACKAGE_luci=y` 与 `CONFIG_LUCI_LANG_zh_Hans=y` 这类必要选择。
- **LOCK-004**: Samba4 与 autosamba 不共存；保留 Samba4，禁用 autosamba。
- **LOCK-005**: OpenVPN 和 LEDE-only 插件只保留在 LEDE 配置片段；非 LEDE profile 不强制请求。
- **LOCK-006**: PassWall 是所有固件必需插件，必须继续使用官方 PassWall 依赖仓和应用仓 overlay。
- **LOCK-007**: GitHub Actions Cache 不直接删除；必须先 dry-run，且真实删除必须有用户明确批准和具体 `ref` 或 `prefix`。
- **LOCK-008**: 每次配置、缓存、workflow 或 package overlay 改动后，必须先验证 x86 两个 profile，再考虑 Qualcommax 或 `all`。

### 12.2 阶段计划

| Phase | Goal | Scope | Required Output | Status |
|-------|------|-------|-----------------|--------|
| PLAN-P0 | 固化基线 | 确认 `main`、上游源码、profile、config fragments、cache policy 和最新 CI run 状态。 | 当前 commit、profile matrix、上游 HEAD、cache inventory、run URL。 | 持续执行 |
| PLAN-P1 | 上游默认配置审计 | 对比 OpenWrt/LEDE/ImmortalWrt 默认 feeds、LuCI、x86 image、build acceleration、initramfs 和 rootfs 行为。 | 记录哪些配置来自官方默认，哪些必须本地保留。 | 持续执行 |
| PLAN-P2 | 配置片段去重与收敛 | 清理 `scripts/common/config/*.config` 中重复、过度硬编码、source-specific 重复项。 | 片段职责清晰：base、LuCI 中文、proxy、Samba、performance、x86、平台 extra。 | 已开始 |
| PLAN-P3 | 必要插件守护 | 把必要插件变成静态检查和 defconfig-expanded 审计约束。 | local validators 和 config-audit artifact 均证明插件未丢失。 | 持续执行 |
| PLAN-P4 | 性能配置保守优化 | 保留 BBR、fq_codel、TCP Fast Open、MTU probing、SQM、CAKE、IFB、irqbalance、microcode、virtio 和常见 x86 NIC。 | 性能能力存在但不强制改变用户实际网络策略。 | 已实施，后续微调 |
| PLAN-P5 | 构建缓存复用优化 | 观察 monthly cache key、matched-key-only save、source/branch/cache group 隔离和 dry-run cleanup。 | cache 复用可解释，容量增长可控，不跨上游污染。 | 已实施，持续观察 |
| PLAN-P6 | x86 产物稳定证明 | 触发 `target=x86_64_all`，验证 compile、config audit、firmware artifact、smoke artifact。 | 两个 x86 profile 均 success；checksum、manifest、size、provenance、smoke 全部可查。 | 每轮大改必跑 |
| PLAN-P7 | Qualcommax 扩展 | 在 x86 稳定后触发 `target=qualcommax_all`，沿用同样审计和产物标准。 | 失败可归因；成功后再考虑 `target=all`。 | 待执行 |
| PLAN-P8 | Release 前验收 | 发布前复核 artifact、release assets、Packages.tar.gz、VM-only 排除、checksum、manifest。 | release 产物完整且可追溯。 | 发布前执行 |

### 12.3 具体任务清单

| Task | File or Command | Action | Acceptance |
|------|-----------------|--------|------------|
| IMPL-001 | `git status --short --branch` | 每次实施前确认本地分支、远端同步和未提交改动。 | `main...origin/main` 清晰；如有未提交改动，先判断是否属于本次任务。 |
| IMPL-002 | `devices/profiles.yml` | 审查 enabled profiles 的 `source_repo`、`source_branch`、`cache_group`、`make_compile_jobs`、`config_fragments`。 | `source_branch` 跟随上游；所有 config fragment 路径存在；x86 cache group 隔离正确。 |
| IMPL-003 | 上游源码目录 `/private/tmp/openwrt-upstream-config-audit/*` | 刷新并检查上游默认 `feeds.conf.default`、LuCI package metadata、x86 target defaults。 | 本地新增配置必须能说明是必要插件、产物约束、性能守护或 CI 加速。 |
| IMPL-004 | `scripts/common/config/base.config` | 只保留全局基础能力和必要元包；避免重复选择 Samba、proxy、platform-specific 包。 | Samba 不在 base 重复声明；LuCI 使用 `CONFIG_PACKAGE_luci=y`。 |
| IMPL-005 | `scripts/common/config/luci-zh-cn.config` | 保持官方语言选择 `CONFIG_LUCI_LANG_zh_Hans=y`。 | 不硬编码 `luci-i18n-*-zh-cn` per-plugin 包。 |
| IMPL-006 | `scripts/common/config/samba.config` | 集中管理 Samba4/autosamba 策略。 | `CONFIG_PACKAGE_luci-app-samba4=y`；`# CONFIG_PACKAGE_autosamba is not set`。 |
| IMPL-007 | `scripts/common/config/proxy.config` and `scripts/common/Packages.sh` | 保持 PassWall/HomeProxy 必要插件和官方 overlay 来源策略。 | `validate-passwall-overlay.sh` 通过；artifact provenance 可追溯 tag/ref/commit。 |
| IMPL-008 | `scripts/common/config/base.config`, `scripts/common/config/lede-extra.config`, `scripts/common/package` | 三方插件按当前请求选择 overlay，LEDE-only 插件只进入 LEDE 片段；OpenVPN 保持 LEDE-only；`luci-app-alist` 不再请求。 | `test-config-audit.sh` 通过；非 LEDE profile 不请求 OpenVPN；config-audit 证明请求的 LuCI app 未丢失。 |
| IMPL-009 | `scripts/common/config/network-performance.config` | 保留 BBR、SQM、CAKE、IFB、scheduler 支持。 | config audit 报告 `TCP BBR: y`、`SQM scripts: y`、`CAKE scheduler: y`。 |
| IMPL-010 | `scripts/common/config/x86.config` and `scripts/common/config/x86-performance.config` | 保留 x86 image、rootfs partsize、GRUB/EFI、virtio、microcode、irqbalance、常见 NIC。 | x86 artifact 有 raw compressed image；smoke static checks 通过。 |
| IMPL-011 | `files/etc/uci-defaults/99-performance-defaults` | 只写保守 sysctl 默认值，不自动启用用户未配置的限速或复杂策略。 | performance overlay 存在；缺失时 config audit 失败。 |
| IMPL-012 | `.github/workflows/firmware-build.yml` | 保持 cache key 隔离和 matched-key-only save 策略。 | `validate-cache-key-policy.sh` 通过；fallback 命中不重复保存 cache。 |
| IMPL-013 | `.github/workflows/cache-maintenance.yml` | 保持 dry-run-first 和真实删除保护。 | `validate-cache-maintenance.sh` 通过；无 `ref` 或 `prefix` 不允许真实删除。 |
| IMPL-014 | `scripts/ci/audit-config.sh` | 新增必要插件或性能配置时同步扩展审计。 | 请求的 LuCI app 缺失会 fail；上游可选驱动差异只 advisory。 |
| IMPL-015 | `scripts/ci/build-artifacts.sh` | 维持 compile log、failure context、size report、package source manifest、environment provenance。 | 成功和失败构建都能复盘。 |
| IMPL-016 | `scripts/ci/smoke-x86.sh` | 保持 gzip、partition、QEMU early boot 检查。 | smoke summary 出现 `Static checks: passed` 和 boot evidence。 |
| IMPL-017 | `plan/upgrade-openwrt-firmware-performance-stability-1.md` | 每轮关键优化后追加 evidence log。 | 记录 commit SHA、run URL、artifact 下载目录、验收结果。 |

### 12.4 本地验证顺序

| Step | Command | Pass Criteria |
|------|---------|---------------|
| VAL-001 | `bash scripts/ci/validate-profiles.sh` | profile matrix 与 config fragments 有效。 |
| VAL-002 | `bash scripts/ci/validate-luci-zh-cn-config.sh` | LuCI 中文策略符合官方语言选择。 |
| VAL-003 | `bash scripts/ci/validate-passwall-overlay.sh` | PassWall overlay 策略可追溯且无冲突。 |
| VAL-004 | `bash scripts/ci/test-config-audit.sh` | 请求的 LuCI app、LuCI 依赖、Samba4/autosamba、性能能力和 x86 guardrails 通过。 |
| VAL-005 | `bash scripts/ci/test-config-feeds.sh` | feeds、config fragments、files overlay、package overlay 加载行为正确。 |
| VAL-006 | `bash scripts/ci/test-artifacts-release.sh` | artifact 与 release packaging 规则通过。 |
| VAL-007 | `bash scripts/ci/test-smoke-x86.sh` | x86 smoke fixture 和 gzip warning 分类通过。 |
| VAL-008 | `bash scripts/ci/validate-cache-key-policy.sh` | cache period、fallback、save 条件和隔离边界有效。 |
| VAL-009 | `bash scripts/ci/validate-cache-maintenance.sh` | cache cleanup guardrails 有效。 |
| VAL-010 | `bash scripts/ci/test-optimization-report.sh` | profile、matrix、cache、summary、release report 行为通过。 |
| VAL-011 | `bash scripts/ci/validate-release-maintenance.sh` | release maintenance 约束通过。 |
| VAL-012 | `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"` | workflow YAML 均可解析。 |
| VAL-013 | `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n` | shell 脚本语法通过。 |
| VAL-014 | `git diff --check` | 无 whitespace error。 |

### 12.5 GitHub Actions 验证顺序

| Step | Command | Required Evidence |
|------|---------|-------------------|
| GHA-001 | `gh workflow run optimization-health.yml --repo yyg20101/OpenWrt-firmware --ref main` | profile drift、matrix、cache health 成功生成。 |
| GHA-002 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=x86_64_all -f release=false` | `x86_64_LEDE` 与 `x86_64_immortalWrt` 两个 job 均 success。 |
| GHA-003 | `gh run download <run_id> --repo yyg20101/OpenWrt-firmware --dir /private/tmp/openwrt-artifacts-<run_id>` | 下载 firmware、compile-log、config-audit、smoke artifacts。 |
| GHA-004 | 在每个 firmware artifact 目录运行 `shasum -a 256 -c sha256sums.txt` | checksum 全部通过。 |
| GHA-005 | 检查 config audit summary | `missing-luci-apps.txt` 为空；LuCI Chinese、uHTTPd、rpcd、theme、Samba4/autosamba、BBR、SQM、CAKE、performance overlay 全部符合预期。 |
| GHA-006 | 检查 smoke summary | `Static checks: passed`，并出现 `Boot status: boot-visible` 或等价早期启动证据。 |
| GHA-007 | `gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=qualcommax_all -f release=false` | x86 通过后再扩展；失败时下载 failure-context 并归因。 |
| GHA-008 | `gh workflow run cache-maintenance.yml --repo yyg20101/OpenWrt-firmware --ref main -f dry_run=true -f older_than_days=0 -f keep_latest=1 -f ref=refs/heads/main` | 只输出候选，不删除；如需真实删除，必须另行获得用户确认。 |

### 12.6 产物验收标准

- **ART-001**: firmware artifact 必须包含 `build.config`、`artifact-manifest.txt`、`firmware-size-report.md`、`build-environment-provenance.md`、`package-source-manifest.tsv`、`Packages.tar.gz`、x86 raw compressed image、`sha256sums.txt`。
- **ART-002**: compile-log artifact 必须包含可追踪的完整日志或失败尾部上下文。
- **ART-003**: config-audit artifact 必须包含 requested config、effective config、summary、`missing-luci-apps.txt` 和关键能力状态。
- **ART-004**: smoke artifact 必须包含 `summary.txt`、`partition-table.txt`、`qemu.log`、`image.raw` 或等价诊断文件。
- **ART-005**: release assets 必须保留 `Packages.tar.gz`，排除 VM-only image formats，并保留 checksum/manifest。
- **ART-006**: package source manifest 必须能追溯本地 overlay、PassWall、依赖包仓库、ref/tag 和 commit。

### 12.7 调优方向与实施边界

- **TUNE-001**: rootfs 压力优先通过 `firmware-size-report.md`、profile-specific fragment、partsize/image 参数或上游包来源处理；禁止第一反应移除必要插件。
- **TUNE-002**: 编译耗时优先通过 cache 命中率、`make_compile_jobs`、fallback jobs、ccache 状态和包失败定位处理。
- **TUNE-003**: 网络性能默认值只保持通用且保守的 kernel/sysctl 能力；SQM/CAKE 只提供能力，不预设用户具体限速。
- **TUNE-004**: x86 硬件支持保持物理机和虚拟机兼容；新增网卡或存储驱动应进入 x86/platform fragment，不进入全局 base。
- **TUNE-005**: LuCI 相关优化以官方元包依赖为准；只有 defconfig-expanded 缺失时才补本地 guardrail。
- **TUNE-006**: PassWall/HomeProxy 变更必须先看 upstream tag、feeds 冲突、package overlay provenance，再判断是否需要本地修复。

### 12.8 失败处理流程

1. 如果本地 validator 失败，先修复 validator 指出的文件；不要直接触发远程编译。
2. 如果 `Firmware CI` 配置阶段失败，下载 `config-audit-*` artifact，先检查 fragments、feeds、LuCI 中文、Samba4/autosamba 和 PassWall overlay。
3. 如果编译阶段失败，查看 `compile-log-*` 与 `failure-context-*`，归类为上游源码、feed 包、overlay 包、runner 资源、cache 污染或本地 config。
4. 如果 smoke 阶段失败，检查 gzip、partition、QEMU boot log；已知 harmless warning 必须精确匹配，未知 warning 保持失败。
5. 如果 cache 容量接近上限，先运行 Optimization Health 和 Cache Maintenance dry-run；只有用户确认后才执行真实删除。
6. 如果 Qualcommax 失败，不回滚 x86 已验证配置；先记录失败 profile、source commit、rootfs pressure、failed package，再决定是否拆分 platform fragment。

### 12.9 完成定义

- **DONE-001**: `main` 分支本地 validator 全部通过。
- **DONE-002**: `target=x86_64_all` 最新 GitHub Actions run 成功，两个 x86 profile 均有完整 artifact。
- **DONE-003**: firmware artifact checksum 通过，smoke summary 通过，config audit summary 通过。
- **DONE-004**: cache health 能解释当前缓存数量、大小、命中、fallback 和候选清理项。
- **DONE-005**: 计划文档记录最新 commit、run URL、artifact 验收路径和结论。
- **DONE-006**: 后续扩展到 Qualcommax 时，有同等 artifact 和 failure-context 证据。
