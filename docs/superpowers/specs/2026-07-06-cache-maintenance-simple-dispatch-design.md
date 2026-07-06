# Cache Maintenance Simple Dispatch Design

## Context

`Cache Maintenance` currently has a daily scheduled cleanup and a manual `workflow_dispatch` entry. The cleanup script already supports artifacts, caches, and historical workflow runs with stable defaults.

The manual GitHub Actions "Run workflow" dialog exposes too many implementation details:

- cache age
- cache prefix
- cache ref
- cache keep count
- artifact age
- protected firmware run count
- workflow-run age
- workflow-run keep count
- dry-run boolean

Recent manual runs succeeded, so the issue is not execution reliability. The issue is operator experience: too many choices make the cleanup action harder to understand and easier to misuse.

## Goal

Simplify the manual `Cache Maintenance` dialog to one required choice:

- `preview`: list cleanup candidates without deleting anything.
- `cleanup`: apply the existing default cleanup policy immediately.

## Non-Goals

- Do not change the cleanup script's retention defaults.
- Do not change the scheduled daily cleanup behavior.
- Do not change artifact, cache, or workflow-run candidate selection logic.
- Do not delete releases, tags, source files, Release assets, artifacts, caches, or workflow runs as part of implementation.
- Do not change workflow, job, step names, logs, or summaries.

## Design

Update `.github/workflows/cache-maintenance.yml` under `on.workflow_dispatch.inputs`.

Replace the current nine manual inputs with one `choice` input:

```yaml
mode:
  description: "执行模式：preview 仅预览不删除；cleanup 按默认策略立即清理"
  required: true
  default: "preview"
  type: choice
  options:
    - preview
    - cleanup
```

The workflow should map manual mode to `DRY_RUN`:

- `mode=preview` -> `DRY_RUN=true`
- `mode=cleanup` -> `DRY_RUN=false`

For scheduled runs, there is no `mode` input. Scheduled runs should continue using `DRY_RUN=false`.

All hidden policy values remain fixed in the workflow environment:

- `ARTIFACT_OLDER_THAN_DAYS=2`
- `ARTIFACT_KEEP_LATEST_RUNS=1`
- `CACHE_OLDER_THAN_DAYS=7`
- `CACHE_PREFIX=""`
- `CACHE_REF=refs/heads/main`
- `CACHE_KEEP_LATEST=1`
- `WORKFLOW_RUN_OLDER_THAN_DAYS=7`
- `WORKFLOW_RUN_KEEP_LATEST_PER_WORKFLOW=3`

## Capacity Assessment

The current default policy remains acceptable for the repository's present size:

- Artifacts: about 3.59 GiB.
- Caches: about 3.11 GiB.
- Always-retained footprint: about 6.7 GiB.

The major future risk is not the manual dispatch shape. It is target expansion: if one protected latest firmware-producing run starts containing many large firmware artifacts, the protected footprint could grow. That should be handled later as a separate storage-threshold policy.

## Validation

After implementation:

1. Parse workflow YAML locally.
2. Run `bash scripts/ci/validate-cache-maintenance.sh`.
3. Run `git diff --check`.
4. Push and confirm remote `CI Lint` passes.
5. Run one manual `Cache Maintenance` dispatch with `mode=preview` to verify the simplified input works without deleting anything.
