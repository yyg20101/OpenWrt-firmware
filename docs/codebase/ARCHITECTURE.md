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
  -> profile export, source clone, cache, config/feeds, build, artifacts, Release
```

1. `firmware-ci.yml` receives `target` and `release`; `target` is a profile id or `all`.
2. `scripts/ci/profiles.sh matrix` validates `devices/profiles.yml` and emits a matrix of enabled profiles.
3. `firmware-build.yml` calls `load-device-profile.sh`, which delegates to `profiles.sh export-env` and writes values to `GITHUB_ENV` and `GITHUB_OUTPUT`.
4. The build workflow clones the selected source repo/branch and emits source commit outputs for cache keys and Release metadata.
5. `config-feeds.sh` loads the profile `.config`, appends config fragments, runs feed hooks, updates/installs feeds, runs common customizations, and applies package overlays.
6. `build-artifacts.sh` downloads dependencies, compiles with fallback, organizes firmware outputs, writes `artifact-manifest.txt`, and generates checksums.
7. `detect-default-access.sh` records default access state, then `release-maintenance.sh` generates standardized Release name/tag/body outputs.

### 3) Layer/Module Responsibilities

| Layer or module | Owns | Must not own | Evidence |
|-----------------|------|--------------|----------|
| `firmware-ci.yml` | Manual/repository dispatch input parsing and matrix dispatch. | Device metadata or build implementation. | `.github/workflows/firmware-ci.yml` |
| `firmware-build.yml` | Runner setup, cache/action wiring, build phase order, artifact and Release actions. | Profile schema validation internals. | `.github/workflows/firmware-build.yml` |
| `profiles.sh` | Profile schema validation, list/matrix generation, env/output export, profile hash calculation. | OpenWrt source mutation. | `scripts/ci/profiles.sh` |
| `config-feeds.sh` | Config assembly, feeds preparation, hooks, package overlays. | Compile fallback or Release publishing. | `scripts/ci/config-feeds.sh` |
| `build-artifacts.sh` | Dependency download, compile fallback, failure diagnostics, firmware packaging/checksums. | Profile parsing. | `scripts/ci/build-artifacts.sh` |
| `detect-default-access.sh` | Default LAN IP and root password state detection. | Release upload. | `scripts/ci/detect-default-access.sh` |
| `release-maintenance.sh` | Release name/tag/body generation and outputs. | Firmware compilation. | `scripts/ci/release-maintenance.sh` |

### 4) Reused Patterns

| Pattern | Where found | Why it exists |
|---------|-------------|---------------|
| Declarative registry | `devices/profiles.yml` | Adds devices without workflow edits. |
| Subcommand shell modules | `profiles.sh`, `config-feeds.sh`, `build-artifacts.sh`, `release-maintenance.sh` | Keeps workflow YAML thin and makes local validation possible. |
| Env plus output contract | `profiles.sh`, `build-artifacts.sh`, `release-maintenance.sh` | Shell steps use environment variables while GitHub action `with:` expressions use step outputs. |
| Compile fallback escalation | `build-artifacts.sh` | Tries parallel build, serial build, then verbose serial build for diagnostics. |
| Profile hash cache key | `profiles.sh`, `firmware-build.yml` | Invalidates build accelerator cache when profile config/hooks/fragments change. |

### 5) Known Architectural Risks

- Upstream OpenWrt sources, feeds, package repos, and the remote build environment script are mutable external dependencies.
- `target=all` can consume significant GitHub Actions minutes and cache quota.
- Release tags are intentionally unique and `allowUpdates=false`; rerunning the same source/profile/run combination can require a new workflow run number.

### 6) Evidence

- `docs/firmware-ci-prd.md`
- `docs/ci-workflow-architecture.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `devices/profiles.yml`
- `scripts/ci/*.sh`
