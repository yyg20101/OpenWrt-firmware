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
  - Scheduled entry every day at 20:00 UTC / 04:00 Asia/Shanghai.
  - Manual entry through `workflow_dispatch`.
  - Optional automation entry through `repository_dispatch` with event type `firmware-ci`.
  - Resolves `target` into a build matrix by calling `scripts/ci/profiles.sh matrix`.
  - Accepts `target=<profile-id>`, profile groups, or `target=all`.
  - Scheduled runs default to `target=x86_64_all` and `release=true`.
  - Marks published releases as GitHub Latest only when one profile is selected.

- `.github/workflows/firmware-build.yml`
  - Reusable build implementation.
  - Loads a single profile, initializes the runner, clones source, restores caches, configures feeds/packages, compiles firmware, uploads artifacts, and optionally publishes a Release.

- `.github/workflows/ci-lint.yml`
  - Validates workflow YAML.
  - Validates shell syntax.
  - Validates `devices/profiles.yml`.
  - Validates Dependabot ecosystem coverage.
  - Validates cache key period and save policy.
  - Validates LuCI Simplified Chinese language policy.
  - Validates PassWall overlay policy.
  - Validates PassWall overlay policy and source-specific config through profile and config-audit checks.
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

## Cache Strategy

`firmware-build.yml` restores two cache families: `ccache-v2` and `build-accel-v2`. Primary keys are grouped by cache type, version, source repository slug, source branch, profile `cache_group`, and monthly cache period. Restore keys intentionally stop at the source/branch/group prefix so a previous period can accelerate the build without crossing toolchain boundaries.

Cache save is stricter than exact-hit detection: save steps run only when `cache-matched-key` is empty. Exact hits and fallback hits both skip saving, which prevents a restored previous-period cache from creating a redundant new period cache on every calendar rollover.

## Feeds, LuCI, and Overlays

Current enabled profiles leave `feeds_conf` empty, so `config-feeds.sh prepare-feeds` does not replace upstream `feeds.conf.default`.

- `coolsnowwolf/lede` declares `src-git luci https://github.com/coolsnowwolf/luci.git;openwrt-25.12`.
- `immortalwrt/immortalwrt`, `VIKINGYFY/immortalwrt`, and `LiBwrt/openwrt-6.x` declare `src-git luci https://github.com/immortalwrt/luci.git`.

LuCI Chinese support follows upstream LuCI rules. The shared fragment selects `CONFIG_LUCI_LANG_zh_Hans=y`; upstream `luci.mk` maps `zh_Hans` to `zh-cn` package aliases and creates matching `luci-i18n` packages for installed modules. The config audit verifies the defconfig result contains `CONFIG_PACKAGE_luci-i18n-base-zh-cn=y` without hard-coding per-plugin translation packages.

ImmortalWrt's `luci` collection depends on `luci-light`; `luci-light` depends on `luci-theme-bootstrap`, `uhttpd`, and `uhttpd-mod-ubus`. The Bootstrap theme installs its own default `main.mediaurlbase`, and `luci-base` depends on `rpcd`/`rpcd-mod-luci` and adds the uHTTPd LuCI ucode handler through its post-install script. Local config therefore avoids hard-coding LuCI runtime/library dependencies and audits those defaults instead of replacing them.

LEDE builds first seed the local package tree from `kenzok8/small` `master` in `all` mode, after removing matching local/feed package directories for that repository's package set. This supplies LEDE-oriented proxy packages such as SSR Plus, OpenClash, HomeProxy, Mihomo/MosDNS/Nikki, and related dependencies without applying the same feed to ImmortalWrt-family profiles.

PassWall remains an explicit shared overlay after the LEDE `kenzok8/small` seed. `scripts/common/package` refreshes `Openwrt-Passwall/openwrt-passwall-packages` from `main` and pulls `Openwrt-Passwall/openwrt-passwall` through `UPDATE_PACKAGE_LATEST_TAG`, after removing conflicting local/feed directories.

Third-party LuCI apps that are not reliably present in the active official feeds can be handled by `scripts/common/package` overlays. Shared requested apps stay in `base.config`; LEDE-oriented apps such as OpenVPN stay in `lede-extra.config`. The build keeps a generic requested-vs-effective LuCI app audit after `make defconfig`, while avoiding a fixed required-plugin overlay whitelist so future plugin additions do not need a second policy list.

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
- `make_compile_jobs`

Profiles may also set `make_compile_jobs` directly to cap OpenWrt compile
parallelism for source trees that are memory-sensitive on GitHub-hosted
runners. When omitted, the build uses the runner CPU count.

Current usage pattern:

- `x86_64_immortalWrt` sets `make_compile_jobs: 2` because the source tree is more memory-sensitive on GitHub-hosted runners.
- `x86_64_LEDE` leaves compile parallelism on auto because it has not needed a cap yet.

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
health report -> config audit -> firmware build with release=true -> Release asset verification -> cache maintenance dry-run
```

Recommended operating order:

1. Run `Optimization Health` first so profile drift, cache grouping, and matrix shape are visible before any build.
2. Run `Firmware CI` for `target=x86_64_all` next and inspect both x86 profiles before widening to other targets.
3. Run `Cache Maintenance` in dry-run mode before any real cache cleanup, and only delete within a bounded `prefix` or `ref`.
4. For firmware output validation, pass `release=true` by default so the successful build exercises the Release asset upload path. Prefer a single selected profile for final publish verification; grouped targets may publish Release assets, but they do not take GitHub Latest.

Daily scheduled builds follow the same release-verification path automatically. They build `x86_64_all` with `release=true`, covering the two stable x86 profiles while avoiding a daily full-platform Actions and Release asset load.

Default firmware verification uses the Release, not a full local download of the multi-GB firmware artifact:

1. Confirm the run and build job conclude `success`, including `Upload Firmware Artifact`, `Smoke X86 Artifact`, and `Publish GitHub Release`.
2. Download small diagnostic artifacts (`config-audit-*`, `compile-log-*`, `smoke-x86-*`) and verify config audit, compile log, and smoke summary.
3. Inspect Release assets with `gh release view <tag> --json assets`.
4. Compare firmware asset `digest` values from GitHub with the entries in `sha256sums.txt`.
5. Download a small asset such as `openwrt-x86-64-generic-kernel.bin` and run `shasum -a 256 -c sha256sums.txt --ignore-missing` to prove the checksum path.
6. Download full firmware images only for flash testing or targeted forensic checks.

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
- Keep cache keys isolated by source slug, source branch, and `cache_group`; save only when no matched cache key exists.
- Treat `x86_64_all` as the preferred preflight target for build and smoke validation before broader profile groups.
- Treat `release=true` as the default for firmware artifact validation so Release assets, asset digests, `sha256sums.txt`, and small-asset checksum checks are exercised.
- Run local validation before pushing:

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/sync-workflow-target-options.sh "$PWD"
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-cache-key-policy.sh
bash scripts/ci/validate-luci-zh-cn-config.sh
bash scripts/ci/validate-passwall-overlay.sh
bash scripts/ci/validate-dependabot-coverage.sh
bash scripts/ci/optimization-report.sh summary "$PWD"
```
