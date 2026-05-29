# Codebase Concerns

## Core Sections (Required)

### 1) Top Risks (Prioritized)

| Severity | Concern | Evidence | Impact | Suggested action |
|----------|---------|----------|--------|------------------|
| High | Builds depend on mutable external sources: upstream repos, feeds, package repos, remote build environment script, and runner images. | `.github/workflows/firmware-build.yml`, `devices/profiles.yml`, `scripts/common/Packages.sh` | Builds may fail or produce different artifacts without local changes. | Pin more external refs, record selected package refs, and add retry wrappers for network-heavy steps. |
| Medium | `target=all` can trigger all enabled profiles in parallel. | `.github/workflows/firmware-ci.yml`, `devices/profiles.yml` | Actions minutes, cache quota, and release volume can spike. | Use profile groups for routine builds; multi-profile releases no longer overwrite GitHub Latest. |
| Medium | No unit/fixture tests cover shell module behavior. | `.github/workflows/ci-lint.yml`, `scripts/ci/*.sh` | Syntax/schema checks can pass while behavioral edge cases remain. | Add fixture tests for profile export, config fragments, artifact organization, and Release metadata. |
| Medium | Release tags are intentionally unique and not updated in place. | `.github/workflows/firmware-build.yml`, `scripts/ci/release-maintenance.sh` | Rebuilds create new releases rather than replacing old ones. | Define retention/cleanup policy in a future workflow. |

### 2) Technical Debt

| Debt item | Why it exists | Where | Risk if ignored | Suggested fix |
|-----------|---------------|-------|-----------------|---------------|
| Build environment is installed inline in workflow YAML. | Runner setup is tightly coupled to GitHub Actions. | `.github/workflows/firmware-build.yml` | Harder to test locally and slower to iterate. | Extract setup into a script if it grows further. |
| Package overlay helper performs live GitHub operations. | Firmware customization relies on latest package sources. | `scripts/common/Packages.sh` | Build reproducibility is limited. | Log or pin selected package refs. |
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
| Network-heavy package/feed operations are serial. | `.github/workflows/firmware-build.yml`, `scripts/common/Packages.sh` | Feeds and package overlays run during every build. | Network stalls can dominate runtime. | Add targeted retry/timeout handling. |
| Manual cache deletion can remove useful accelerators if scoped too broadly. | `.github/workflows/cache-maintenance.yml` | Real deletion now requires `prefix` or `ref` and keeps two newest matches by default. | Wrong filter choices can still delete useful cache groups. | Run dry-run first and keep cache keys grouped by source/profile family. |

### 5) Fragile/High-Churn Areas

| Area | Why fragile | Churn signal | Safe change strategy |
|------|-------------|-------------|----------------------|
| `.github/workflows/firmware-build.yml` | Central build phase order, cache keys, artifact paths, and Release wiring live here. | Large workflow surface. | Keep step outputs explicit and run YAML/profile validation after edits. |
| `scripts/ci/profiles.sh` | Profile validation, matrix output, env/output contracts, and cache hash computation live here. | New central contract. | Test with single profile and `all` matrix before workflow changes. |
| `scripts/ci/config-feeds.sh` | Mutates the cloned OpenWrt tree. | Source/feeds layout can vary by upstream. | Keep path resolution explicit and fail on missing declared inputs. |

### 6) `[ASK USER]` Questions

1. [ASK USER] Should repository dispatch be limited to specific automation sources, or is any caller with repo dispatch permission acceptable?
2. [ASK USER] What retention policy should replace the removed automatic cleanup workflows?
3. [ASK USER] Should package overlay refs be pinned for reproducible builds, or is “latest” package behavior desired?

### 7) Evidence

- `docs/firmware-ci-prd.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `devices/profiles.yml`
- `scripts/ci/profiles.sh`
- `scripts/ci/config-feeds.sh`
- `scripts/common/Packages.sh`
