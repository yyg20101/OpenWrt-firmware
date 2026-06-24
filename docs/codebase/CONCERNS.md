# Codebase Concerns

## Core Sections (Required)

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| High | Builds depend on mutable external sources: upstream repos, feeds, package repos, remote build environment script, and runner images. | `.github/workflows/firmware-build.yml`, `devices/profiles.yml`, `scripts/common/Packages.sh` | Builds may fail or produce different artifacts without local changes. | Pin more external refs; package overlay refs are now recorded when overlays run. |
| Medium | `target=all` can trigger all enabled profiles in parallel. | `.github/workflows/firmware-ci.yml`, `devices/profiles.yml` | Actions minutes, cache quota, and release volume can spike. | Use profile groups for routine builds; multi-profile releases no longer overwrite GitHub Latest. |
| Medium | Fixture tests still cover only selected shell module behavior. | `.github/workflows/ci-lint.yml`, `scripts/ci/*.sh` | Syntax/schema checks can pass while untested behavioral edge cases remain. | Extend fixtures to profile export and config fragment edge cases if those modules change further. |
| Medium | Fixed Release tags replace assets in place. | `.github/workflows/firmware-build.yml`, `scripts/ci/release-maintenance.sh` | A successful rebuild becomes the current published asset set for that profile/source/branch. | Keep source commit, profile hash, and workflow run in the Release body; validate release assets before treating a build as accepted. |

### 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Build environment is installed inline in workflow YAML. | Runner setup is tightly coupled to GitHub Actions. | `.github/workflows/firmware-build.yml` | Harder to test locally and slower to iterate. | Extract setup into a script if it grows further. |
| Package overlay helper performs live GitHub operations. | Firmware customization relies on latest package sources. | `scripts/common/Packages.sh` | Build reproducibility is limited. | Pin selected package refs if reproducible builds become more important than latest package behavior. |
| Compatibility wrapper `load-device-profile.sh` remains after profile refactor. | Existing script name is still convenient for workflow usage. | `scripts/ci/load-device-profile.sh` | Minor naming mismatch with the new profile model. | Rename in a future cleanup once callers are stable. |

### 3) Security Concerns

| Risk | OWASP category (if applicable) | Evidence | Current mitigation | Gap |
|------|--------------------------------|----------|--------------------|-----|
| Remote shell execution for build environment initialization. | N/A | `.github/workflows/firmware-build.yml` | Uses HTTPS to fetch the ImmortalWrt build environment script. | Script is not pinned by checksum or commit. |
| Public package repositories are cloned at build time. | N/A | `scripts/common/Packages.sh` | Repository names are validated before helper clone operations. | No signature/checksum validation of cloned package repos. |
| Repository dispatch can trigger firmware CI. | N/A | `.github/workflows/firmware-ci.yml` | Runs under GitHub permissions model and profile validation. | Trusted dispatch sources are not documented. |

### 4) Performance and Scaling Concerns

| Concern | Evidence | Current symptom | Scaling risk | Suggested improvement |
|---------|----------|-----------------|-------------|-----------------------|
| OpenWrt builds are compute/disk intensive. | `.github/workflows/firmware-build.yml` | Workflow maximizes build space and restores caches. | More profiles increase runtime and cache churn. | Monitor cache hit rate and add profile grouping if needed. |
| Network performance packages add footprint. | `scripts/common/config/network-performance.config` | BBR, SQM/CAKE, and IFB are enabled for all profiles. | Smaller flash targets may need a slimmer profile. | Keep the performance config as a separate fragment so low-storage devices can opt out. |
| Network-heavy package/feed operations are serial. | `.github/workflows/firmware-build.yml`, `scripts/common/Packages.sh` | Feeds and package overlays run during every build. | Network stalls can dominate runtime. | Retry/backoff is now applied to feeds and package overlay network calls; add timeout tuning if failures persist. |
| Manual cache deletion can remove useful accelerators if scoped too broadly. | `.github/workflows/cache-maintenance.yml` | Real deletion now requires `prefix` or `ref` and keeps two newest matches by default. | Wrong filter choices can still delete useful cache groups. | Run dry-run first and keep cache keys grouped by source/profile family. |

### 5) Fragile/High-Churn Areas

| Area | Why fragile | Churn signal | Safe change strategy |
|------|-------------|-------------|----------------------|
| `.github/workflows/firmware-build.yml` | Central build phase order, cache keys, artifact paths, and Release wiring live here. | Large workflow surface. | Keep step outputs explicit and run YAML/profile validation after edits. |
| `scripts/ci/profiles.sh` | Profile validation, matrix output, env/output contracts, and cache hash computation live here. | New central contract. | Test with single profile and `all` matrix before workflow changes. |
| `scripts/ci/config-feeds.sh` | Mutates the cloned OpenWrt tree. | Source/feeds layout can vary by upstream. | Keep path resolution explicit and fail on missing declared inputs. |
| `devices/profiles.yml` source branches | External repos can rename or remove branches. | `Qualcommax_B` tracks `LiBwrt/openwrt-6.x` `main-nss`, the current default branch. | Verify source branches before changing profile sources. |

### 6) `[ASK USER]` Questions

1. [ASK USER] Should repository dispatch be limited to specific automation sources, or is any caller with repo dispatch permission acceptable?
2. [ASK USER] Should package overlay refs be pinned for reproducible builds, or is “latest with recorded refs” package behavior desired?

### 7) Evidence

- `docs/firmware-ci-prd.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `.github/workflows/release-maintenance.yml`
- `devices/profiles.yml`
- `scripts/ci/profiles.sh`
- `scripts/ci/config-feeds.sh`
- `scripts/common/Packages.sh`
