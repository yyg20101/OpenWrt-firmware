# CI Workflow Architecture

This repository uses a declarative profile + reusable workflow structure for firmware builds.

## Goals

- Keep device metadata in one place.
- Keep workflow YAML thin and orchestration-focused.
- Make adding a device require a `.config` file and one `devices/profiles.yml` entry.
- Standardize artifacts and Release metadata.
- Keep validation runnable locally and in GitHub Actions.

## Entry Workflows

- `.github/workflows/firmware-ci.yml`
  - Manual entry through `workflow_dispatch`.
  - Optional automation entry through `repository_dispatch` with event type `firmware-ci`.
  - Resolves `target` into a build matrix by calling `scripts/ci/profiles.sh matrix`.
  - Accepts `target=<profile-id>`, profile groups, or `target=all`.
  - Marks published releases as GitHub Latest only when one profile is selected.

- `.github/workflows/firmware-build.yml`
  - Reusable build implementation.
  - Loads a single profile, initializes the runner, clones source, restores caches, configures feeds/packages, compiles firmware, uploads artifacts, and optionally publishes a Release.

- `.github/workflows/ci-lint.yml`
  - Validates workflow YAML.
  - Validates shell syntax.
  - Validates `devices/profiles.yml`.
  - Validates Dependabot ecosystem coverage.
  - Validates optimization health summary generation.

- `.github/workflows/optimization-health.yml`
  - Manually generates a read-only firmware optimization health report.
  - Summarizes enabled profiles, target matrix, governance checks, and GitHub Actions cache usage.
  - Uploads report artifacts and writes the same report to the GitHub Step Summary.
  - Does not build firmware, publish releases, or delete caches.

- `.github/workflows/cache-maintenance.yml`
  - Manually lists or deletes GitHub Actions caches.
  - Defaults to dry-run and keeps the newest two matched caches.
  - Requires `prefix` or `ref` for real deletions.

- `.github/workflows/release-maintenance.yml`
  - Manually lists or deletes old GitHub Releases by tag prefix.
  - Defaults to dry-run and keeps the newest matched releases.
  - Allows broad `firmware-` dry-runs, but requires a profile-specific tag prefix for real deletions.

## Profile Contract

The authoritative device registry is `devices/profiles.yml`.

Required fields per profile:

- `title`
- `enabled`
- `source_repo`
- `source_branch`
- `firmware_tag`
- `cache_group`
- `groups`
- `config`

Shared defaults may define:

- `timezone`
- `config_fragments`
- `feeds_conf`
- `pre_feeds_script`
- `post_feeds_script`
- `general_script`
- `package_base_script`
- `package_overlay_script`
- `make_download_jobs`

`scripts/ci/profiles.sh export-env` writes profile values to both `GITHUB_ENV` and `GITHUB_OUTPUT`, so shell steps and action expressions use the same resolved contract.

`scripts/ci/profiles.sh target-options` generates the supported manual dispatch targets from enabled profiles, their groups, and `all`. `scripts/ci/sync-workflow-target-options.sh` writes those targets into `.github/workflows/firmware-ci.yml`, keeping the GitHub manual dispatch dropdown aligned with `devices/profiles.yml`.

## Build Flow

```text
Firmware CI
  -> Resolve target from workflow_dispatch/repository_dispatch
  -> Generate matrix from devices/profiles.yml
  -> Decide whether a single published profile may become GitHub Latest
  -> Firmware Build(profile)
    -> Load profile
    -> Initialize runner with retry/backoff for network package setup
    -> Clone OpenWrt source with retry/backoff
    -> Restore ccache and build accelerator cache
    -> Load .config and config fragments
    -> Prepare feeds and run pre-feeds script
    -> Update/install feeds with retry/backoff
    -> Run general script
    -> Apply package overlays and record package source refs
    -> Run post-feeds script
    -> Download dependencies
    -> Compile with fallback
    -> Organize artifacts and checksums
    -> Detect default access
    -> Upload Artifact and optional Release
```

## Optimization Health Flow

```text
Optimization Health
  -> Validate devices/profiles.yml
  -> Generate profile and matrix summary
  -> Generate GitHub Actions cache summary
  -> Upload read-only health report
```

Use this flow before each optimization pass. The intended loop is:

```text
health report -> config audit -> firmware build -> artifact verification -> cache maintenance dry-run
```

## CI Script Modules

- `scripts/ci/profiles.sh`
  - Validates profile schema.
  - Lists profile ids.
  - Generates manual dispatch target options.
  - Generates build matrix JSON.
  - Exports one profile as environment variables and step outputs.

- `scripts/ci/load-device-profile.sh`
  - Compatibility wrapper around `profiles.sh export-env`.

- `scripts/ci/config-feeds.sh`
  - Loads base config.
  - Appends declared config fragments.
  - Runs feeds and customization hooks.
  - Retries feeds update/install operations with backoff.
  - Applies package overlays.

- `scripts/ci/retry.sh`
  - Provides shared retry/backoff behavior for network-heavy workflow and CI script steps.

- `scripts/ci/build-artifacts.sh`
  - Downloads dependencies.
  - Compiles with fallback strategies.
  - Dumps failure context.
  - Organizes firmware files and checksums.
  - Prunes VM-specific disk image formats (`*.vmdk`, `*.vdi`, `*.vhd`, `*.vhdx`, `*.qcow2`) from uploaded artifacts while keeping `Packages.tar.gz`.

- `scripts/ci/detect-default-access.sh`
  - Detects default LAN IP and root password state from source/rootfs outputs.

- `scripts/ci/release-maintenance.sh`
  - Generates standardized Release name, tag, body file, and action outputs.
  - Adds package archive and package source manifest details to the Release body when present.

- `scripts/ci/optimization-report.sh`
  - Generates read-only Markdown reports for profile/matrix health, GitHub Actions cache usage, and Release artifact assets.
  - Keeps optimization checks visible without triggering builds, releases, or cache deletion.

- `scripts/ci/validate-profiles.sh`
  - CI-facing profile validation wrapper.

- `scripts/ci/sync-workflow-target-options.sh`
  - Updates the static GitHub Actions manual dispatch dropdown from `devices/profiles.yml`.

- `scripts/ci/validate-dependabot-coverage.sh`
  - Detects npm/pip/docker manifests and requires matching Dependabot ecosystems.

## Maintenance Rules

- Add device metadata only in `devices/profiles.yml`.
- Add device OpenWrt config under `devices/<profile-id>/.config`.
- Run `scripts/ci/sync-workflow-target-options.sh` after changing enabled profiles or groups.
- Keep long shell logic in `scripts/ci/*.sh`, not workflow YAML.
- Preserve profile output names when refactoring cache, artifact, or Release behavior.
- Keep cache deletion workflows filtered by `prefix` or `ref`; dry-run is the only broad mode.
- Run local validation before pushing:

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/sync-workflow-target-options.sh "$PWD"
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
bash scripts/ci/optimization-report.sh summary "$PWD"
```
