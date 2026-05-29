# External Integrations

## Core Sections (Required)

### 1) Integration Inventory

| System | Type (API/DB/Queue/etc) | Purpose | Auth model | Criticality | Evidence |
|--------|---------------------------|---------|------------|-------------|----------|
| GitHub Actions | CI/CD platform | Runs build and lint workflows. | GitHub Actions context. | High | `.github/workflows/*.yml` |
| GitHub Actions Cache | Cache service | Restores ccache and build accelerator directories; supports filtered manual cleanup. | GitHub Actions context. | Medium | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub Artifacts | Artifact storage | Stores compile logs and firmware outputs for 14 days. | GitHub Actions context. | High | `.github/workflows/firmware-build.yml` |
| GitHub Releases | Release hosting | Optionally publishes successful firmware builds. | `secrets.GITHUB_TOKEN`. | High | `.github/workflows/firmware-build.yml`, `scripts/ci/release-maintenance.sh` |
| External OpenWrt source repositories | Git repositories | Cloned and compiled per profile. | Public HTTPS clone. | High | `devices/profiles.yml`, `.github/workflows/firmware-build.yml` |
| OpenWrt/ImmortalWrt build environment script | Remote shell script | Initializes runner build prerequisites. | Public HTTPS fetch through `curl`. | High | `.github/workflows/firmware-build.yml` |
| OpenWrt feeds | Package feed system | Updates and installs package feeds before build. | Public network access from cloned source. | High | `.github/workflows/firmware-build.yml` |
| GitHub package repositories | Git/API downloads | `scripts/common/Packages.sh` clones package repos and may query release metadata. | Public HTTPS/API. | Medium | `scripts/common/Packages.sh`, `scripts/common/package` |
| Dependabot | Dependency update service | Updates GitHub Actions ecosystem weekly. | GitHub-managed service. | Low | `.github/dependabot.yml` |

### 2) Data Stores

| Store | Role | Access layer | Key risk | Evidence |
|------|------|--------------|----------|----------|
| GitHub Actions cache | Build acceleration. | `actions/cache@v5`; cleanup through GitHub REST API in `actions/github-script@v8`. | Cache key churn or stale toolchain artifacts can affect build time/correctness; real deletion requires `prefix` or `ref`. | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub Artifacts | Compile logs and firmware outputs. | `actions/upload-artifact@v7`. | Retention is 14 days. | `.github/workflows/firmware-build.yml` |
| GitHub Releases | Optional firmware distribution. | `ncipollo/release-action@v1`. | Release tags are unique and not updated in place; only single-profile publishes become GitHub Latest. | `.github/workflows/firmware-build.yml`, `scripts/ci/release-maintenance.sh` |

### 3) Secrets and Credentials Handling

- Credential sources: GitHub-provided `GITHUB_TOKEN` / `secrets.GITHUB_TOKEN`.
- Hardcoding checks: source URLs, branches, profile ids, and package repos are committed as build config; no plaintext API secrets are present in repository files.
- Rotation or lifecycle notes: `GITHUB_TOKEN` is GitHub-managed; `[TODO]` no custom secret rotation policy is documented.

### 4) Reliability and Failure Behavior

- Compile retries: parallel `make`, serial `make`, then verbose serial `make V=s`.
- Firmware configs enable BBR and optional SQM/CAKE/IFB support for better WAN throughput and latency stability.
- x86 profiles include Intel/AMD microcode for CPU errata mitigation.
- Release publishing is disabled by default and optional via `release=true`.
- Multi-profile publishing does not update the GitHub Latest release marker.
- Cache maintenance defaults to dry-run and refuses real deletion unless `prefix` or `ref` narrows the scope.
- The update-checker and cleanup workflows were removed from the default architecture to reduce hidden side effects.
- No general retry/backoff wrapper exists for network-heavy source/feed/package operations.

### 5) Observability for Integrations

- Build logs include runner summary, profile/source summary, compile log artifact, and failure context.
- Release notes include source commit, profile hash, workflow run, default access, and artifact table.
- No metrics/tracing integration exists.

### 6) Evidence

- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `.github/dependabot.yml`
- `devices/profiles.yml`
- `scripts/common/Packages.sh`
- `scripts/ci/release-maintenance.sh`
