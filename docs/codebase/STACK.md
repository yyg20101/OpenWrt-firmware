# Technology Stack

## Core Sections (Required)

### 1) Runtime Summary

| Area | Value | Evidence |
|------|-------|----------|
| Primary language | Bash shell scripts, GitHub Actions YAML, OpenWrt `.config` fragments, and one Ruby-backed profile parser embedded in a shell script. | `scripts/ci/*.sh`, `.github/workflows/*.yml`, `devices/*/.config` |
| Runtime + version | GitHub-hosted `ubuntu-22.04` runners for firmware workflows; shell scripts use `#!/usr/bin/env bash` with `set -euo pipefail`; Ruby is used through the runner/system Ruby for YAML/JSON profile parsing. | `.github/workflows/firmware-ci.yml`, `.github/workflows/firmware-build.yml`, `scripts/ci/profiles.sh` |
| Package manager | No repository package manager manifest exists. Build dependencies are installed with `apt-get`; OpenWrt packages are resolved with `./scripts/feeds`. | `.github/workflows/firmware-build.yml`, `README.md` |
| Module/build system | GitHub Actions orchestrates OpenWrt firmware builds; OpenWrt `make` compiles firmware after source clone, config assembly, feeds setup, and package overlays. | `.github/workflows/firmware-ci.yml`, `.github/workflows/firmware-build.yml`, `scripts/ci/build-artifacts.sh` |

### 2) Production Frameworks and Dependencies

| Dependency | Version | Role in system | Evidence |
|------------|---------|----------------|----------|
| GitHub Actions | Action refs pinned in workflow files, for example `actions/checkout@v6`, `actions/cache@v5`, `actions/upload-artifact@v7` | CI orchestration, cache restore, artifact upload, optional Release publishing | `.github/workflows/firmware-build.yml`, `.github/workflows/ci-lint.yml` |
| OpenWrt/LEDE/ImmortalWrt source trees | Branches declared per profile | External firmware source cloned and compiled during workflow execution | `devices/profiles.yml` |
| Debian/Ubuntu build packages | Runner package repository versions | Toolchain prerequisites for OpenWrt compilation | `.github/workflows/firmware-build.yml` |
| OpenWrt feeds | Source-controlled by cloned OpenWrt tree | Package feed resolution for firmware builds | `.github/workflows/firmware-build.yml` |

### 3) Development Toolchain

| Tool | Purpose | Evidence |
|------|---------|----------|
| reviewdog/action-actionlint | GitHub Actions workflow static checking in CI | `.github/workflows/ci-lint.yml` |
| Ruby YAML parser | Validates workflow YAML and parses `devices/profiles.yml` | `.github/workflows/ci-lint.yml`, `scripts/ci/profiles.sh` |
| `bash -n` | Validates shell syntax under `scripts/` | `.github/workflows/ci-lint.yml` |
| `scripts/ci/validate-profiles.sh` | Validates declarative firmware profiles | `scripts/ci/validate-profiles.sh`, `scripts/ci/profiles.sh` |
| Dependabot | Updates GitHub Actions dependencies weekly | `.github/dependabot.yml` |

### 4) Key Commands

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
bash scripts/ci/profiles.sh matrix all "" "$PWD"
```

### 5) Environment and Config

- Config sources: `.github/workflows/*.yml`, `devices/profiles.yml`, `devices/<profile>/.config`, `scripts/common/*`, and `scripts/ci/*`.
- Required profile fields: `source_repo`, `source_branch`, `firmware_tag`, `cache_group`, and `config`.
- Deployment/runtime constraints: firmware builds assume GitHub-hosted Ubuntu runners with enough disk space for OpenWrt compilation; `firmware-build.yml` maximizes build space and installs prerequisites at run time.

### 6) Evidence

- `README.md`
- `docs/ci-workflow-architecture.md`
- `docs/firmware-ci-prd.md`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `.github/workflows/ci-lint.yml`
- `devices/profiles.yml`
- `scripts/ci/*.sh`
