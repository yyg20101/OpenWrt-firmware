# Remove GecoOS AC Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `gecoosac` from the required firmware set so `x86_64_LEDE` can build and publish without maintaining the broken external `laipeng668/luci-app-gecoosac` overlay.

**Architecture:** Treat `gecoosac` as a removed optional capability, not as a package-source bug to patch locally. The fix removes the config request and overlay source, then adds a small validator so the package is not reintroduced accidentally while keeping `kenzok8/small`, PassWall, HomeProxy, LuCI Chinese, Samba4, SQM, and x86 guardrails unchanged.

**Tech Stack:** Bash CI scripts, OpenWrt `.config` fragments, GitHub Actions workflows, `gh` CLI.

---

## File Structure

- Modify `scripts/common/config/base.config`: remove the shared `CONFIG_PACKAGE_luci-app-gecoosac=y` selection.
- Modify `scripts/common/package`: remove the `laipeng668/luci-app-gecoosac` overlay call only.
- Create `scripts/ci/validate-gecoosac-removed.sh`: fail if active config or package overlay reintroduces `gecoosac`.
- Modify `.github/workflows/ci-lint.yml`: run the new validator in CI Lint.
- Modify `README.md`: list the validator in local validation commands.
- Modify `docs/ci-workflow-architecture.md`: remove `gecoosac` from described selected overlay examples if present.
- Modify `docs/superpowers/specs/2026-06-06-openwrt-config-guardrails-design.md`: remove `gecoosac` from current required/effective package evidence.
- Modify `plan/upgrade-openwrt-firmware-performance-stability-1.md`: record the removal and update historical evidence text.

## Task 1: Prove Current GecoOS AC Requirement Exists

**Files:**
- Inspect: `scripts/common/config/base.config`
- Inspect: `scripts/common/package`

- [ ] **Step 1: Run the negative pre-check**

Run:

```bash
if rg -n 'CONFIG_PACKAGE_luci-app-gecoosac=y|laipeng668/luci-app-gecoosac|UPDATE_PACKAGE "luci-app-gecoosac"' scripts/common/config/base.config scripts/common/package; then
  echo "gecoosac is still required"
  exit 1
fi
```

Expected: FAIL with matches in `scripts/common/config/base.config` and `scripts/common/package`.

## Task 2: Remove GecoOS AC Config And Overlay

**Files:**
- Modify: `scripts/common/config/base.config`
- Modify: `scripts/common/package`

- [ ] **Step 1: Remove the config request**

Edit `scripts/common/config/base.config` so the LuCI applications block no longer contains this line:

```text
CONFIG_PACKAGE_luci-app-gecoosac=y
```

The surrounding block should contain:

```text
# LuCI applications
CONFIG_PACKAGE_luci-app-autoreboot=y
CONFIG_PACKAGE_luci-app-ddns-go=y
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-dockerman=y
CONFIG_PACKAGE_luci-app-homeproxy=y
CONFIG_PACKAGE_luci-app-mini-diskmanager=y
CONFIG_PACKAGE_luci-app-partexp=y
CONFIG_PACKAGE_luci-app-passwall=y
```

- [ ] **Step 2: Remove the overlay call**

Edit `scripts/common/package` so the shared overlay block no longer contains this line:

```bash
UPDATE_PACKAGE "luci-app-gecoosac" "laipeng668/luci-app-gecoosac" "main" "all" "gecoosac"
```

The start of the shared overlay block should contain:

```bash
case "${SOURCE_REPO:-}" in
  lede|immortalwrt|openwrt-6.x)
  UPDATE_PACKAGE "luci-app-mini-diskmanager" "4IceG/luci-app-mini-diskmanager" "main" "all"
  UPDATE_PACKAGE "luci-app-partexp" "sirpdboy/luci-app-partexp" "main" "all"
  UPDATE_PACKAGE "luci-app-wolplus" "animegasan/luci-app-wolplus" "main" "root"
```

- [ ] **Step 3: Verify the removal check now passes**

Run:

```bash
if rg -n 'CONFIG_PACKAGE_luci-app-gecoosac=y|laipeng668/luci-app-gecoosac|UPDATE_PACKAGE "luci-app-gecoosac"' scripts/common/config/base.config scripts/common/package; then
  echo "ERROR: gecoosac is still required" >&2
  exit 1
fi
echo "gecoosac removal check passed"
```

Expected: PASS with `gecoosac removal check passed`.

## Task 3: Add A Permanent Removal Validator

**Files:**
- Create: `scripts/ci/validate-gecoosac-removed.sh`
- Modify: `.github/workflows/ci-lint.yml`
- Modify: `README.md`

- [ ] **Step 1: Create the validator**

Create `scripts/ci/validate-gecoosac-removed.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
CONFIG_FILE="${ROOT_DIR}/scripts/common/config/base.config"
PACKAGE_OVERLAY="${ROOT_DIR}/scripts/common/package"

if [ ! -f "${CONFIG_FILE}" ]; then
  echo "ERROR: missing config file: ${CONFIG_FILE}" >&2
  exit 1
fi

if [ ! -f "${PACKAGE_OVERLAY}" ]; then
  echo "ERROR: missing package overlay script: ${PACKAGE_OVERLAY}" >&2
  exit 1
fi

if rg -n 'CONFIG_PACKAGE_luci-app-gecoosac=y' "${CONFIG_FILE}"; then
  echo "ERROR: gecoosac must not be selected in base.config" >&2
  exit 1
fi

if rg -n 'laipeng668/luci-app-gecoosac|UPDATE_PACKAGE "luci-app-gecoosac"' "${PACKAGE_OVERLAY}"; then
  echo "ERROR: gecoosac overlay must not be configured" >&2
  exit 1
fi

echo "GecoOS AC removal validation passed."
```

