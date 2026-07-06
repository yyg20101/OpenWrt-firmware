# Cache Maintenance Simple Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the manual `Cache Maintenance` workflow dialog's many parameters with one `mode` choice while keeping scheduled cleanup behavior and retention defaults unchanged.

**Architecture:** `.github/workflows/cache-maintenance.yml` owns the manual dispatch schema and passes fixed policy values to `scripts/ci/actions-storage-maintenance.sh`. `scripts/ci/validate-cache-maintenance.sh` is the guard that must be updated to enforce the simplified dispatch contract.

**Tech Stack:** GitHub Actions YAML, Bash, Ruby YAML parser, GitHub Actions expressions.

## Global Constraints

- Manual dispatch has exactly one input named `mode`.
- `mode` is a required `choice` input with default `preview` and options `preview` and `cleanup`.
- `mode=preview` maps to `DRY_RUN=true`.
- `mode=cleanup` maps to `DRY_RUN=false`.
- Scheduled runs continue using `DRY_RUN=false`.
- Do not change the cleanup script's retention defaults.
- Do not change artifact, cache, or workflow-run candidate selection logic.
- Do not delete releases, tags, source files, Release assets, artifacts, caches, or workflow runs as part of implementation.
- Do not change workflow, job, step names, logs, or summaries.

---

### Task 1: Simplify Cache Maintenance Manual Dispatch

**Files:**
- Modify: `.github/workflows/cache-maintenance.yml`
- Modify: `scripts/ci/validate-cache-maintenance.sh`

**Interfaces:**
- Consumes: `workflow_dispatch.inputs.mode` from GitHub Actions manual runs.
- Produces: environment variables consumed by `scripts/ci/actions-storage-maintenance.sh`: `DRY_RUN`, `ARTIFACT_OLDER_THAN_DAYS`, `ARTIFACT_KEEP_LATEST_RUNS`, `CACHE_OLDER_THAN_DAYS`, `CACHE_PREFIX`, `CACHE_REF`, `CACHE_KEEP_LATEST`, `WORKFLOW_RUN_OLDER_THAN_DAYS`, `WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW`, and `CURRENT_RUN_ID`.

- [ ] **Step 1: Inspect current workflow and guard**

Run:

```bash
sed -n '1,120p' .github/workflows/cache-maintenance.yml
sed -n '1,120p' scripts/ci/validate-cache-maintenance.sh
```

Expected: workflow has nine manual inputs (`older_than_days`, `prefix`, `ref`, `keep_latest`, `artifact_older_than_days`, `artifact_keep_latest_runs`, `workflow_run_older_than_days`, `workflow_run_keep_latest_per_workflow`, `dry_run`), and the guard checks those inputs.

- [ ] **Step 2: Replace manual dispatch inputs with `mode`**

In `.github/workflows/cache-maintenance.yml`, replace the entire `workflow_dispatch.inputs` map with:

```yaml
    inputs:
      mode:
        description: "执行模式：preview 仅预览不删除；cleanup 按默认策略立即清理"
        required: true
        default: "preview"
        type: choice
        options:
          - preview
          - cleanup
```

Keep the existing `schedule`, `permissions`, job name, runner, checkout step, and cleanup step name unchanged.

- [ ] **Step 3: Make cleanup policy fixed in workflow env**

In `.github/workflows/cache-maintenance.yml`, replace the cleanup step `env` block with exactly:

```yaml
        env:
          GH_TOKEN: ${{ github.token }}
          REPOSITORY: ${{ github.repository }}
          DRY_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.mode == 'preview' && 'true' || 'false' }}
          ARTIFACT_OLDER_THAN_DAYS: "2"
          ARTIFACT_KEEP_LATEST_RUNS: "1"
          CACHE_OLDER_THAN_DAYS: "7"
          CACHE_PREFIX: ""
          CACHE_REF: refs/heads/main
          CACHE_KEEP_LATEST: "1"
          WORKFLOW_RUN_OLDER_THAN_DAYS: "7"
          WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW: "3"
          CURRENT_RUN_ID: ${{ github.run_id }}
```

This preserves scheduled cleanup behavior because non-`workflow_dispatch` events set `DRY_RUN=false`.

- [ ] **Step 4: Update guard input checks**

In `scripts/ci/validate-cache-maintenance.sh`, replace the old manual-input assertions:

```ruby
fail!("dry_run must default to true") unless inputs.dig("dry_run", "default") == true
fail!("keep_latest must default to 1") unless inputs.dig("keep_latest", "default").to_s == "1"
fail!("prefix input must exist") unless inputs.key?("prefix")
fail!("ref input must exist") unless inputs.key?("ref")
fail!("ref input must default to refs/heads/main") unless inputs.dig("ref", "default") == "refs/heads/main"
fail!("artifact_older_than_days input must exist") unless inputs.key?("artifact_older_than_days")
fail!("artifact_keep_latest_runs input must exist") unless inputs.key?("artifact_keep_latest_runs")
fail!("artifact_keep_latest_runs must default to 1") unless inputs.dig("artifact_keep_latest_runs", "default").to_s == "1"
fail!("workflow_run_older_than_days input must exist") unless inputs.key?("workflow_run_older_than_days")
fail!("workflow_run_older_than_days must default to 7") unless inputs.dig("workflow_run_older_than_days", "default").to_s == "7"
fail!("workflow_run_keep_latest_per_workflow input must exist") unless inputs.key?("workflow_run_keep_latest_per_workflow")
fail!("workflow_run_keep_latest_per_workflow must default to 3") unless inputs.dig("workflow_run_keep_latest_per_workflow", "default").to_s == "3"
```

