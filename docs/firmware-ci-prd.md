# Firmware CI Refactor PRD

### 1. Executive Summary

- **Problem Statement**: Firmware builds are unstable, adding devices requires touching scattered files, workflow YAML is hard to review, and Release output is inconsistent.
- **Proposed Solution**: Rebuild the CI around a single declarative profile registry, dynamic build matrix generation, a thin dispatcher workflow, a reusable build workflow, local validation scripts, and standardized artifact/Release metadata.
- **Success Criteria**:
  - Adding a new enabled device requires one `devices/<profile-id>/.config` file and one `devices/profiles.yml` entry, with no workflow YAML edits.
  - `target=all` expands to every enabled profile in `devices/profiles.yml`.
  - Local validation commands pass for workflow YAML, shell syntax, profile schema, and Dependabot coverage.
  - Every successful build uploads a firmware artifact with `build.config`, `artifact-manifest.txt`, `Packages.tar.gz`, and `sha256sums.txt` when matching firmware files exist.
  - Every published Release includes profile, source, commit, profile hash, workflow run, default access, and artifact file table.

### 2. User Experience & Functionality

- **User Personas**:
  - Maintainer who adds or updates firmware targets.
  - Operator who manually triggers one profile or all profiles.
  - Debugger who investigates failed builds and needs logs plus source/config traceability.

- **User Stories**:
  - As a maintainer, I want to add a firmware profile in one registry so that device onboarding does not require editing multiple workflows.
  - As an operator, I want to trigger one profile or all enabled profiles so that manual builds are predictable.
  - As a debugger, I want compile logs and failure context uploaded so that build failures can be diagnosed without re-running blindly.
  - As a release consumer, I want standardized Release metadata so that I can identify source commit, device profile, default access, and included artifacts.

- **Acceptance Criteria**:
  - `bash scripts/ci/validate-profiles.sh` validates all profiles and fails on missing config files, malformed GitHub repo URLs, or missing required fields.
  - `bash scripts/ci/profiles.sh matrix all "" "$PWD"` emits JSON with all enabled profiles.
  - `firmware-ci.yml` accepts `target=<profile-id>` or `target=all` and delegates each matrix item to `firmware-build.yml`.
  - `firmware-build.yml` does not hard-code device ids.
  - Cache keys include source slug, branch, cache group, profile hash, and source commit hash.
  - Release publishing can be disabled per dispatch with `release=false`.

- **Non-Goals**:
  - No web UI for device management.
  - No automatic scheduled update checker in this iteration.
  - No automatic cleanup of old releases or workflow runs in this iteration.
  - No guarantee that upstream OpenWrt/feeds/package repositories are reproducible without pinning.

### 3. AI System Requirements (If Applicable)

- **Tool Requirements**: Not applicable.
- **Evaluation Strategy**: Not applicable.

### 4. Technical Specifications

- **Architecture Overview**:
  - `devices/profiles.yml` is the single source of truth for firmware profile metadata.
  - `scripts/ci/profiles.sh` validates profiles, emits matrix JSON, and exports profile values to `GITHUB_ENV` and `GITHUB_OUTPUT`.
  - `.github/workflows/firmware-ci.yml` resolves dispatch input into a matrix.
  - `.github/workflows/firmware-build.yml` performs the end-to-end build for one profile.
  - `scripts/ci/config-feeds.sh`, `build-artifacts.sh`, `detect-default-access.sh`, and `release-maintenance.sh` own reusable shell implementation.

- **Integration Points**:
  - GitHub Actions for workflow orchestration.
  - GitHub Actions Cache for ccache and build accelerator cache.
  - GitHub Artifacts for compile logs and firmware outputs.
  - GitHub Releases for optional published firmware.
  - External OpenWrt source repositories and feeds.

- **Security & Privacy**:
  - Workflow permissions are limited to `contents: write` and `actions: read` for build/release operations.
  - Release notes describe root password state, not plaintext passwords.
  - No custom secrets are required beyond GitHub-provided token context.
  - Remote source, feed, and package repositories remain supply-chain dependencies and should be pinned in future hardening work.

### 5. Risks & Roadmap

- **Phased Rollout**:
  - MVP: Declarative profiles, dynamic matrix, reusable build workflow, profile validation, standardized Release metadata.
  - v1.1: Add fixture tests for `profiles.sh`, `config-feeds.sh`, `build-artifacts.sh`, and `release-maintenance.sh`.
  - v2.0: Optional scheduled update checks, retention policy automation, package ref pinning, and per-profile build concurrency controls.

- **Technical Risks**:
  - GitHub runner image changes can break OpenWrt build prerequisites.
  - Upstream feeds/package repositories can change without local commits.
  - `target=all` can consume significant Actions minutes and cache quota.
  - Release publishing may fail if a tag already exists because releases are intentionally not updated in place.