- [ ] **Step 2: Make the validator executable**

Run:

```bash
chmod +x scripts/ci/validate-gecoosac-removed.sh
```

Expected: command exits 0.

- [ ] **Step 3: Run the validator**

Run:

```bash
bash scripts/ci/validate-gecoosac-removed.sh
```

Expected: PASS with `GecoOS AC removal validation passed.`

- [ ] **Step 4: Add the validator to CI Lint**

In `.github/workflows/ci-lint.yml`, add this step after `Validate LEDE Small Overlay Policy / 校验 LEDE Small 覆盖策略`:

```yaml
      - name: Validate GecoOS AC Removal / 校验 GecoOS AC 移除策略
        run: |
          set -euo pipefail
          bash scripts/ci/validate-gecoosac-removed.sh
```

- [ ] **Step 5: Add the validator to README local validation**

In `README.md`, add:

```bash
bash scripts/ci/validate-gecoosac-removed.sh
```

immediately after:

```bash
bash scripts/ci/validate-lede-small-overlay.sh
```

## Task 4: Update Documentation

**Files:**
- Modify: `docs/ci-workflow-architecture.md`
- Modify: `docs/superpowers/specs/2026-06-06-openwrt-config-guardrails-design.md`
- Modify: `plan/upgrade-openwrt-firmware-performance-stability-1.md`

- [ ] **Step 1: Update architecture docs**

In `docs/ci-workflow-architecture.md`, keep the `kenzok8/small` and PassWall overlay explanation. Do not list `gecoosac` as a selected third-party overlay.

- [ ] **Step 2: Update guardrails evidence**

In `docs/superpowers/specs/2026-06-06-openwrt-config-guardrails-design.md`, update the package evidence bullet so it states that `gecoosac` has been intentionally removed from the required set.

Use this wording:

```markdown
- `scripts/common/package` seeds LEDE builds from `kenzok8/small@master`, overlays selected third-party packages from GitHub repositories, and keeps the official PassWall package/app overlay for all supported source trees. `luci-app-gecoosac` has been intentionally removed from the requested set after the external overlay failed the LEDE release build.
```

- [ ] **Step 3: Update the performance plan evidence**

In `plan/upgrade-openwrt-firmware-performance-stability-1.md`, update the evidence text that lists `luci-app-gecoosac` as requested/effective. Replace it with text that says `luci-app-gecoosac` was removed after run `28097015786` failed in `package/gecoosac` due to the missing parent `LICENSE`.

## Task 5: Run Local Validation

**Files:**
- Validate repository state only.

- [ ] **Step 1: Run static validators**

Run:

```bash
bash scripts/ci/validate-profiles.sh
bash scripts/ci/validate-lede-small-overlay.sh
bash scripts/ci/validate-gecoosac-removed.sh
bash scripts/ci/validate-passwall-overlay.sh
bash scripts/ci/validate-cache-key-policy.sh
bash scripts/ci/validate-luci-zh-cn-config.sh
```

Expected: all commands exit 0.

- [ ] **Step 2: Run fixture tests**

Run:

```bash
bash scripts/ci/test-config-audit.sh
bash scripts/ci/test-config-feeds.sh
```

Expected: both commands exit 0.

- [ ] **Step 3: Run syntax and whitespace checks**

Run:

```bash
ruby -e "require 'yaml'; Dir['.github/workflows/*.yml'].each { |f| YAML.load_file(f) }"
find scripts -type f -name "*.sh" -print0 | xargs -0 -n1 bash -n
git diff --check
```

Expected: all commands exit 0 and print no errors.

## Task 6: Commit, Push, And Re-run LEDE Release Build

**Files:**
- Commit all files changed by Tasks 2 through 4.

- [ ] **Step 1: Inspect final diff**

Run:

```bash
git status --short --branch
git diff --stat
```

Expected: only the intended config, overlay, validator, workflow, README, and docs files are changed.

- [ ] **Step 2: Commit implementation**

Run:

```bash
git add scripts/common/config/base.config scripts/common/package scripts/ci/validate-gecoosac-removed.sh .github/workflows/ci-lint.yml README.md docs/ci-workflow-architecture.md docs/superpowers/specs/2026-06-06-openwrt-config-guardrails-design.md plan/upgrade-openwrt-firmware-performance-stability-1.md
git commit -m "build: remove gecoosac from firmware baseline"
```

Expected: commit succeeds.

- [ ] **Step 3: Push main**

Run:

```bash
git push origin main
```

Expected: push succeeds.

- [ ] **Step 4: Trigger LEDE release build**

Run:

```bash
gh workflow run firmware-ci.yml --repo yyg20101/OpenWrt-firmware --ref main -f target=x86_64_LEDE -f release=true
```

Expected: command returns a GitHub Actions run URL or exits 0.

- [ ] **Step 5: Verify remote run starts on the pushed commit**

Run:

```bash
gh run list --repo yyg20101/OpenWrt-firmware --workflow firmware-ci.yml --limit 1
```

Expected: latest run is `Firmware CI / x86_64_LEDE` on `main`.