with:

```ruby
fail!("mode input must exist") unless inputs.key?("mode")
fail!("mode must default to preview") unless inputs.dig("mode", "default") == "preview"
fail!("mode must be a choice input") unless inputs.dig("mode", "type") == "choice"
fail!("mode options must be preview and cleanup") unless inputs.dig("mode", "options") == ["preview", "cleanup"]

forbidden_inputs = %w[
  older_than_days
  prefix
  ref
  keep_latest
  artifact_older_than_days
  artifact_keep_latest_runs
  workflow_run_older_than_days
  workflow_run_keep_latest_per_workflow
  dry_run
]
forbidden_inputs.each do |input|
  fail!("#{input} input must not be exposed in workflow_dispatch") if inputs.key?(input)
end
```

- [ ] **Step 5: Update guard env checks**

In `scripts/ci/validate-cache-maintenance.sh`, replace the old body checks:

```ruby
fail!("workflow inputs must have scheduled cache defaults") unless body.include?("CACHE_OLDER_THAN_DAYS: ${{ inputs.older_than_days || '7' }}")
fail!("workflow inputs must have scheduled workflow run defaults") unless body.include?("WORKFLOW_RUN_OLDER_THAN_DAYS: ${{ inputs.workflow_run_older_than_days || '7' }}")
fail!("dry_run must be forwarded to maintenance script") unless body.include?("DRY_RUN: ${{ inputs.dry_run || 'false' }}")
```

with:

```ruby
fail!("preview mode must map to dry-run") unless body.include?("DRY_RUN: ${{ github.event_name == 'workflow_dispatch' && inputs.mode == 'preview' && 'true' || 'false' }}")
fail!("workflow must keep fixed artifact age default") unless body.include?('ARTIFACT_OLDER_THAN_DAYS: "2"')
fail!("workflow must keep fixed protected firmware run default") unless body.include?('ARTIFACT_KEEP_LATEST_RUNS: "1"')
fail!("workflow must keep fixed cache age default") unless body.include?('CACHE_OLDER_THAN_DAYS: "7"')
fail!("workflow must keep fixed cache prefix default") unless body.include?('CACHE_PREFIX: ""')
fail!("workflow must keep fixed cache ref default") unless body.include?("CACHE_REF: refs/heads/main")
fail!("workflow must keep fixed cache group retention default") unless body.include?('CACHE_KEEP_LATEST: "1"')
fail!("workflow must keep fixed workflow run age default") unless body.include?('WORKFLOW_RUN_OLDER_THAN_DAYS: "7"')
fail!("workflow must keep fixed workflow run retention default") unless body.include?('WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW: "3"')
```

Do not change the existing script checks for pagination, deletion by id, protected firmware runs, current run protection, latest runs per workflow, or cache group retention.

- [ ] **Step 6: Verify the diff shape**

Run:

```bash
git diff -- .github/workflows/cache-maintenance.yml scripts/ci/validate-cache-maintenance.sh
```

Expected:

- `.github/workflows/cache-maintenance.yml` removes the eight advanced inputs plus `dry_run`, adds only `mode`, and changes only env values for fixed defaults and mode-derived `DRY_RUN`.
- `scripts/ci/validate-cache-maintenance.sh` now requires `mode` and forbids the old advanced inputs.
- `scripts/ci/actions-storage-maintenance.sh` is unchanged.

- [ ] **Step 7: Run local validation**

Run:

```bash
ruby -e "require 'yaml'; YAML.load_file('.github/workflows/cache-maintenance.yml')"
bash scripts/ci/validate-cache-maintenance.sh
git diff --check
```

Expected:

```text
Cache Maintenance workflow guard passed.
```

`ruby` and `git diff --check` should produce no output and exit 0.

- [ ] **Step 8: Commit implementation**

Run:

```bash
git add .github/workflows/cache-maintenance.yml scripts/ci/validate-cache-maintenance.sh
git commit -m "ci: simplify cache maintenance dispatch inputs"
```

Expected: commit succeeds with only `.github/workflows/cache-maintenance.yml` and `scripts/ci/validate-cache-maintenance.sh` changed.

- [ ] **Step 9: Push and verify remote behavior**

Run:

```bash
git push origin main
gh run watch "$(gh run list -R yyg20101/OpenWrt-firmware --branch main --limit 1 --json databaseId --jq '.[0].databaseId')" -R yyg20101/OpenWrt-firmware --exit-status
gh workflow run cache-maintenance.yml -R yyg20101/OpenWrt-firmware --ref main -f mode=preview
```

Expected:

- Remote `CI Lint` passes.
- Manual `Cache Maintenance` dispatch accepts only `mode=preview`.
- The dispatched run is a dry-run and must not delete artifacts, caches, or workflow runs.
