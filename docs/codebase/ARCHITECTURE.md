# Architecture

## Core Sections (Required)

### 1) Architectural Style

- Primary style: Declarative profile registry plus dispatcher/reusable GitHub Actions workflow.
- Why this classification: `devices/profiles.yml` owns device metadata; `firmware-ci.yml` only resolves a target into a matrix; `firmware-build.yml` performs one profile build by calling focused `scripts/ci` modules.
- Primary constraints: OpenWrt builds are disk/CPU intensive, depend on mutable upstream sources and feeds, and need Release metadata that traces profile inputs and source commit.

### 2) System Flow

```text
workflow_dispatch/repository_dispatch
  -> firmware-ci target resolution
  -> profiles.sh matrix
  -> firmware-build(profile)
  -> profile export, source revision probe, optional unchanged-release skip, source clone, cache, config/feeds, build, artifacts, Release
```

1. `firmware-ci.yml` receives `target` and `release`; `target` is a profile id, a profile group, or `all`.
2. `scripts/ci/profiles.sh target-options` provides the manual dispatch target list; `sync-workflow-target-options.sh` writes it into the static GitHub Actions dropdown.
3. `scripts/ci/profiles.sh matrix` validates `devices/profiles.yml`, emits a matrix of enabled profiles, and lets the dispatcher mark releases as Latest only for single-profile selections.
4. `firmware-build.yml` calls `load-device-profile.sh`, which delegates to `profiles.sh export-env` and writes values to `GITHUB_ENV` and `GITHUB_OUTPUT`.
5. Scheduled release builds probe the upstream branch head before runner setup and may skip when the existing stable Release already matches both source commit and profile hash.
6. The build workflow clones the selected source repo/branch and emits source commit outputs for cache keys and Release metadata.
7. `config-feeds.sh` loads the profile `.config`, appends config fragments, runs feed hooks, updates/installs feeds with retry/backoff, runs common customizations, and applies package overlays.
8. `build-artifacts.sh` downloads dependencies, compiles with fallback, prunes VM-specific disk image formats from firmware outputs, writes `artifact-manifest.txt`, and generates checksums.
9. `detect-default-access.sh` records default access state, then `release-maintenance.sh` generates standardized Release name/tag/body outputs including package source refs when present.

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| `firmware-ci.yml` | Manual/repository dispatch input parsing and matrix dispatch. | Device metadata or build implementation. | `.github/workflows/firmware-ci.yml` |
| `firmware-build.yml` | Runner setup, cache/action wiring, build phase order, artifact and Release actions. | Profile schema validation internals. | `.github/workflows/firmware-build.yml` |
| `profiles.sh` | Profile schema validation, list/matrix generation, env/output export, profile hash calculation. | OpenWrt source mutation. | `scripts/ci/profiles.sh` |
| `config-feeds.sh` | Config assembly, feeds preparation, hooks, package overlays. | Compile fallback or Release publishing. | `scripts/ci/config-feeds.sh` |
| `build-artifacts.sh` | Dependency download, compile fallback, failure diagnostics, firmware packaging/checksums. | Profile parsing. | `scripts/ci/build-artifacts.sh` |
| `release-skip.sh` | Scheduled release no-op detection from stable Release metadata. | Manual validation skipping or artifact publishing. | `scripts/ci/release-skip.sh` |
| `build-metrics.sh` | Build metrics summary from compile env and heartbeat log. | Build control flow. | `scripts/ci/build-metrics.sh` |
| `detect-default-access.sh` | Default LAN IP and root password state detection. | Release upload. | `scripts/ci/detect-default-access.sh` |
| `release-maintenance.sh` | Release name/tag/body generation and outputs. | Firmware compilation. | `scripts/ci/release-maintenance.sh` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| Declarative registry | `devices/profiles.yml` | Adds devices without workflow edits. |
| Generated manual targets | `profiles.sh target-options`, `sync-workflow-target-options.sh` | Keeps the GitHub manual dispatch dropdown aligned with enabled profiles and groups. |
| Shared performance fragment | `network-performance.config` | Enables BBR and optional SQM/CAKE/IFB queue management consistently across profiles. |
| Runtime performance defaults | `files/etc/uci-defaults/99-performance-defaults` | Applies conservative sysctl defaults for BBR, fq_codel, and TCP buffers on first boot. |
| Platform performance fragment | `x86-performance.config` | Keeps x86-only NIC, virtualization, IRQ balancing, and CPU microcode choices out of non-x86 profiles. |
| Subcommand shell modules | `profiles.sh`, `config-feeds.sh`, `build-artifacts.sh`, `release-maintenance.sh` | Keeps workflow YAML thin and makes local validation possible. |
| Env plus output contract | `profiles.sh`, `build-artifacts.sh`, `release-maintenance.sh` | Shell steps use environment variables while GitHub action `with:` expressions use step outputs. |
| Compile fallback escalation | `build-artifacts.sh` | Tries parallel build, serial build, then verbose serial build for diagnostics. |
| Scheduled unchanged-release skip | `release-skip.sh`, `release-maintenance.sh` | Avoids daily rebuilds when source commit, profile hash, and published checksum assets already match. |
| Build metrics artifact | `build-metrics.sh`, `build-artifacts.sh` | Records compile duration, selected parallelism, heartbeat count, and peak heartbeat disk use. |
| Network retry/backoff | `retry.sh`, `firmware-build.yml`, `config-feeds.sh`, `Packages.sh` | Reduces transient apt/source/feed/package GitHub failures without masking final errors. |
| Artifact pruning | `build-artifacts.sh`, `x86.config` | Keeps x86 compressed raw images and packages while excluding VM-specific disk formats from uploaded artifacts. |
| Profile hash provenance | `profiles.sh`, `release-maintenance.sh`, `release-skip.sh` | Identifies whether a stable Release was built with the current profile config/hooks/fragments. |
| Filtered cache deletion | `cache-maintenance.yml` | Allows broad dry-runs, but requires `prefix` or `ref` before deleting caches. |

### 5) Known Architectural Risks

- Upstream OpenWrt sources, feeds, package repos, and the remote build environment script are mutable external dependencies.
- `target=all` can consume significant GitHub Actions minutes and cache quota.
- Release tags are stable per profile/source/branch; successful rebuilds update the same Release and replace assets. Only single-profile publishes are marked GitHub Latest.

### 6) Evidence

- `docs/firmware-ci-prd.md`
- `docs/ci-workflow-architecture.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `devices/profiles.yml`
- `scripts/ci/*.sh`
