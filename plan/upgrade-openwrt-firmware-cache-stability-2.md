---
goal: OpenWrt firmware cache reuse, build performance, and stability hardening
version: 2.0
date_created: 2026-06-02
last_updated: 2026-06-03
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
- **SEC-001**: Workflow changes must not add new secrets, broaden token permissions beyond the existing need, or hide remote script and package overlay provenance.
- **CON-001**: Changes must stay compatible with the existing workflow split: `.github/workflows/firmware-ci.yml`, `.github/workflows/firmware-build.yml`, `.github/workflows/optimization-health.yml`, `.github/workflows/cache-maintenance.yml`, `.github/workflows/release-maintenance.yml`, and `.github/workflows/ci-lint.yml`.
- **CON-002**: `devices/profiles.yml` remains the single source of truth for profile matrix membership, source repository, source branch, config path, cache group, compile limits, and config fragments.
- **CON-003**: GitHub Actions cache entries are immutable after save. The cache strategy must account for immutable cache keys instead of assuming a stable key can be overwritten.
- **CON-004**: Live cache deletion is outside this implementation unless the user explicitly approves a deletion operation after reviewing dry-run output.
- **GUD-001**: Keep OpenWrt configuration split into base, network performance, storage, USB/mobile, proxy, Samba, x86, x86 performance, and platform-specific fragments.
- **GUD-002**: Prefer workflow policy validation in `scripts/ci/` so cache behavior regressions are caught by `ci-lint.yml`.
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

### Implementation Phase 5

- GOAL-005: Prove the optimized cache policy in GitHub Actions before merging.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-020 | Commit the cache policy, validator, and documentation changes on branch `codex/cache-stability-optimization`. |  |  |
| TASK-021 | Push branch `codex/cache-stability-optimization` to `origin`. |  |  |
| TASK-022 | Trigger `Optimization Health` on branch `codex/cache-stability-optimization` and record the run ID, commit SHA, and cache report result in this plan. |  |  |
| TASK-023 | Trigger `Firmware CI` with `target=x86_64_all`, `release=false`, and `make_latest=false` on branch `codex/cache-stability-optimization`; confirm both x86 profiles succeed. |  |  |
| TASK-024 | Download or inspect the x86 artifacts from TASK-023 and confirm both profiles include firmware, compile log, config audit, smoke report, size report, provenance, package archive, and checksum evidence. |  |  |
| TASK-025 | Run `Cache Maintenance` dry-run with `dry_run=true`, `older_than_days=0`, `keep_latest=1`, and `ref=refs/heads/main`; record matched cache count, matched group count, and cleanup candidate count in this plan. |  |  |

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
- **TEST-013**: Run `bash scripts/ci/optimization-report.sh cache yyg20101/OpenWrt-firmware`; expect live cache inventory, refs, prefix groups, sizes, and last-access timestamps to render.
- **TEST-014**: Trigger `Optimization Health` on branch `codex/cache-stability-optimization`; expect the workflow conclusion to be `success`.
- **TEST-015**: Trigger `Firmware CI` with `target=x86_64_all`, `release=false`, and `make_latest=false` on branch `codex/cache-stability-optimization`; expect both x86 jobs to conclude `success`.
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

## 11. Completion Criteria

- **DONE-001**: `.github/workflows/firmware-build.yml` uses `CACHE_PERIOD` and `cache_period`, not `CACHE_WEEK` or `cache_week`.
- **DONE-002**: ccache and build accelerator save steps use `cache-matched-key == ''` and do not use `cache-hit != 'true'`.
- **DONE-003**: Cache keys keep cache type, cache version, source slug, repo branch, cache group, and cache period.
- **DONE-004**: `scripts/ci/validate-cache-key-policy.sh` exists and is executed by `.github/workflows/ci-lint.yml`.
- **DONE-005**: Documentation describes period-based keys, fallback restore, matched-key save policy, and dry-run-first cleanup.
- **DONE-006**: Local validators TEST-001 through TEST-012 pass.
- **DONE-007**: Branch `codex/cache-stability-optimization` is pushed and GitHub Actions TEST-014 through TEST-016 pass.
- **DONE-008**: x86 artifacts from the implementation branch include firmware, compile logs, config audit, smoke reports, size reports, provenance, package archive, and checksum evidence.
- **DONE-009**: The implementation is fast-forward merged into `main` and `main` is pushed to `origin`.
- **DONE-010**: Obsolete local and remote implementation branches are deleted after merge.
- **DONE-011**: Final branch and worktree audit confirms `main` is clean, `HEAD` equals `origin/main`, and no obsolete implementation branch remains.
- **DONE-012**: This plan is updated to `Completed` only after DONE-001 through DONE-011 are satisfied.
