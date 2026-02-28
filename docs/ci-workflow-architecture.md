# CI Workflow Architecture

This repository uses a dispatcher + reusable workflow structure for OpenWrt firmware builds.

## Entry Workflows

- `.github/workflows/openwrt-builder.yml`
  - Manual entry (`workflow_dispatch`) and optional auto entry (`repository_dispatch`).
  - Expands model matrix (single model or build-all).
  - Calls reusable workflow with `uses`.

- `.github/workflows/openwrt-build-reusable.yml`
  - Contains the end-to-end build pipeline.
  - Uses shell scripts in `scripts/ci` to keep YAML readable and testable.

- `.github/workflows/ci-lint.yml`
  - Validates workflows, shell syntax, and device env schema.

- `.github/workflows/update-checker.yml`
  - Compares upstream commit hash.
  - Supports `auto_trigger_build` switch (default `false`).
  - When switch is on and update is detected, dispatches `source-code-update` to builder.

## Build Assets

- Shared defaults are located in `scripts/common/` by default:
  - `Driver.config`
  - `General.sh`
  - `Packages.sh`
  - `diy-part1.sh`
  - `diy-part1-helloworld.sh`
  - `diy-part2.sh`
  - `package`

- Path variables (workflow `env`) can override shared defaults without changing scripts:
  - `DRIVER_CONFIG_PATH` (single file)
  - `DRIVER_CONFIG_GLOB` (additional fragments, sorted append)
  - `GENERAL_SCRIPT_PATH`
  - `PACKAGE_BASE_SCRIPT_PATH`
  - `DRIVER_CONFIG_HASH_GLOB` (cache key invalidation scope)

- Device overrides are located in `devices/<model>/`.

- Resolution order (high to low priority):
  1. `devices/<model>/...` (device-specific override)
  2. shared defaults from `scripts/common/...`

## CI Script Modules

- `scripts/ci/load-device-profile.sh`
  - Resolves device env overrides.
  - Selects `CONFIG_FILE`, `FEEDS_CONF`, `DIY_P1_SH`, `DIY_P2_SH`, `PACKAGE_FILE`.
  - Computes `CCACHE_GROUP`.

- `scripts/ci/generate-build-vars.sh`
  - Exports `SOURCE_REPO`, `WRT_HASH`, `CACHE_WEEK`.

- `scripts/ci/config-feeds.sh`
  - Handles phase-5 config and feeds operations:
    - load/snapshot config
    - extend driver config
    - custom feeds scripts
    - package override script
    - custom `files` + `diy-part2`

- `scripts/ci/build-artifacts.sh`
  - Handles phase-6 build and artifact operations:
    - dependency download
    - compile with fallback strategies
    - failure context dump
    - artifact organize
    - checksum generation

- `scripts/ci/detect-default-access.sh`
  - Detects default LAN IP and root password state.
  - Emits source trace for release notes.

- `scripts/ci/release-maintenance.sh`
  - Generates release tag.
  - Prepares release name/tag/body file metadata.

- `scripts/ci/validate-device-env.sh`
  - Schema checks for `devices/*/env`.

- `scripts/ci/validate-dependabot-coverage.sh`
  - Detects whether npm/pip/docker manifests exist.
  - Fails CI if manifests are present but matching Dependabot ecosystem is missing.

## Maintenance Rules

- Prefer adding logic to `scripts/ci/*.sh` rather than inline YAML.
- Keep workflow steps thin and focused on orchestration.
- Preserve exported env/output variable names when refactoring.
- Run local checks before pushing:
  - workflow YAML parse
  - shell syntax check
  - device env schema validation
  - dependabot coverage validation
