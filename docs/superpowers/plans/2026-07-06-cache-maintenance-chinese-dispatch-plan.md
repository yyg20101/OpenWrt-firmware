# Cache Maintenance Chinese Dispatch Text Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Translate only the manual `Cache Maintenance` workflow dispatch input descriptions into Chinese without changing behavior.

**Architecture:** The workflow already owns the GitHub Actions manual dispatch schema. This change updates only `workflow_dispatch.inputs.*.description` in `.github/workflows/cache-maintenance.yml`; the cleanup script, defaults, names, types, and deletion logic stay unchanged.

**Tech Stack:** GitHub Actions YAML, Ruby YAML parser, Bash guard scripts.

## Global Constraints

- Modify only input `description` text in `.github/workflows/cache-maintenance.yml`.
- Do not change input names, types, defaults, cleanup logic, workflow names, job names, step names, script logs, or summaries.
- Keep manual runs defaulting to dry-run.
- Keep scheduled runs using the current defaults.
- Do not delete releases, tags, source files, Release assets, artifacts, caches, or workflow runs as part of this change.

---

### Task 1: Translate Cache Maintenance Dispatch Descriptions

**Files:**
- Modify: `.github/workflows/cache-maintenance.yml`

**Interfaces:**
- Consumes: existing `workflow_dispatch.inputs` keys in `.github/workflows/cache-maintenance.yml`.
- Produces: same input keys and defaults, with Chinese `description` text.

- [ ] **Step 1: Inspect current descriptions**

Run:

```bash
sed -n '1,90p' .github/workflows/cache-maintenance.yml
```

Expected: output shows these English descriptions:

```yaml
description: "Delete caches not accessed for at least this many days"
description: "Only consider caches whose key starts with this prefix"
description: "Only consider caches for this ref, for example refs/heads/main"
description: "Keep this many newest matched caches even if they are old"
description: "Delete non-protected artifacts created at least this many days ago"
description: "Keep artifacts from this many newest firmware-producing runs"
description: "Delete completed workflow runs created at least this many days ago"
description: "Keep this many newest runs per workflow"
description: "List artifacts, caches, and workflow runs without deleting them"
```

- [ ] **Step 2: Replace only description values**

Edit `.github/workflows/cache-maintenance.yml` so the descriptions become exactly:

```yaml
older_than_days:
  description: "删除至少多少天未访问的缓存"
prefix:
  description: "仅处理缓存 key 以此前缀开头的缓存；留空表示不按前缀过滤"
ref:
  description: "仅处理指定 ref 的缓存，例如 refs/heads/main"
keep_latest:
  description: "每个缓存分组保留的最新缓存数量，即使这些缓存已超过清理天数"
artifact_older_than_days:
  description: "删除至少多少天前创建且未受保护的产物"
artifact_keep_latest_runs:
  description: "保留最近多少次产生 firmware 产物的运行记录及其产物"
workflow_run_older_than_days:
  description: "删除至少多少天前创建且已完成的 workflow 运行记录"
workflow_run_keep_latest_per_workflow:
  description: "每个 workflow 保留的最新运行记录数量"
dry_run:
  description: "仅列出将清理的产物、缓存和 workflow 运行记录，不实际删除"
```

Do not edit any neighboring `required`, `default`, or `type` lines.

- [ ] **Step 3: Verify only descriptions changed**

Run:

```bash
git diff -- .github/workflows/cache-maintenance.yml
```

Expected: diff changes only `description:` lines under `workflow_dispatch.inputs`.

- [ ] **Step 4: Run local validation**

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

- [ ] **Step 5: Commit implementation**

Run:

```bash
git add .github/workflows/cache-maintenance.yml
git commit -m "ci: localize cache maintenance dispatch descriptions"
```

Expected: commit succeeds with only `.github/workflows/cache-maintenance.yml` changed.
