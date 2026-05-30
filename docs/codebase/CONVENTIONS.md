# Coding Conventions

## Core Sections (Required)

### 1) Naming Rules

| Item | Rule | Example | Evidence |
|------|------|---------|----------|
| Files | CI shell modules use kebab-case; workflows use firmware-domain names; shared assets keep existing OpenWrt-oriented names. | `build-artifacts.sh`, `firmware-build.yml`, `base.config` | `scripts/ci/`, `.github/workflows/`, `scripts/common/` |
| Functions/methods | Bash functions use lower_snake_case; package helper functions use UPPER_SNAKE names. | `prepare_feeds`, `generate_sha256_checksums`, `UPDATE_PACKAGE` | `scripts/ci/config-feeds.sh`, `scripts/ci/build-artifacts.sh`, `scripts/common/Packages.sh` |
| Types/interfaces | Not applicable; repository uses Bash/YAML/config files and no typed interfaces. | `[TODO]` no type declarations found | `scripts/ci/*.sh`, `.github/workflows/*.yml` |
| Constants/env vars | Workflow/script environment variables use UPPER_SNAKE_CASE; profile YAML uses lower_snake_case keys. | `PROFILE_ID`, `SOURCE_SLUG`, `source_repo`, `cache_group` | `scripts/ci/profiles.sh`, `devices/profiles.yml` |

### 2) Formatting and Linting

- Formatter: no formatter configuration is present.
- Linter/checks: `reviewdog/action-actionlint@v1`, Ruby YAML loading, `bash -n`, `validate-profiles.sh`, and `validate-dependabot-coverage.sh`.
- Run commands:

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-dependabot-coverage.sh
```

### 3) Import and Module Conventions

- Shell modules are invoked as executable scripts rather than sourced.
- Repository-relative paths are resolved from `GITHUB_WORKSPACE`/repository root.
- Profile data exported by `profiles.sh` is written to both `GITHUB_ENV` and `GITHUB_OUTPUT`.

### 4) Error and Logging Conventions

- Scripts generally use `set -euo pipefail`.
- Validation scripts fail fast with `ERROR:` messages.
- Build compilation intentionally disables `set -e` inside fallback attempts, then writes `status=success` or `status=failure`.
- Failure diagnostics use GitHub Actions group markers around compile log tail and verbose package rebuild.

### 5) Testing Conventions

- No unit test framework is configured.
- CI validation covers YAML syntax, shell syntax, profile schema, and Dependabot coverage.
- Fixture tests now cover artifact pruning, Release body generation, and Release Maintenance guardrails; broader shell subcommand fixtures remain a future hardening area.

### 6) Evidence

- `.github/workflows/ci-lint.yml`
- `docs/firmware-ci-prd.md`
- `scripts/ci/profiles.sh`
- `scripts/ci/build-artifacts.sh`
- `devices/profiles.yml`
