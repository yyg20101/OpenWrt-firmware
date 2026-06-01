---
goal: OpenWrt firmware performance and stability optimization
version: 1.0
date_created: 2026-06-01
last_updated: 2026-06-01
owner: wajie
status: In progress
tags:
  - openwrt
  - firmware
  - ci
  - performance
  - stability
---

# Introduction

![Status: In progress](https://img.shields.io/badge/status-In%20progress-yellow)

This plan records the execution path for improving OpenWrt firmware performance, build stability, and observability while preserving upstream-following profiles, required plugins, and x86 delivery as first-class constraints.

The current baseline already includes profile drift reporting, x86 smoke validation, failure-context artifacts, cache grouping, and layered config fragments. The remaining work is to finish x86 audit hardening, continue cache and compile tuning, and keep maintenance steps repeatable.

## 1. Requirements & Constraints

- **REQ-001**: `x86_64_LEDE` and `x86_64_immortalWrt` must remain the first stability targets.
- **REQ-002**: `source_branch` must continue to follow upstream branches; do not hard-pin profile branches to local commits.
- **REQ-003**: Required plugins must stay available; optimization may not remove user-required packages just to make builds pass.
- **REQ-004**: `Samba4` and `autosamba` do not need to coexist; `Samba4` is the preferred baseline and `autosamba` must remain disabled.
- **REQ-005**: Cache work must improve reuse, visibility, and cleanup boundaries, not just increase total cache size.
- **REQ-006**: Every build must retain configuration audit output, cache status, and failure-context artifacts.
- **SEC-001**: Remote bootstrap scripts and build environment sources must be logged so provenance can be traced.
- **CON-001**: All changes must remain compatible with the current GitHub Actions workflow structure and the profile matrix defined in `devices/profiles.yml`.
- **PAT-001**: Use config fragments to separate base, network, storage, x86, Samba, and platform-specific settings.

## 2. Implementation Steps

### Implementation Phase 1

- GOAL-001: Make x86 builds observable and prevent upstream-specific config variance from hiding real failures.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-001 | Add profile drift reporting in `scripts/ci/optimization-report.sh` and `.github/workflows/optimization-health.yml` so the report shows source repo, branch, remote HEAD, and last build commit. | ✅ | 2026-06-01 |
| TASK-002 | Add x86 smoke validation in `scripts/ci/smoke-x86.sh` and `.github/workflows/firmware-build.yml` to verify image integrity, partition recognition, and basic boot visibility. | ✅ | 2026-06-01 |
| TASK-003 | Capture failure context in `scripts/ci/build-artifacts.sh` and upload `failure-context-*` artifacts from `.github/workflows/firmware-build.yml`. | ✅ | 2026-06-01 |
| TASK-004 | Relax x86 virtio checks in `scripts/ci/audit-config.sh` and `scripts/ci/test-config-audit.sh` so advisory modules are reported but do not block valid upstream variants. | ✅ | 2026-06-01 |

### Implementation Phase 2

- GOAL-002: Improve cache reuse and compile throughput without crossing source or profile boundaries.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-005 | Keep cache keys grouped by source slug, branch, cache group, and cache week in `.github/workflows/firmware-build.yml`, and expose matched key and cache group summaries in `scripts/ci/optimization-report.sh`. | ✅ | 2026-06-01 |
| TASK-006 | Tune `make_compile_jobs` per profile in `devices/profiles.yml` and keep the fallback path in `scripts/ci/build-artifacts.sh` so memory-sensitive sources do not fail under parallel load. |  |  |
| TASK-007 | Preserve layered config fragments in `scripts/common/config/*.config` and `devices/profiles.yml` so performance capabilities remain traceable to a specific fragment. | ✅ | 2026-06-01 |
| TASK-008 | Keep cache maintenance reviewable through `.github/workflows/cache-maintenance.yml` and `scripts/ci/validate-cache-maintenance.sh`, with cleanup rules based on prefix or ref. | ✅ | 2026-06-01 |

### Implementation Phase 3

- GOAL-003: Lock in long-term maintenance, release hygiene, and regression detection.

| Task | Description | Completed | Date |
|------|-------------|-----------|------|
| TASK-009 | Keep release and artifact integrity checks in `scripts/ci/test-artifacts-release.sh`, `scripts/ci/validate-release-maintenance.sh`, and `.github/workflows/release-maintenance.yml`. | ✅ | 2026-06-01 |
| TASK-010 | Document the maintenance cadence and operating order in `docs/ci-workflow-architecture.md`, `docs/firmware-ci-prd.md`, and `README.md`. |  |  |
| TASK-011 | Re-run `Optimization Health`, then `Firmware CI` for `x86_64_all`, and record the result in the workflow outputs before widening to the other profile groups. |  |  |

## 3. Alternatives

- **ALT-001**: Pin each profile to a fixed upstream commit. Rejected because it breaks the requirement that profiles continue following upstream branches.
- **ALT-002**: Remove required plugins to lower rootfs pressure. Rejected because the plugins are part of the intended firmware capability set.
- **ALT-003**: Expand cache size without changing grouping. Rejected because the problem is reuse and boundary control, not only total capacity.

## 4. Dependencies

- **DEP-001**: GitHub Actions cache and artifact actions used by `.github/workflows/firmware-build.yml` and `.github/workflows/optimization-health.yml`.
- **DEP-002**: `gh` CLI with repository access for drift and cache reporting.
- **DEP-003**: `qemu-system-x86` and `qemu-utils` for x86 smoke validation.
- **DEP-004**: OpenWrt/ImmortalWrt build environment scripts and standard GNU build tooling.
- **DEP-005**: `ccache` for build acceleration and reuse analysis.

## 5. Files

- **FILE-001**: `plan/upgrade-openwrt-firmware-performance-stability-1.md`
- **FILE-002**: `devices/profiles.yml`
- **FILE-003**: `scripts/ci/optimization-report.sh`
- **FILE-004**: `scripts/ci/audit-config.sh`
- **FILE-005**: `scripts/ci/build-artifacts.sh`
- **FILE-006**: `scripts/ci/smoke-x86.sh`
- **FILE-007**: `scripts/ci/test-config-audit.sh`
- **FILE-008**: `.github/workflows/firmware-build.yml`
- **FILE-009**: `.github/workflows/optimization-health.yml`
- **FILE-010**: `.github/workflows/cache-maintenance.yml`
- **FILE-011**: `.github/workflows/release-maintenance.yml`
- **FILE-012**: `scripts/common/config/base.config`
- **FILE-013**: `scripts/common/config/network-performance.config`
- **FILE-014**: `scripts/common/config/storage.config`
- **FILE-015**: `scripts/common/config/x86-performance.config`
- **FILE-016**: `scripts/common/config/samba.config`
- **FILE-017**: `files/etc/uci-defaults/99-performance-defaults`

## 6. Testing

- `bash scripts/ci/test-config-audit.sh`: verify x86 audit rules, Samba4/autosamba mutual exclusion, and required package coverage.
- `bash scripts/ci/test-smoke-x86.sh`: verify x86 smoke fixture behavior and image validation logic.
- `bash scripts/ci/test-optimization-report.sh`: verify profile drift, cache, and release reporting output.
- `bash scripts/ci/test-artifacts-release.sh`: verify artifact packaging and release metadata rules.
- `bash scripts/ci/validate-profiles.sh`: verify the profile matrix and config fragment wiring.
- `bash scripts/ci/validate-cache-maintenance.sh`: verify cache cleanup guardrails.
- `bash scripts/ci/validate-release-maintenance.sh`: verify release maintenance constraints.
- `find scripts -type f -name '*.sh' -print0 | xargs -0 -n1 bash -n`: verify shell syntax across the CI helper scripts.
- `ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"`: verify workflow YAML validity.

## 7. Risks & Assumptions

- **RISK-001**: Upstream branches can change behavior without local changes, which may make identical profiles build differently over time. Mitigation: keep drift reporting and source commit evidence in build summaries.
- **RISK-002**: x86 audit rules can become too strict for one upstream and too loose for another. Mitigation: keep advisory modules in the summary and only hard-fail on invariant requirements.
- **RISK-003**: Aggressive cache cleanup can remove useful reuse and slow the next build. Mitigation: only clean within a well-defined prefix or ref boundary and preserve the newest entries.
- **ASSUMPTION-001**: `devices/profiles.yml` remains the single source of truth for the profile matrix and cache group boundaries.
- **ASSUMPTION-002**: QEMU smoke will stay a diagnostic gate until the x86 boot path is stable enough for a hard block.

## 8. Related Specifications / Further Reading

- [docs/firmware-ci-prd.md](../docs/firmware-ci-prd.md)
- [docs/ci-workflow-architecture.md](../docs/ci-workflow-architecture.md)
- [docs/openwrt-firmware-performance-stability-plan.md](../docs/openwrt-firmware-performance-stability-plan.md)
- [docs/codebase/ARCHITECTURE.md](../docs/codebase/ARCHITECTURE.md)
- [docs/codebase/CONCERNS.md](../docs/codebase/CONCERNS.md)
