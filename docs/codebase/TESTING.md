# Testing Patterns

## Core Sections (Required)

### 1) Test Stack and Commands

- Primary test framework: no unit test framework is configured.
- Assertion/mocking tools: none configured.
- Commands:

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
bash scripts/ci/validate-cache-maintenance.sh
bash scripts/ci/validate-release-maintenance.sh
bash scripts/ci/test-artifacts-release.sh
bash scripts/ci/test-config-audit.sh
bash scripts/ci/test-config-feeds.sh
bash scripts/ci/profiles.sh matrix all "" "$PWD"
```

### 2) Test Layout

- Test file placement pattern: no `test/`, `tests/`, `spec/`, or equivalent test directory is present.
- Naming convention: `[TODO]` no test naming convention exists.
- Setup files and where they run: `.github/workflows/ci-lint.yml` runs validation on pull requests and pushes touching workflows, scripts, devices, or docs.

### 3) Test Scope Matrix

| Scope | Covered? | Typical target | Notes |
|-------|----------|----------------|-------|
| Unit | No | `[TODO]` | No unit framework or test files are present. |
| Integration | Partial | Workflow/script/profile contracts | CI lint validates YAML, shell syntax, profile schema, matrix generation, Dependabot coverage, and artifact/Release fixture behavior. |
| E2E | Manual/CI workflow | Full firmware build | `Firmware CI` performs real source clone, feeds update, compile, artifacts, and optional Release. |

### 4) Mocking and Isolation Strategy

- Main mocking approach: none configured.
- Isolation guarantees: GitHub Actions jobs run on fresh hosted runners; build source is freshly cloned per profile.
- Common failure modes: upstream source changes, feed/package repository changes, network failures, runner image changes, and profile config mistakes.

### 5) Coverage and Quality Signals

- Coverage tool + threshold: none configured.
- Current reported coverage: `[TODO]` not applicable.
- Known gaps: no fixture tests exercise every shell subcommand; artifact pruning, Release body generation, Cache Maintenance guardrails, and Release Maintenance guardrails now have focused checks.

### 6) Evidence

- `.github/workflows/ci-lint.yml`
- `.github/workflows/firmware-ci.yml`
- `.github/workflows/firmware-build.yml`
- `scripts/ci/validate-profiles.sh`
- `scripts/ci/validate-cache-maintenance.sh`
- `scripts/ci/validate-release-maintenance.sh`
- `scripts/ci/test-artifacts-release.sh`
- `scripts/ci/test-config-audit.sh`
- `scripts/ci/test-config-feeds.sh`
- `scripts/ci/profiles.sh`
- `docs/firmware-ci-prd.md`
