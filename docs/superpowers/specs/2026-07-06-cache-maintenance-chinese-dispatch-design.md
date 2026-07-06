# Cache Maintenance Dispatch Chinese Descriptions Design

## Context

`Cache Maintenance` is already responsible for scheduled GitHub Actions storage cleanup. It prunes artifacts, caches, and historical workflow runs through `scripts/ci/actions-storage-maintenance.sh`.

The remaining usability issue is the manual GitHub Actions "Run workflow" dialog. Its `workflow_dispatch` input descriptions are currently English, while the operator-facing repo documentation and normal workflow usage are Chinese.

Current storage data shows the default cleanup policy is acceptable for the current repository size:

- Artifacts: 8 items, about 3.59 GiB.
- Caches: 4 items, about 3.11 GiB.
- Workflow runs: 16 items.
- Latest dry-run: 0 artifact candidates, 0 cache candidates, 2 workflow-run candidates.

The always-retained footprint is mainly the latest firmware-producing run plus the newest cache per cache group, currently about 6.7 GiB. This should not exceed the quota in the current x86-focused setup. Future expansion to more device targets may require a stricter policy, but that is outside this change.

## Goal

Make the manual `Cache Maintenance` workflow dialog easier for Chinese operators to understand without changing cleanup behavior.

## Non-Goals

- Do not change input names, types, defaults, or cleanup logic.
- Do not change workflow, job, or step names.
- Do not translate script logs or GitHub step summaries.
- Do not change artifact, cache, or workflow-run retention thresholds.
- Do not delete releases, tags, source files, or Release assets.

## Design

Update only `.github/workflows/cache-maintenance.yml` under `on.workflow_dispatch.inputs.*.description`.

The descriptions should be concise Chinese operational text:

- `older_than_days`: cache age by last access time.
- `prefix`: optional cache-key prefix filter.
- `ref`: optional cache ref filter, usually `refs/heads/main`.
- `keep_latest`: newest matched caches to keep per cache group.
- `artifact_older_than_days`: non-protected artifact age by creation time.
- `artifact_keep_latest_runs`: newest firmware-producing runs whose artifacts are protected.
- `workflow_run_older_than_days`: completed workflow-run age by creation time.
- `workflow_run_keep_latest_per_workflow`: newest runs kept per workflow.
- `dry_run`: list-only mode that does not delete anything.

## Capacity Assessment

The current defaults are acceptable for the repository's present size:

- Artifacts are protected only for the latest firmware-producing run.
- Cache cleanup keeps one newest cache per group under the selected ref.
- Workflow-run cleanup keeps the current run, the latest firmware-producing run, and the newest runs per workflow.

The main capacity risk is future device expansion. If a single latest firmware-producing run begins to contain many large firmware artifacts, the protected latest-run footprint could grow enough to approach quota even with daily cleanup. That should be handled as a separate policy change after new targets are added.

## Validation

After implementation:

1. Run local workflow YAML parsing.
2. Run `bash scripts/ci/validate-cache-maintenance.sh`.
3. Run `git diff --check`.
4. Push and confirm remote `CI Lint` passes.

No live cleanup run is required because only UI descriptions change.
