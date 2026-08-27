# External Integrations

## Core Sections (Required)

### 1) Integration Inventory

| System | Type (API/DB/Queue/etc) | Purpose | Auth model | Criticality | Evidence |
|--------|---------------------------|---------|------------|-------------|----------|
| GitHub Actions | CI/CD platform | Runs build and lint workflows; old workflow runs are pruned by scheduled storage maintenance. | GitHub Actions context. | High | `.github/workflows/*.yml`, `scripts/ci/actions-storage-maintenance.sh` |
| GitHub Actions Cache | Cache service | Restores ccache and build accelerator directories; supports scheduled and filtered manual cleanup. | GitHub Actions context. | Medium | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub Artifacts | Artifact storage | Stores short-lived compile logs, diagnostics, and firmware outputs; scheduled cleanup protects the latest firmware-producing run. | GitHub Actions context. | High | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub Releases | Release hosting | Optionally publishes successful firmware builds and supports filtered manual cleanup. | `secrets.GITHUB_TOKEN`. | High | `.github/workflows/firmware-build.yml`, `.github/workflows/release-maintenance.yml`, `scripts/ci/release-maintenance.sh` |
| External OpenWrt source repositories | Git repositories | Cloned and compiled per profile. | Public HTTPS clone. | High | `devices/profiles.yml`, `.github/workflows/firmware-build.yml` |
| OpenWrt/ImmortalWrt build environment script | Remote shell script | Initializes runner build prerequisites. | Public HTTPS fetch through `curl`. | High | `.github/workflows/firmware-build.yml` |
| OpenWrt feeds | Package feed system | Updates and installs package feeds before build. | Public network access from cloned source. | High | `.github/workflows/firmware-build.yml` |
| GitHub package repositories | Git/API downloads | `scripts/common/Packages.sh` clones package repos and may query release metadata. | Public HTTPS/API. | Medium | `scripts/common/Packages.sh`, `scripts/common/package` |
| Dependabot | Dependency update service | Updates GitHub Actions ecosystem weekly. | GitHub-managed service. | Low | `.github/dependabot.yml` |

### 2) Data Stores

| Store | Role | Access layer | Key risk | Evidence |
|------|------|--------------|----------|----------|
| GitHub Actions cache | Build acceleration. | `actions/cache@v6`; cleanup through GitHub REST API in `scripts/ci/actions-storage-maintenance.sh`. | Cache key churn or stale toolchain artifacts can affect build time/correctness; fixed cleanup protects the newest cache per group. | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub Artifacts | Compile logs, diagnostics, and firmware outputs. | `actions/upload-artifact@v7`; cleanup through GitHub REST API in `scripts/ci/actions-storage-maintenance.sh`. | Large firmware artifacts can exhaust account storage if retention or cleanup fails. | `.github/workflows/firmware-build.yml`, `.github/workflows/cache-maintenance.yml` |
| GitHub workflow runs | Logs and run metadata. | GitHub REST API in `scripts/ci/actions-storage-maintenance.sh`. | Historical runs can accumulate noisy logs and make storage maintenance harder to audit. | `.github/workflows/cache-maintenance.yml`, `scripts/ci/actions-storage-maintenance.sh` |
| GitHub Releases | Optional firmware distribution. | `ncipollo/release-action@v1`; filtered cleanup through GitHub REST API in `actions/github-script@v9`. | Release tags are stable per profile/source/branch and successful rebuilds replace the current asset set; only single-profile publishes become GitHub Latest. | `.github/workflows/firmware-build.yml`, `.github/workflows/release-maintenance.yml`, `scripts/ci/release-maintenance.sh` |

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
- A successful rebuild updates the existing profile/source/branch Release and replaces old Release assets.
- Cache maintenance defaults to `preview` for manual runs; `cleanup` applies the fixed `main` branch retention policy.
- Scheduled Actions storage maintenance prunes artifacts, caches, and historical workflow runs while protecting the current run and latest firmware-producing run.
- The update-checker workflow was removed from the default architecture to reduce hidden side effects.
- Runner package installation, build environment script download, source clone, feeds update/install, and package overlay GitHub operations use retry/backoff wrappers.

### 5) Observability for Integrations

- Build logs include runner summary, profile/source summary, compile log artifact, and failure context.
- Release notes include source commit, profile hash, workflow run, default access, artifact table, package archive summary, and package source refs when package overlays run.
- No metrics/tracing integration exists.

### 6) Evidence

- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `.github/workflows/release-maintenance.yml`
- `.github/dependabot.yml`
- `devices/profiles.yml`
- `scripts/common/Packages.sh`
- `scripts/ci/release-maintenance.sh`
