# Codebase Structure

## Core Sections (Required)

### 1) Top-Level Map

| Path | Purpose | Evidence |
|------|---------|----------|
| `.github/workflows/` | GitHub Actions entry workflow, reusable firmware build workflow, and lint workflow. | `.github/workflows/firmware-ci.yml`, `.github/workflows/firmware-build.yml`, `.github/workflows/ci-lint.yml` |
| `.github/dependabot.yml` | Dependabot configuration for GitHub Actions dependency updates. | `.github/dependabot.yml` |
| `devices/` | Declarative profile registry plus per-profile OpenWrt `.config` files. | `devices/profiles.yml`, `devices/*/.config` |
| `scripts/ci/` | Reusable CI implementation modules for profile parsing, config/feeds, build artifacts, access detection, release metadata, and validation. | `scripts/ci/profiles.sh`, `scripts/ci/config-feeds.sh`, `scripts/ci/build-artifacts.sh` |
| `scripts/common/` | Shared config fragments, build customizations, and package overlay helpers. | `scripts/common/config/base.config`, `scripts/common/General.sh`, `scripts/common/Packages.sh`, `scripts/common/package` |
| `docs/` | PRD, architecture notes, and generated codebase knowledge. | `docs/firmware-ci-prd.md`, `docs/ci-workflow-architecture.md`, `docs/codebase/` |
| `README.md` | User-facing workflow, profile, validation, and Release contract overview. | `README.md` |

### 2) Entry Points

- Main runtime entry: `.github/workflows/firmware-ci.yml`.
- Main reusable implementation: `.github/workflows/firmware-build.yml`.
- Secondary entry point: `.github/workflows/ci-lint.yml`.
- How entry is selected: `firmware-ci.yml` accepts `target=<profile-id>` or `target=all`, resolves the matrix with `scripts/ci/profiles.sh matrix`, then calls `firmware-build.yml` once per selected profile.

### 3) Module Boundaries

| Boundary | What belongs here | What must not be here |
|----------|-------------------|------------------------|
| `.github/workflows/` | Triggers, permissions, matrix orchestration, action wiring, and high-level phase order. | Device metadata or large shell implementations. |
| `devices/profiles.yml` | Profile metadata: source repo/branch, firmware tag, cache group, config path, and optional build hooks. | Shell implementation logic. |
| `devices/<profile>/` | OpenWrt target/subtarget/device `.config` inputs for one profile. | Shared package selections, package helper logic, or workflow orchestration. |
| `scripts/ci/` | Reusable shell modules and validation. | Device-specific OpenWrt package selections unless they are generic build mechanics. |
| `scripts/common/` | Shared config fragments, hooks, and package overlay helper calls. | GitHub Actions trigger rules. |

### 4) Naming and Organization Rules

- Workflow files use firmware-domain names: `firmware-ci.yml`, `firmware-build.yml`, `ci-lint.yml`.
- CI shell modules use kebab-case: `profiles.sh`, `config-feeds.sh`, `build-artifacts.sh`.
- Profile ids match existing device directory names, for example `x86_64_immortalWrt` and `Qualcommax_LEDE`.
- Profile paths are relative to the repository root unless explicitly absolute.

### 5) Evidence

- `README.md`
- `docs/ci-workflow-architecture.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `devices/profiles.yml`
- `scripts/ci/profiles.sh`
